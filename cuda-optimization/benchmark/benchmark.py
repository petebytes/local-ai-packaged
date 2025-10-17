#!/usr/bin/env python3
"""
CUDA/PyTorch Benchmark Suite for Local AI Packaged
Automated performance testing with persistent results storage

Usage:
    python benchmark.py --service whisperx --cuda-version 12.8
    python benchmark.py --service whisperx --cuda-version 13.0 --compare
    python benchmark.py --report
"""

import argparse
import json
import sqlite3
import subprocess
import time
from dataclasses import dataclass, asdict
from datetime import datetime
from pathlib import Path
from typing import Optional, Dict, List
import sys

# Database setup
DB_PATH = Path(__file__).parent / "results.db"


@dataclass
class BenchmarkResult:
    """Benchmark result data structure"""
    test_id: str
    timestamp: str
    service: str
    cuda_version: str
    pytorch_version: Optional[str]
    build_time_seconds: float
    image_size_mb: float
    gpu_available: bool
    gpu_name: Optional[str]
    vram_total_mb: Optional[float]
    vram_used_mb: Optional[float]
    runtime_test_passed: bool
    runtime_speed_factor: Optional[float]  # Relative to baseline
    notes: str


class BenchmarkDatabase:
    """SQLite database for persistent results storage"""

    def __init__(self, db_path: Path = DB_PATH):
        self.db_path = db_path
        self.conn: Optional[sqlite3.Connection] = None
        self.init_database()

    def init_database(self):
        """Initialize database schema"""
        self.conn = sqlite3.connect(self.db_path)
        cursor = self.conn.cursor()

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS benchmark_results (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                test_id TEXT UNIQUE NOT NULL,
                timestamp TEXT NOT NULL,
                service TEXT NOT NULL,
                cuda_version TEXT NOT NULL,
                pytorch_version TEXT,
                build_time_seconds REAL,
                image_size_mb REAL,
                gpu_available INTEGER,
                gpu_name TEXT,
                vram_total_mb REAL,
                vram_used_mb REAL,
                runtime_test_passed INTEGER,
                runtime_speed_factor REAL,
                notes TEXT,
                UNIQUE(service, cuda_version, timestamp)
            )
        """)

        cursor.execute("""
            CREATE TABLE IF NOT EXISTS gpu_metrics (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                test_id TEXT NOT NULL,
                timestamp TEXT NOT NULL,
                gpu_utilization_pct REAL,
                memory_used_mb REAL,
                memory_total_mb REAL,
                temperature_c REAL,
                power_watts REAL,
                FOREIGN KEY (test_id) REFERENCES benchmark_results(test_id)
            )
        """)

        self.conn.commit()

    def save_result(self, result: BenchmarkResult):
        """Save benchmark result to database"""
        cursor = self.conn.cursor()
        data = asdict(result)
        data['gpu_available'] = int(data['gpu_available'])
        data['runtime_test_passed'] = int(data['runtime_test_passed'])

        cursor.execute("""
            INSERT OR REPLACE INTO benchmark_results
            (test_id, timestamp, service, cuda_version, pytorch_version,
             build_time_seconds, image_size_mb, gpu_available, gpu_name,
             vram_total_mb, vram_used_mb, runtime_test_passed,
             runtime_speed_factor, notes)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """, (
            data['test_id'], data['timestamp'], data['service'],
            data['cuda_version'], data['pytorch_version'],
            data['build_time_seconds'], data['image_size_mb'],
            data['gpu_available'], data['gpu_name'],
            data['vram_total_mb'], data['vram_used_mb'],
            data['runtime_test_passed'], data['runtime_speed_factor'],
            data['notes']
        ))
        self.conn.commit()

    def get_latest_results(self, service: str, limit: int = 10) -> List[Dict]:
        """Get latest benchmark results for a service"""
        cursor = self.conn.cursor()
        cursor.execute("""
            SELECT * FROM benchmark_results
            WHERE service = ?
            ORDER BY timestamp DESC
            LIMIT ?
        """, (service, limit))

        columns = [desc[0] for desc in cursor.description]
        results = []
        for row in cursor.fetchall():
            results.append(dict(zip(columns, row)))
        return results

    def compare_versions(self, service: str, cuda_versions: List[str]) -> Dict:
        """Compare benchmark results across CUDA versions"""
        cursor = self.conn.cursor()
        comparison = {}

        for version in cuda_versions:
            cursor.execute("""
                SELECT * FROM benchmark_results
                WHERE service = ? AND cuda_version = ?
                ORDER BY timestamp DESC
                LIMIT 1
            """, (service, version))

            columns = [desc[0] for desc in cursor.description]
            row = cursor.fetchone()
            if row:
                comparison[version] = dict(zip(columns, row))

        return comparison

    def close(self):
        """Close database connection"""
        if self.conn:
            self.conn.close()


class CUDABenchmark:
    """CUDA/PyTorch benchmark runner"""

    def __init__(self, service: str, cuda_version: str):
        self.service = service
        self.cuda_version = cuda_version
        self.db = BenchmarkDatabase()
        self.test_id = f"{service}-{cuda_version}-{int(time.time())}"

    def run_build_test(self) -> tuple[float, float, bool]:
        """Build the service and measure time/size"""
        print(f"Building {self.service} with CUDA {self.cuda_version}...")

        start_time = time.time()

        # Build command
        cmd = [
            "docker", "compose", "build",
            "--build-arg", f"CUDA_VERSION={self.cuda_version}",
            self.service
        ]

        try:
            result = subprocess.run(
                cmd,
                cwd="/home/ghar/code/local-ai-packaged",
                capture_output=True,
                text=True,
                timeout=1800  # 30 min timeout
            )
            build_time = time.time() - start_time
            build_success = result.returncode == 0

            if not build_success:
                print(f"Build failed: {result.stderr}")
                return build_time, 0.0, False

        except subprocess.TimeoutExpired:
            print("Build timed out after 30 minutes")
            return time.time() - start_time, 0.0, False

        # Get image size
        image_name = f"localai-{self.service}"
        size_cmd = ["docker", "images", "--format", "{{.Size}}", image_name]
        size_result = subprocess.run(size_cmd, capture_output=True, text=True)
        image_size = self._parse_image_size(size_result.stdout.strip())

        return build_time, image_size, build_success

    def run_runtime_test(self) -> tuple[bool, Optional[str], Optional[float], Optional[float]]:
        """Start container and test CUDA availability"""
        print(f"Testing runtime for {self.service}...")

        # Start service
        start_cmd = ["docker", "compose", "up", "-d", self.service]
        subprocess.run(start_cmd, cwd="/home/ghar/code/local-ai-packaged")

        # Wait for startup
        time.sleep(10)

        # Test CUDA inside container
        test_cmd = [
            "docker", "compose", "exec", "-T", self.service,
            "python3", "-c",
            "import torch; import json; print(json.dumps({'cuda': torch.cuda.is_available(), 'version': torch.__version__, 'gpu': torch.cuda.get_device_name(0) if torch.cuda.is_available() else None}))"
        ]

        try:
            result = subprocess.run(
                test_cmd,
                cwd="/home/ghar/code/local-ai-packaged",
                capture_output=True,
                text=True,
                timeout=30
            )

            if result.returncode == 0:
                data = json.loads(result.stdout.strip())
                cuda_available = data['cuda']
                pytorch_version = data['version']
                gpu_name = data['gpu']

                # Get VRAM info
                vram_total, vram_used = self._get_vram_info()

                # Stop service
                subprocess.run(
                    ["docker", "compose", "down", self.service],
                    cwd="/home/ghar/code/local-ai-packaged"
                )

                return cuda_available, pytorch_version, vram_total, vram_used
            else:
                print(f"Runtime test failed: {result.stderr}")
                return False, None, None, None

        except (subprocess.TimeoutExpired, json.JSONDecodeError) as e:
            print(f"Runtime test error: {e}")
            subprocess.run(
                ["docker", "compose", "down", self.service],
                cwd="/home/ghar/code/local-ai-packaged"
            )
            return False, None, None, None

    def _get_vram_info(self) -> tuple[Optional[float], Optional[float]]:
        """Get GPU VRAM information"""
        try:
            result = subprocess.run(
                ["nvidia-smi", "--query-gpu=memory.total,memory.used",
                 "--format=csv,noheader,nounits"],
                capture_output=True,
                text=True
            )
            if result.returncode == 0:
                line = result.stdout.strip().split('\n')[0]
                total, used = line.split(',')
                return float(total.strip()), float(used.strip())
        except Exception as e:
            print(f"Failed to get VRAM info: {e}")
        return None, None

    def _parse_image_size(self, size_str: str) -> float:
        """Parse Docker image size string to MB"""
        if not size_str:
            return 0.0

        try:
            if 'GB' in size_str:
                return float(size_str.replace('GB', '').strip()) * 1024
            elif 'MB' in size_str:
                return float(size_str.replace('MB', '').strip())
            else:
                return 0.0
        except ValueError:
            return 0.0

    def run_full_benchmark(self) -> BenchmarkResult:
        """Run complete benchmark suite"""
        print(f"\n{'='*60}")
        print(f"Running benchmark: {self.service} with CUDA {self.cuda_version}")
        print(f"Test ID: {self.test_id}")
        print(f"{'='*60}\n")

        # Build test
        build_time, image_size, build_success = self.run_build_test()

        if not build_success:
            result = BenchmarkResult(
                test_id=self.test_id,
                timestamp=datetime.now().isoformat(),
                service=self.service,
                cuda_version=self.cuda_version,
                pytorch_version=None,
                build_time_seconds=build_time,
                image_size_mb=image_size,
                gpu_available=False,
                gpu_name=None,
                vram_total_mb=None,
                vram_used_mb=None,
                runtime_test_passed=False,
                runtime_speed_factor=None,
                notes="Build failed"
            )
            self.db.save_result(result)
            return result

        # Runtime test
        cuda_available, pytorch_version, vram_total, vram_used = self.run_runtime_test()

        # Get GPU name
        gpu_name = None
        if cuda_available:
            try:
                gpu_result = subprocess.run(
                    ["nvidia-smi", "--query-gpu=name", "--format=csv,noheader"],
                    capture_output=True,
                    text=True
                )
                if gpu_result.returncode == 0:
                    gpu_name = gpu_result.stdout.strip().split('\n')[0]
            except Exception:
                pass

        result = BenchmarkResult(
            test_id=self.test_id,
            timestamp=datetime.now().isoformat(),
            service=self.service,
            cuda_version=self.cuda_version,
            pytorch_version=pytorch_version,
            build_time_seconds=build_time,
            image_size_mb=image_size,
            gpu_available=cuda_available,
            gpu_name=gpu_name,
            vram_total_mb=vram_total,
            vram_used_mb=vram_used,
            runtime_test_passed=cuda_available,
            runtime_speed_factor=None,  # TODO: Implement actual speed tests
            notes="Success" if cuda_available else "CUDA not available"
        )

        self.db.save_result(result)
        self._print_result(result)

        return result

    def _print_result(self, result: BenchmarkResult):
        """Print benchmark result summary"""
        print(f"\n{'='*60}")
        print("BENCHMARK RESULTS")
        print(f"{'='*60}")
        print(f"Service:        {result.service}")
        print(f"CUDA Version:   {result.cuda_version}")
        print(f"PyTorch:        {result.pytorch_version}")
        print(f"Build Time:     {result.build_time_seconds:.1f}s")
        print(f"Image Size:     {result.image_size_mb:.1f} MB")
        print(f"GPU Available:  {'✓' if result.gpu_available else '✗'}")
        if result.gpu_name:
            print(f"GPU Name:       {result.gpu_name}")
        if result.vram_total_mb:
            print(f"VRAM:           {result.vram_used_mb:.0f} / {result.vram_total_mb:.0f} MB")
        print(f"Status:         {result.notes}")
        print(f"{'='*60}\n")


def generate_comparison_report(service: str, cuda_versions: List[str]):
    """Generate markdown comparison report"""
    db = BenchmarkDatabase()
    comparison = db.compare_versions(service, cuda_versions)

    if not comparison:
        print("No results found for comparison")
        return

    report_path = Path(__file__).parent / f"comparison_{service}_{int(time.time())}.md"

    with open(report_path, 'w') as f:
        f.write(f"# CUDA Version Comparison: {service}\n\n")
        f.write(f"Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n\n")

        # Table header
        f.write("| CUDA Ver | PyTorch | Build Time | Image Size | GPU | VRAM Used | Status |\n")
        f.write("|----------|---------|------------|------------|-----|-----------|--------|\n")

        # Sort by CUDA version
        sorted_versions = sorted(comparison.items(), key=lambda x: x[0])

        for version, result in sorted_versions:
            f.write(f"| {result['cuda_version']} | ")
            f.write(f"{result['pytorch_version'] or 'N/A'} | ")
            f.write(f"{result['build_time_seconds']:.0f}s | ")
            f.write(f"{result['image_size_mb']:.0f}MB | ")
            f.write(f"{'✓' if result['gpu_available'] else '✗'} | ")
            f.write(f"{result['vram_used_mb']:.0f}MB | " if result['vram_used_mb'] else "N/A | ")
            f.write(f"{result['notes']} |\n")

        # Find winner
        f.write("\n## Recommendation\n\n")
        fastest_build = min(comparison.items(), key=lambda x: x[1]['build_time_seconds'])
        f.write(f"**Fastest Build**: CUDA {fastest_build[0]} ({fastest_build[1]['build_time_seconds']:.0f}s)\n\n")

        working_versions = [v for v, r in comparison.items() if r['runtime_test_passed']]
        if working_versions:
            f.write(f"**Working Versions**: {', '.join(working_versions)}\n")

    print(f"\nComparison report saved to: {report_path}")
    db.close()


def main():
    parser = argparse.ArgumentParser(description="CUDA/PyTorch Benchmark Suite")
    parser.add_argument("--service", help="Service to benchmark (e.g., whisperx)")
    parser.add_argument("--cuda-version", help="CUDA version to test (e.g., 12.8)")
    parser.add_argument("--compare", action="store_true", help="Generate comparison report")
    parser.add_argument("--report", action="store_true", help="Show latest results")
    parser.add_argument("--list", action="store_true", help="List all test results")

    args = parser.parse_args()

    if args.report:
        db = BenchmarkDatabase()
        if args.service:
            results = db.get_latest_results(args.service, limit=10)
            print(f"\nLatest results for {args.service}:")
            for r in results:
                print(f"  {r['timestamp']}: CUDA {r['cuda_version']} - {r['notes']}")
        db.close()
        return

    if args.list:
        db = BenchmarkDatabase()
        cursor = db.conn.cursor()
        cursor.execute("SELECT DISTINCT service FROM benchmark_results")
        services = [row[0] for row in cursor.fetchall()]
        print("Services with benchmark results:")
        for s in services:
            cursor.execute("SELECT COUNT(*) FROM benchmark_results WHERE service = ?", (s,))
            count = cursor.fetchone()[0]
            print(f"  {s}: {count} tests")
        db.close()
        return

    if not args.service or not args.cuda_version:
        parser.print_help()
        sys.exit(1)

    # Run benchmark
    benchmark = CUDABenchmark(args.service, args.cuda_version)
    result = benchmark.run_full_benchmark()

    if args.compare:
        # Generate comparison with other versions
        cuda_versions = ["12.1", "12.8", "12.9", "13.0"]
        generate_comparison_report(args.service, cuda_versions)

    benchmark.db.close()


if __name__ == "__main__":
    main()
