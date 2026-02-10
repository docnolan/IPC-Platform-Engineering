import os
import time
import socket
import psutil
import json
import hashlib
import hmac
import base64
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import requests

DEVICE_ID = os.getenv("HOSTNAME", socket.gethostname())
CUSTOMER_ID = os.getenv("CUSTOMER_ID", "dmc-internal")
LOG_ANALYTICS_WORKSPACE_ID = os.getenv("LOG_ANALYTICS_WORKSPACE_ID", "")
LOG_ANALYTICS_KEY = os.getenv("LOG_ANALYTICS_KEY", "")
COLLECTION_INTERVAL = int(os.getenv("COLLECTION_INTERVAL", "60"))
HEALTH_PORT = 8080

NETWORK_ENDPOINTS = [
    ("opcua-simulator", 4840),
]

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="HealthMonitor", **kwargs):
    entry = {
        "timestamp": datetime.utcnow().isoformat() + "Z",
        "level": level,
        "component": component,
        "message": message,
        **kwargs
    }
    print(json.dumps(entry), flush=True)

# --- Op Maturity: Health Server ---
class HealthHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/health':
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

def start_health_server():
    try:
        server = HTTPServer(('0.0.0.0', HEALTH_PORT), HealthHandler)
        log_json("INFO", f"Health server listening on port {HEALTH_PORT}", "HealthCheck")
        server.serve_forever()
    except Exception as e:
        log_json("ERROR", f"Failed to start health server: {e}", "HealthCheck")

def collect_system_metrics():
    cpu_percent = psutil.cpu_percent(interval=1)
    memory = psutil.virtual_memory()
    disk = psutil.disk_usage('/')
    
    return {
        "cpu_percent": cpu_percent,
        "memory_percent": memory.percent,
        "memory_used_gb": round(memory.used / (1024**3), 2),
        "memory_total_gb": round(memory.total / (1024**3), 2),
        "disk_percent": disk.percent,
        "disk_used_gb": round(disk.used / (1024**3), 2),
        "disk_total_gb": round(disk.total / (1024**3), 2),
        "boot_time": datetime.fromtimestamp(psutil.boot_time()).isoformat()
    }

def check_network_endpoints():
    results = {}
    for host, port in NETWORK_ENDPOINTS:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(5)
            result = sock.connect_ex((host, port))
            results[f"{host}:{port}"] = "reachable" if result == 0 else "unreachable"
            sock.close()
        except Exception as e:
            results[f"{host}:{port}"] = f"error: {str(e)}"
    return results

def send_to_log_analytics(data):
    if not LOG_ANALYTICS_WORKSPACE_ID or not LOG_ANALYTICS_KEY:
        log_json("WARNING", "Log Analytics not configured, skipping upload", "LogAnalytics")
        return False
    
    body = json.dumps(data)
    content_length = len(body)
    rfc1123date = datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S GMT')
    
    string_to_hash = f"POST\n{content_length}\napplication/json\nx-ms-date:{rfc1123date}\n/api/logs"
    bytes_to_hash = string_to_hash.encode('utf-8')
    decoded_key = base64.b64decode(LOG_ANALYTICS_KEY)
    encoded_hash = base64.b64encode(hmac.new(decoded_key, bytes_to_hash, digestmod=hashlib.sha256).digest()).decode('utf-8')
    authorization = f"SharedKey {LOG_ANALYTICS_WORKSPACE_ID}:{encoded_hash}"
    
    uri = f"https://{LOG_ANALYTICS_WORKSPACE_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': authorization,
        'Log-Type': 'IPCHealthMonitor',
        'x-ms-date': rfc1123date
    }
    
    try:
        response = requests.post(uri, data=body, headers=headers)
        return response.status_code >= 200 and response.status_code <= 299
    except Exception as e:
        log_json("ERROR", f"Log Analytics upload failed: {e}", "LogAnalytics")
        return False

def main():
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", f"Health Monitor starting for device: {DEVICE_ID}")
    log_json("INFO", f"Customer: {CUSTOMER_ID}")
    log_json("INFO", f"Collection interval: {COLLECTION_INTERVAL} seconds")
    
    while True:
        timestamp = datetime.utcnow().isoformat() + "Z"
        metrics = collect_system_metrics()
        network = check_network_endpoints()
        
        health_record = {
            "timestamp": timestamp,
            "deviceId": DEVICE_ID,
            "customerId": CUSTOMER_ID,
            "system": metrics,
            "network": network,
            "status": "healthy"
        }
        
        if metrics["cpu_percent"] > 90:
            health_record["status"] = "warning"
            health_record["alerts"] = health_record.get("alerts", []) + ["High CPU usage"]
        if metrics["memory_percent"] > 90:
            health_record["status"] = "warning"
            health_record["alerts"] = health_record.get("alerts", []) + ["High memory usage"]
        if metrics["disk_percent"] > 85:
            health_record["status"] = "warning"
            health_record["alerts"] = health_record.get("alerts", []) + ["Low disk space"]
        if any("unreachable" in str(v) for v in network.values()):
            health_record["status"] = "critical"
            health_record["alerts"] = health_record.get("alerts", []) + ["Network endpoint unreachable"]
        
        log_json("INFO", f"Health Monitor Status: {health_record['status']}", "Monitor", 
                 cpu=metrics['cpu_percent'], memory=metrics['memory_percent'], disk=metrics['disk_percent'])
        
        if health_record.get("alerts"):
            log_json("WARNING", f"Alerts: {', '.join(health_record['alerts'])}", "Monitor")
        
        if send_to_log_analytics(health_record):
            log_json("INFO", "Sent to Log Analytics", "LogAnalytics")
        
        time.sleep(COLLECTION_INTERVAL)

if __name__ == "__main__":
    main()
