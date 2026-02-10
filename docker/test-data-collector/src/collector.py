import os
import json
import csv
import time
import hashlib
import threading
from datetime import datetime
from pathlib import Path
from http.server import HTTPServer, BaseHTTPRequestHandler
from watchdog.observers import Observer
from watchdog.events import FileSystemEventHandler
from azure.storage.blob import BlobServiceClient
from azure.iot.device import IoTHubDeviceClient, Message

WATCH_DIR = os.getenv("WATCH_DIR", "/data/test-results")
BLOB_CONNECTION_STRING = os.getenv("BLOB_CONNECTION_STRING", "")
BLOB_CONTAINER = os.getenv("BLOB_CONTAINER", "test-results")
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
DEVICE_ID = os.getenv("HOSTNAME", "unknown-device")
HEALTH_PORT = 8080

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="TestCollector", **kwargs):
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

class TestResultHandler(FileSystemEventHandler):
    def __init__(self, blob_service, iot_client):
        self.blob_service = blob_service
        self.iot_client = iot_client
        self.processed_files = set()
    
    def on_created(self, event):
        if event.is_directory:
            return
        
        filepath = event.src_path
        filename = os.path.basename(filepath)
        
        if not filename.lower().endswith(('.csv', '.json')):
            return
        
        # Wait for file to be fully written
        time.sleep(1)
        
        file_hash = self._get_file_hash(filepath)
        if file_hash in self.processed_files:
            return
        
        log_json("INFO", f"New test result detected: {filename}", "Watcher")
        
        try:
            test_data = self._parse_file(filepath)
            
            test_data["metadata"] = {
                "sourceFile": filename,
                "deviceId": DEVICE_ID,
                "uploadTimestamp": datetime.utcnow().isoformat() + "Z",
                "fileHash": file_hash
            }
            
            blob_name = None
            if self.blob_service:
                blob_name = f"{DEVICE_ID}/{datetime.utcnow().strftime('%Y/%m/%d')}/{filename}.json"
                blob_client = self.blob_service.get_blob_client(container=BLOB_CONTAINER, blob=blob_name)
                blob_client.upload_blob(json.dumps(test_data, indent=2), overwrite=True)
                log_json("INFO", f"Uploaded to Blob: {blob_name}", "BlobStorage")
            
            if self.iot_client:
                summary = {
                    "messageType": "testResult",
                    "deviceId": DEVICE_ID,
                    "timestamp": datetime.utcnow().isoformat() + "Z",
                    "testId": test_data.get("testId", filename),
                    "result": test_data.get("result", "UNKNOWN"),
                    "blobPath": blob_name
                }
                message = Message(json.dumps(summary))
                message.content_type = "application/json"
                self.iot_client.send_message(message)
                log_json("INFO", "Sent summary to IoT Hub", "IoTHub")
            
            self.processed_files.add(file_hash)
            log_json("INFO", "Processing complete", "Handler")
            
        except Exception as e:
            log_json("ERROR", f"Error processing {filename}: {e}", "Handler")
    
    def _get_file_hash(self, filepath):
        try:
            with open(filepath, 'rb') as f:
                return hashlib.md5(f.read()).hexdigest()
        except:
            return str(time.time())
    
    def _parse_file(self, filepath):
        filename = os.path.basename(filepath).lower()
        
        if filename.endswith('.json'):
            with open(filepath, 'r') as f:
                return json.load(f)
        
        elif filename.endswith('.csv'):
            with open(filepath, 'r') as f:
                reader = csv.DictReader(f)
                rows = list(reader)
                
                result = {
                    "testId": os.path.splitext(os.path.basename(filepath))[0],
                    "recordCount": len(rows),
                    "data": rows,
                    "result": "UNKNOWN"
                }
                
                for row in rows:
                    for key, value in row.items():
                        if 'result' in key.lower() or 'status' in key.lower():
                            result["result"] = value
                            break
                
                return result
        
        return {"raw": open(filepath, 'r').read()}

def main():
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", "Test Data Collector starting...", "Collector")
    log_json("INFO", f"Watching directory: {WATCH_DIR}")
    log_json("INFO", f"Blob container: {BLOB_CONTAINER}")
    
    blob_service = None
    if BLOB_CONNECTION_STRING:
        try:
            blob_service = BlobServiceClient.from_connection_string(BLOB_CONNECTION_STRING)
            log_json("INFO", "Connected to Azure Blob Storage", "BlobStorage")
        except Exception as e:
            log_json("WARNING", f"Failed to connect to Blob Storage: {e}", "BlobStorage")
    else:
        log_json("WARNING", "No Blob connection string. Files will not be uploaded.", "BlobStorage")
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        try:
            iot_client = IoTHubDeviceClient.create_from_connection_string(IOT_HUB_CONNECTION_STRING)
            iot_client.connect()
            log_json("INFO", "Connected to Azure IoT Hub", "IoTHub")
        except Exception as e:
            log_json("WARNING", f"Failed to connect to IoT Hub: {e}", "IoTHub")
    else:
        log_json("WARNING", "No IoT Hub connection string. Summaries will not be sent.", "IoTHub")
    
    Path(WATCH_DIR).mkdir(parents=True, exist_ok=True)
    
    handler = TestResultHandler(blob_service, iot_client)
    observer = Observer()
    observer.schedule(handler, WATCH_DIR, recursive=False)
    observer.start()
    
    log_json("INFO", "Watching for test results...", "Collector")
    log_json("INFO", f"Drop .csv or .json files into {WATCH_DIR} to process them.", "Collector")
    
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        observer.stop()
        log_json("INFO", "Stopping observer", "System")
    
    observer.join()
    if iot_client:
        try:
            iot_client.disconnect()
        except:
             pass

if __name__ == "__main__":
    main()
