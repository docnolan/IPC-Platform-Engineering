import asyncio
import json
import os
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from asyncua import Client
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

OPCUA_ENDPOINT = os.getenv("OPCUA_ENDPOINT", "opc.tcp://opcua-simulator:4840/freeopcua/server/")
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
PUBLISH_INTERVAL = int(os.getenv("PUBLISH_INTERVAL", "5"))
HEALTH_PORT = 8080

TAGS = [
    "ns=2;s=ProductionLine/CycleCount",
    "ns=2;s=ProductionLine/PartsGood",
    "ns=2;s=ProductionLine/PartsBad",
    "ns=2;s=ProductionLine/Temperature",
    "ns=2;s=ProductionLine/Pressure",
    "ns=2;s=ProductionLine/Vibration",
    "ns=2;s=ProductionLine/MachineState",
]

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="OPCUAGateway", **kwargs):
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

async def main():
    # Start Health Server
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", "OPC-UA Gateway starting...", "Gateway")
    log_json("INFO", f"OPC-UA Endpoint: {OPCUA_ENDPOINT}")
    log_json("INFO", f"Publish Interval: {PUBLISH_INTERVAL} seconds")
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        iot_client = IoTHubDeviceClient.create_from_connection_string(IOT_HUB_CONNECTION_STRING)
        await iot_client.connect()
        log_json("INFO", "Connected to Azure IoT Hub", "IoTHub")
    else:
        log_json("WARNING", "No IoT Hub connection string. Running in local-only mode.", "IoTHub")
    
    opcua_client = Client(OPCUA_ENDPOINT)
    
    try:
        await opcua_client.connect()
        log_json("INFO", f"Connected to OPC-UA server: {OPCUA_ENDPOINT}", "OPCUA")
        
        nodes = []
        for tag in TAGS:
            try:
                node = opcua_client.get_node(tag)
                nodes.append((tag, node))
                log_json("INFO", f"Subscribed to: {tag}", "OPCUA")
            except Exception as e:
                log_json("ERROR", f"Failed to subscribe to {tag}: {e}", "OPCUA")
        
        while True:
            telemetry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "deviceId": os.getenv("HOSTNAME", "unknown"),
                "tags": {}
            }
            
            for tag_path, node in nodes:
                try:
                    value = await node.read_value()
                    tag_name = tag_path.split("/")[-1]
                    telemetry["tags"][tag_name] = value
                except Exception as e:
                    log_json("ERROR", f"Error reading {tag_path}: {e}", "OPCUA")
            
            log_json("INFO", f"Telemetry collected", "Telemetry", data_preview=str(telemetry["tags"]))
            
            if iot_client:
                message = Message(json.dumps(telemetry))
                message.content_type = "application/json"
                message.content_encoding = "utf-8"
                await iot_client.send_message(message)
                log_json("INFO", "Sent to IoT Hub", "IoTHub")
            
            await asyncio.sleep(PUBLISH_INTERVAL)
            
    except Exception as e:
        log_json("ERROR", f"Fatal Error: {e}", "System")
    finally:
        try:
            await opcua_client.disconnect()
        except:
             pass
        if iot_client:
             try:
                 await iot_client.disconnect()
             except:
                 pass

if __name__ == "__main__":
    asyncio.run(main())
