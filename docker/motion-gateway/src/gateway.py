import asyncio
import json
import os
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from asyncua import Client
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

OPCUA_ENDPOINT = os.getenv(
    "OPCUA_ENDPOINT", 
    "opc.tcp://motion-simulator:4841/freeopcua/server/"
)
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
PUBLISH_INTERVAL = int(os.getenv("PUBLISH_INTERVAL", "1"))
DEVICE_ID = os.getenv("DEVICE_ID", "gantry-b")
HEALTH_PORT = 8080

TAGS = [
    "ns=2;s=GantryB/Axis_X_Pos",
    "ns=2;s=GantryB/Axis_Y_Pos",
    "ns=2;s=GantryB/Axis_Z_Pos",
    "ns=2;s=GantryB/Axis_X_Vel",
    "ns=2;s=GantryB/Axis_Y_Vel",
    "ns=2;s=GantryB/Axis_Z_Vel",
    "ns=2;s=GantryB/Motor_Temp",
    "ns=2;s=GantryB/Fan_Status",
    "ns=2;s=GantryB/Servo_Enabled",
    "ns=2;s=GantryB/In_Motion",
    "ns=2;s=GantryB/Alarm_Active",
    "ns=2;s=GantryB/Cycle_Count",
    "ns=2;s=GantryB/Motion_Mode",
]

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="MotionGateway", **kwargs):
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

    log_json("INFO", "Motion Gateway - OPC-UA to Azure IoT Hub", "Gateway")
    log_json("INFO", f"OPC-UA Endpoint: {OPCUA_ENDPOINT}")
    log_json("INFO", f"Device ID: {DEVICE_ID}")
    
    iot_client = None
    if IOT_HUB_CONNECTION_STRING:
        try:
            iot_client = IoTHubDeviceClient.create_from_connection_string(
                IOT_HUB_CONNECTION_STRING
            )
            await iot_client.connect()
            log_json("INFO", "Connected successfully", "IoTHub")
        except Exception as e:
            log_json("ERROR", f"Connection failed: {e}", "IoTHub")
            iot_client = None
    else:
        log_json("WARNING", "No connection string - local mode", "IoTHub")
    
    opcua_client = Client(OPCUA_ENDPOINT)
    
    try:
        await opcua_client.connect()
        log_json("INFO", f"Connected to {OPCUA_ENDPOINT}", "OPCUA")
        
        nodes = []
        for tag in TAGS:
            try:
                node = opcua_client.get_node(tag)
                nodes.append((tag, node))
            except Exception as e:
                log_json("ERROR", f"Failed: {tag} - {e}", "OPCUA")
        
        log_json("INFO", "Starting telemetry loop...", "Gateway")
        
        message_count = 0
        while True:
            telemetry = {
                "timestamp": datetime.utcnow().isoformat() + "Z",
                "deviceId": DEVICE_ID,
                "dataType": "motion_gantry",
                "position": {},
                "velocity": {},
                "status": {}
            }
            
            for tag_path, node in nodes:
                try:
                    value = await node.read_value()
                    tag_name = tag_path.split("/")[-1]
                    
                    if "Pos" in tag_name:
                        telemetry["position"][tag_name] = value
                    elif "Vel" in tag_name:
                        telemetry["velocity"][tag_name] = value
                    else:
                        telemetry["status"][tag_name] = value
                        
                except Exception as e:
                    log_json("ERROR", f"Error reading {tag_path}: {e}", "OPCUA")
            
            message_count += 1
            
            if message_count % 5 == 0:
                pos = telemetry["position"]
                status = telemetry["status"]
                msg = (f"X:{pos.get('Axis_X_Pos', 0):.1f} "
                       f"Y:{pos.get('Axis_Y_Pos', 0):.1f} "
                       f"Z:{pos.get('Axis_Z_Pos', 0):.1f} | "
                       f"Temp:{status.get('Motor_Temp', 0):.1f}°C")
                log_json("INFO", msg, "Telemetry")
            
            if iot_client:
                try:
                    message = Message(json.dumps(telemetry))
                    message.content_type = "application/json"
                    message.content_encoding = "utf-8"
                    message.custom_properties["dataType"] = "motion_gantry"
                    await iot_client.send_message(message)
                except Exception as e:
                    log_json("ERROR", f"Send failed: {e}", "IoTHub")
            
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
