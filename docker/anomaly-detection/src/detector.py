import os
import json
import time
import numpy as np
import threading
from datetime import datetime
from collections import deque
from http.server import HTTPServer, BaseHTTPRequestHandler
from opcua import Client
from azure.iot.device import IoTHubDeviceClient, Message

OPCUA_ENDPOINT = os.getenv("OPCUA_ENDPOINT", "opc.tcp://opcua-simulator:4840/freeopcua/server/")
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
DEVICE_ID = os.getenv("HOSTNAME", "unknown-device")
DETECTION_INTERVAL = int(os.getenv("DETECTION_INTERVAL", "5"))
WINDOW_SIZE = int(os.getenv("WINDOW_SIZE", "20"))
ANOMALY_THRESHOLD = float(os.getenv("ANOMALY_THRESHOLD", "2.5"))
HEALTH_PORT = 8080

MONITORED_TAGS = [
    ("ns=2;s=ProductionLine/Vibration", "Vibration"),
    ("ns=2;s=ProductionLine/Temperature", "Temperature"),
    ("ns=2;s=ProductionLine/Pressure", "Pressure"),
]

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="AnomalyDetector", **kwargs):
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

class AnomalyDetector:
    def __init__(self, window_size=20, threshold=2.5):
        self.window_size = window_size
        self.threshold = threshold
        self.history = {}
    
    def add_sample(self, tag_name, value):
        if tag_name not in self.history:
            self.history[tag_name] = deque(maxlen=self.window_size)
        
        self.history[tag_name].append(value)
        
        if len(self.history[tag_name]) < self.window_size // 2:
            return None, None, None
        
        values = np.array(self.history[tag_name])
        mean = np.mean(values)
        std = np.std(values)
        
        if std == 0:
            return False, 0, mean
        
        z_score = abs(value - mean) / std
        is_anomaly = z_score > self.threshold
        
        return is_anomaly, z_score, mean

def main():
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", f"Anomaly Detection starting for device: {DEVICE_ID}", "Detector")
    log_json("INFO", f"OPC-UA Endpoint: {OPCUA_ENDPOINT}")
    log_json("INFO", f"Detection interval: {DETECTION_INTERVAL} seconds")
    log_json("INFO", f"Window size: {WINDOW_SIZE} samples")
    log_json("INFO", f"Anomaly threshold: {ANOMALY_THRESHOLD} standard deviations")
    
    detector = AnomalyDetector(window_size=WINDOW_SIZE, threshold=ANOMALY_THRESHOLD)
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        try:
            iot_client = IoTHubDeviceClient.create_from_connection_string(IOT_HUB_CONNECTION_STRING)
            iot_client.connect()
            log_json("INFO", "Connected to Azure IoT Hub", "IoTHub")
        except Exception as e:
            log_json("WARNING", f"Failed to connect to IoT Hub: {e}", "IoTHub")
    else:
        log_json("WARNING", "No IoT Hub connection string. Alerts will be logged locally only.", "IoTHub")
    
    client = Client(OPCUA_ENDPOINT)
    
    try:
        client.connect()
        log_json("INFO", "Connected to OPC-UA server", "OPCUA")
        
        nodes = []
        for tag_path, tag_name in MONITORED_TAGS:
            try:
                node = client.get_node(tag_path)
                nodes.append((node, tag_name))
                log_json("INFO", f"Monitoring: {tag_name}", "OPCUA")
            except Exception as e:
                log_json("ERROR", f"Failed to get node {tag_name}: {e}", "OPCUA")
        
        anomaly_count = 0
        
        while True:
            timestamp = datetime.utcnow().isoformat() + "Z"
            anomalies_detected = []
            
            # log_json("INFO", "Checking for anomalies...", "Detector") # Noisy, maybe skip
            
            for node, tag_name in nodes:
                try:
                    value = node.get_value()
                    is_anomaly, z_score, baseline = detector.add_sample(tag_name, value)
                    
                    if is_anomaly is None:
                        # Collecting baseline, maybe debug log?
                        pass
                    elif is_anomaly:
                        anomaly_count += 1
                        anomaly_info = {
                            "tag": tag_name,
                            "value": round(value, 3),
                            "baseline": round(baseline, 3),
                            "deviation": round(z_score, 2),
                            "threshold": ANOMALY_THRESHOLD
                        }
                        anomalies_detected.append(anomaly_info)
                        log_json("WARNING", f"ANOMALY detected on {tag_name}", "Detector", 
                                 value=value, z_score=z_score)
                    else:
                        # Normal
                        pass
                        
                except Exception as e:
                    log_json("ERROR", f"Error reading {tag_name}: {e}", "OPCUA")
            
            if anomalies_detected and iot_client:
                try:
                    alert = {
                        "messageType": "anomalyAlert",
                        "deviceId": DEVICE_ID,
                        "timestamp": timestamp,
                        "anomalyCount": len(anomalies_detected),
                        "totalAnomalies": anomaly_count,
                        "anomalies": anomalies_detected,
                        "severity": "warning" if len(anomalies_detected) < 2 else "critical"
                    }
                    message = Message(json.dumps(alert))
                    message.content_type = "application/json"
                    message.custom_properties["severity"] = alert["severity"]
                    iot_client.send_message(message)
                    log_json("INFO", f"Alert sent to IoT Hub (severity: {alert['severity']})", "IoTHub")
                except Exception as e:
                    log_json("ERROR", f"Failed to send alert: {e}", "IoTHub")
            
            time.sleep(DETECTION_INTERVAL)
            
    except Exception as e:
        log_json("ERROR", f"Fatal Error: {e}", "System")
    finally:
        try:
            client.disconnect()
        except:
            pass
        if iot_client:
            try:
                iot_client.disconnect()
            except:
                pass

if __name__ == "__main__":
    main()
