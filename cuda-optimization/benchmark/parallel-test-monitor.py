#!/usr/bin/env python3
"""
Parallel Test Monitor for CUDA Version Testing
Monitors multiple test containers and collects results

Usage:
    Called automatically by docker-compose.test-matrix.yml
"""

import os
import json
import time
import requests
import docker
from datetime import datetime
from typing import Dict, List, Optional

SERVICES = os.getenv("SERVICES", "").split(",")
RESULTS_PATH = os.getenv("RESULTS_PATH", "/benchmark/parallel-test-results.json")
CHECK_INTERVAL = 10  # seconds
MAX_WAIT_TIME = 600  # 10 minutes


class ParallelTestMonitor:
    """Monitor parallel test execution and collect results"""

    def __init__(self, services: List[str]):
        self.services = self._parse_services(services)
        self.client = docker.from_env()
        self.results = {}
        self.start_time = time.time()

    def _parse_services(self, services: List[str]) -> Dict[str, int]:
        """Parse SERVICE:PORT format into dict"""
        parsed = {}
        for service_str in services:
            if ':' in service_str:
                name, port = service_str.split(':')
                parsed[name] = int(port)
        return parsed

    def check_service_health(self, service: str, port: int) -> tuple[bool, Optional[Dict]]:
        """Check if service is healthy and CUDA is available"""
        try:
            # Check container status
            container = self.client.containers.get(service)
            if container.status != 'running':
                return False, {"status": "not_running"}

            # Check CUDA availability
            exec_result = container.exec_run(
                ["python3", "-c",
                 "import torch; import json; print(json.dumps({'cuda': torch.cuda.is_available(), 'version': torch.__version__, 'gpu': torch.cuda.get_device_name(0) if torch.cuda.is_available() else None}))"]
            )

            if exec_result.exit_code == 0:
                cuda_info = json.loads(exec_result.output.decode())

                # Check if service endpoint is responding
                try:
                    response = requests.get(f"http://localhost:{port}/health", timeout=5)
                    endpoint_healthy = response.status_code == 200
                except:
                    endpoint_healthy = False

                return True, {
                    "status": "healthy",
                    "cuda_available": cuda_info['cuda'],
                    "pytorch_version": cuda_info['version'],
                    "gpu_name": cuda_info['gpu'],
                    "endpoint_healthy": endpoint_healthy
                }
            else:
                return False, {"status": "cuda_check_failed", "error": exec_result.output.decode()}

        except docker.errors.NotFound:
            return False, {"status": "container_not_found"}
        except Exception as e:
            return False, {"status": "error", "error": str(e)}

    def monitor_all_services(self):
        """Monitor all services until timeout or all complete"""
        print(f"Monitoring {len(self.services)} services...")
        print(f"Services: {', '.join(self.services.keys())}")
        print("")

        while True:
            elapsed = time.time() - self.start_time
            if elapsed > MAX_WAIT_TIME:
                print(f"\nTimeout reached ({MAX_WAIT_TIME}s)")
                break

            all_complete = True
            for service, port in self.services.items():
                if service not in self.results or not self.results[service].get('final', False):
                    healthy, info = self.check_service_health(service, port)

                    if healthy and info.get('cuda_available'):
                        self.results[service] = {
                            **info,
                            'final': True,
                            'check_time': datetime.now().isoformat()
                        }
                        print(f"✓ {service}: {info.get('status')} - PyTorch {info.get('pytorch_version')}")
                    else:
                        all_complete = False
                        if service not in self.results:
                            print(f"⏳ {service}: Waiting... ({elapsed:.0f}s)")

            if all_complete:
                print("\n✓ All services ready!")
                break

            time.sleep(CHECK_INTERVAL)

    def save_results(self):
        """Save results to JSON file"""
        output = {
            "timestamp": datetime.now().isoformat(),
            "total_time": time.time() - self.start_time,
            "services": self.results
        }

        with open(RESULTS_PATH, 'w') as f:
            json.dump(output, f, indent=2)

        print(f"\nResults saved to: {RESULTS_PATH}")

    def print_summary(self):
        """Print test summary"""
        print("\n" + "="*60)
        print("PARALLEL TEST SUMMARY")
        print("="*60)

        success_count = 0
        for service, result in self.results.items():
            if result.get('cuda_available'):
                success_count += 1
                status = "✓ SUCCESS"
            else:
                status = "✗ FAILED"

            print(f"{service:20s} {status:12s} PyTorch: {result.get('pytorch_version', 'N/A')}")

        print(f"\nTotal time: {time.time() - self.start_time:.1f}s")
        print(f"Success rate: {success_count}/{len(self.services)}")
        print("="*60)


def main():
    if not SERVICES or SERVICES == ['']:
        print("Error: No services specified in SERVICES environment variable")
        print("Format: SERVICE1:PORT1,SERVICE2:PORT2,...")
        return

    monitor = ParallelTestMonitor(SERVICES)
    monitor.monitor_all_services()
    monitor.save_results()
    monitor.print_summary()


if __name__ == "__main__":
    main()
