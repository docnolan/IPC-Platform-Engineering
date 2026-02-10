import os
import json
import time
import hashlib
import hmac
import base64
import requests
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
import random

DEVICE_ID = os.getenv("HOSTNAME", "unknown-device")
CUSTOMER_ID = os.getenv("CUSTOMER_ID", "dmc-internal")
LOG_ANALYTICS_WORKSPACE_ID = os.getenv("LOG_ANALYTICS_WORKSPACE_ID", "")
LOG_ANALYTICS_KEY = os.getenv("LOG_ANALYTICS_KEY", "")
FORWARD_INTERVAL = int(os.getenv("FORWARD_INTERVAL", "30"))
HEALTH_PORT = 8080

DEMO_EVENTS = [
    {"EventID": 4624, "EventType": "Logon", "Description": "An account was successfully logged on"},
    {"EventID": 4625, "EventType": "FailedLogon", "Description": "An account failed to log on"},
    {"EventID": 4634, "EventType": "Logoff", "Description": "An account was logged off"},
    {"EventID": 4672, "EventType": "SpecialPrivilege", "Description": "Special privileges assigned to new logon"},
    {"EventID": 4688, "EventType": "ProcessCreation", "Description": "A new process has been created"},
    {"EventID": 4719, "EventType": "AuditPolicyChange", "Description": "System audit policy was changed"},
    {"EventID": 4738, "EventType": "AccountChange", "Description": "A user account was changed"},
]

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="LogForwarder", **kwargs):
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

def generate_simulated_event():
    event_template = random.choice(DEMO_EVENTS)
    
    return {
        "TimeGenerated": datetime.utcnow().isoformat() + "Z",
        "EventID": event_template["EventID"],
        "EventType": event_template["EventType"],
        "Description": event_template["Description"],
        "Computer": DEVICE_ID,
        "CustomerId": CUSTOMER_ID,
        "SourceSystem": "WindowsSecurityEvent",
        "Channel": "Security",
        "Account": f"DMC\\{'operator' if random.random() > 0.3 else 'admin'}{random.randint(1,5)}",
        "LogonType": random.choice([2, 3, 10]) if "Logon" in event_template["EventType"] else None,
        "IpAddress": f"192.168.1.{random.randint(1, 254)}",
        "ComplianceFramework": ["NIST-800-171", "CMMC-L2"],
        "RetentionDays": 90
    }

def send_to_log_analytics(events):
    if not LOG_ANALYTICS_WORKSPACE_ID or not LOG_ANALYTICS_KEY:
        log_json("WARNING", "Log Analytics not configured", "LogAnalytics")
        return False
    
    body = json.dumps(events)
    content_length = len(body)
    rfc1123date = datetime.utcnow().strftime('%a, %d %b %Y %H:%M:%S GMT')
    
    string_to_hash = f"POST\n{content_length}\napplication/json\nx-ms-date:{rfc1123date}\n/api/logs"
    bytes_to_hash = string_to_hash.encode('utf-8')
    decoded_key = base64.b64decode(LOG_ANALYTICS_KEY)
    encoded_hash = base64.b64encode(
        hmac.new(decoded_key, bytes_to_hash, digestmod=hashlib.sha256).digest()
    ).decode('utf-8')
    authorization = f"SharedKey {LOG_ANALYTICS_WORKSPACE_ID}:{encoded_hash}"
    
    uri = f"https://{LOG_ANALYTICS_WORKSPACE_ID}.ods.opinsights.azure.com/api/logs?api-version=2016-04-01"
    
    headers = {
        'Content-Type': 'application/json',
        'Authorization': authorization,
        'Log-Type': 'IPCSecurityAudit',
        'x-ms-date': rfc1123date,
        'time-generated-field': 'TimeGenerated'
    }
    
    try:
        response = requests.post(uri, data=body, headers=headers)
        return response.status_code >= 200 and response.status_code <= 299
    except Exception as e:
        log_json("ERROR", f"Upload failed: {e}", "LogAnalytics")
        return False

def main():
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", f"Compliance Log Forwarder starting for device: {DEVICE_ID}")
    log_json("INFO", f"Customer: {CUSTOMER_ID}")
    log_json("INFO", f"Forward interval: {FORWARD_INTERVAL} seconds")
    
    event_count = 0
    
    while True:
        batch_size = random.randint(1, 5)
        events = [generate_simulated_event() for _ in range(batch_size)]
        event_count += batch_size
        
        log_json("INFO", f"Forwarding {batch_size} security events...", "Forwarder")
        
        for event in events:
            log_json("INFO", f"Event {event['EventID']}: {event['EventType']}", "Audit", account=event['Account'])
        
        if send_to_log_analytics(events):
            log_json("INFO", f"Forwarded to Log Analytics (total: {event_count})", "LogAnalytics")
        else:
            log_json("INFO", "Events logged locally (Log Analytics not configured)", "LocalLog")
        
        time.sleep(FORWARD_INTERVAL)

if __name__ == "__main__":
    main()
