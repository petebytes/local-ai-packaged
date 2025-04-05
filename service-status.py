from flask import Flask, jsonify
from flask_cors import CORS
import subprocess
import json
import os
import time
from datetime import datetime

app = Flask(__name__)
CORS(app)

def get_status():
    # Check backup status
    try:
        latest = subprocess.check_output("ls -t /backup/backup-*.tar.gz 2>/dev/null | head -1", shell=True).decode().strip()
        if latest:
            timestamp = os.path.getmtime(latest)
            now = time.time()
            age = now - timestamp
            backup_status = "healthy" if age < 86400 else "overdue"
            backup_time = datetime.fromtimestamp(timestamp).isoformat()
        else:
            backup_status = "no_backups"
            backup_time = None
    except:
        backup_status = "error"
        backup_time = None

    # Check service status
    try:
        result = subprocess.check_output(["curl", "-s", "--unix-socket", "/var/run/docker.sock", "http://localhost/containers/json"])
        services = json.loads(result)
        service_status = [{
            "name": container["Names"][0].lstrip("/"),
            "state": container["State"],
            "status": container["Status"]
        } for container in services]
    except:
        service_status = []

    return {
        "backup": {
            "status": backup_status,
            "last_backup": backup_time
        },
        "services": service_status
    }

@app.route("/")
def status():
    return jsonify(get_status())

app.run(host="0.0.0.0", port=80)
