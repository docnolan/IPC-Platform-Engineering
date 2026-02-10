"""
Vision Inspection Simulator for DMC IPC Platform PoC
Simulates a machine vision quality inspection station

This demonstrates:
- Event-based (bursty) data pattern
- Quality metrics (PASS/FAIL with weighted rates)
- Discrete inspection results with metadata

Business Context: DMC builds machine vision systems for defect detection.
This shows the platform handles quality/inspection data, not just time-series.
"""

import asyncio
import json
import os
import random
import uuid
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

# Configuration
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
INSPECTION_INTERVAL = float(os.getenv("INSPECTION_INTERVAL", "5"))
DEVICE_ID = os.getenv("DEVICE_ID", "vision-station-04")
PASS_RATE = float(os.getenv("PASS_RATE", "0.95"))
HEALTH_PORT = 8080

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="VisionSimulator", **kwargs):
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

# Defect types and their relative probabilities
DEFECT_TYPES = {
    "Scratch": 0.45,
    "Dent": 0.25,
    "Discoloration": 0.15,
    "Contamination": 0.10,
    "Dimensional": 0.05
}

PART_TYPES = ["Housing-A1", "Cover-B2", "Bracket-C3", "Frame-D4"]

CAMERAS = [
    {"id": "CAM-01", "position": "Top", "resolution": "5MP"},
    {"id": "CAM-02", "position": "Side-Left", "resolution": "5MP"},
    {"id": "CAM-03", "position": "Side-Right", "resolution": "5MP"},
]


class VisionInspectionStation:
    def __init__(self):
        self.inspection_count = 0
        self.pass_count = 0
        self.fail_count = 0
        self.current_batch = str(uuid.uuid4())[:8].upper()
        self.batch_count = 0
        self.batch_size = random.randint(50, 100)
        self.defect_counts = {defect: 0 for defect in DEFECT_TYPES}
        
    def perform_inspection(self) -> dict:
        """Simulate a single inspection event"""
        self.inspection_count += 1
        self.batch_count += 1
        
        # Check for batch rollover
        if self.batch_count >= self.batch_size:
            self.current_batch = str(uuid.uuid4())[:8].upper()
            self.batch_count = 0
            self.batch_size = random.randint(50, 100)
            log_json("INFO", f"New batch started: {self.current_batch}", "Batch")
        
        inspection_id = f"INS-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{self.inspection_count:06d}"
        passed = random.random() < PASS_RATE
        part_type = random.choice(PART_TYPES)
        part_serial = f"{part_type}-{random.randint(100000, 999999)}"
        
        result = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "deviceId": DEVICE_ID,
            "dataType": "vision_inspection",
            "inspection": {
                "id": inspection_id,
                "batchId": self.current_batch,
                "partType": part_type,
                "partSerial": part_serial,
                "result": "PASS" if passed else "FAIL",
                "processTimeMs": random.randint(120, 200),
                "confidence": round(random.uniform(0.92, 0.99), 3)
            },
            "cameras": [],
            "defects": [],
            "statistics": {
                "totalInspections": self.inspection_count,
                "totalPass": self.pass_count,
                "totalFail": self.fail_count,
                "passRate": round(self.pass_count / max(1, self.inspection_count) * 100, 2)
            }
        }
        
        # Add camera results
        for cam in CAMERAS:
            cam_result = {
                "cameraId": cam["id"],
                "position": cam["position"],
                "captureTimeMs": random.randint(15, 30),
                "analysisTimeMs": random.randint(30, 60),
                "imageQuality": round(random.uniform(0.95, 1.0), 3)
            }
            result["cameras"].append(cam_result)
        
        if passed:
            self.pass_count += 1
            result["inspection"]["defectType"] = "None"
        else:
            self.fail_count += 1
            defect_type = self._select_defect_type()
            self.defect_counts[defect_type] += 1
            result["inspection"]["defectType"] = defect_type
            
            defect_detail = {
                "type": defect_type,
                "severity": random.choice(["Minor", "Major", "Critical"]),
                "location": {
                    "x": random.randint(100, 900),
                    "y": random.randint(100, 900),
                    "width": random.randint(10, 100),
                    "height": random.randint(10, 100)
                },
                "detectedBy": random.choice([c["id"] for c in CAMERAS]),
                "confidence": round(random.uniform(0.85, 0.98), 3)
            }
            result["defects"].append(defect_detail)
        
        result["statistics"]["defectDistribution"] = dict(self.defect_counts)
        return result
    
    def _select_defect_type(self) -> str:
        r = random.random()
        cumulative = 0
        for defect, prob in DEFECT_TYPES.items():
            cumulative += prob
            if r <= cumulative:
                return defect
        return list(DEFECT_TYPES.keys())[0]


async def main():
    # Start Health Server
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", "Vision Inspection Station Simulator Starting")
    log_json("INFO", f"Device ID: {DEVICE_ID}")
    log_json("INFO", f"Inspection interval: {INSPECTION_INTERVAL}s")
    log_json("INFO", f"Target pass rate: {PASS_RATE * 100:.1f}%")
    
    station = VisionInspectionStation()
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        try:
            iot_client = IoTHubDeviceClient.create_from_connection_string(
                IOT_HUB_CONNECTION_STRING
            )
            await iot_client.connect()
            log_json("INFO", "Connected to Azure IoT Hub", "IoTHub")
        except Exception as e:
            log_json("ERROR", f"Connection failed: {e}", "IoTHub")
            iot_client = None
    else:
        log_json("WARNING", "No connection string - local mode", "IoTHub")
    
    log_json("INFO", "Starting inspections...", "Simulator")
    
    try:
        while True:
            result = station.perform_inspection()
            
            status = result["inspection"]["result"]
            defect_info = f" [{result['inspection']['defectType']}]" if status == "FAIL" else ""
            
            msg = (f"{status} {result['inspection']['id']} | "
                   f"{result['inspection']['partSerial']} {defect_info} | "
                   f"Rate: {result['statistics']['passRate']:.1f}%")
            
            log_json("INFO", msg, "Inspection")
            
            if iot_client:
                try:
                    message = Message(json.dumps(result))
                    message.content_type = "application/json"
                    message.content_encoding = "utf-8"
                    message.custom_properties["dataType"] = "vision_inspection"
                    message.custom_properties["result"] = result["inspection"]["result"]
                    await iot_client.send_message(message)
                except Exception as e:
                    log_json("ERROR", f"Send failed: {e}", "IoTHub")
            
            wait_time = INSPECTION_INTERVAL + random.uniform(-0.5, 0.5)
            await asyncio.sleep(max(1, wait_time))
            
    except KeyboardInterrupt:
        log_json("INFO", "Shutting down...", "System")
    finally:
        if iot_client:
            await iot_client.disconnect()


if __name__ == "__main__":
    asyncio.run(main())
