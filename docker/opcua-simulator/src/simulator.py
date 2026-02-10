import asyncio
import random
import math
import json
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from asyncua import Server, ua

HEALTH_PORT = 8080

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="OPCUASimulator", **kwargs):
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

    server = Server()
    await server.init()
    
    server.set_endpoint("opc.tcp://0.0.0.0:4840/freeopcua/server/")
    server.set_server_name("DMC Simulated PLC")
    
    uri = "http://dmc.com/opcua/simulator"
    idx = await server.register_namespace(uri)
    
    objects = server.nodes.objects
    production_line = await objects.add_object(idx, "ProductionLine")
    
    # Use explicit string node IDs
    cycle_count = await production_line.add_variable(
        ua.NodeId("ProductionLine/CycleCount", idx), "CycleCount", 0)
    await cycle_count.set_writable()
    
    parts_good = await production_line.add_variable(
        ua.NodeId("ProductionLine/PartsGood", idx), "PartsGood", 0)
    await parts_good.set_writable()
    
    parts_bad = await production_line.add_variable(
        ua.NodeId("ProductionLine/PartsBad", idx), "PartsBad", 0)
    await parts_bad.set_writable()
    
    temperature = await production_line.add_variable(
        ua.NodeId("ProductionLine/Temperature", idx), "Temperature", 72.0)
    await temperature.set_writable()
    
    pressure = await production_line.add_variable(
        ua.NodeId("ProductionLine/Pressure", idx), "Pressure", 14.7)
    await pressure.set_writable()
    
    vibration = await production_line.add_variable(
        ua.NodeId("ProductionLine/Vibration", idx), "Vibration", 0.5)
    await vibration.set_writable()
    
    machine_state = await production_line.add_variable(
        ua.NodeId("ProductionLine/MachineState", idx), "MachineState", "Running")
    await machine_state.set_writable()
    
    log_json("INFO", "OPC-UA Simulator started at opc.tcp://0.0.0.0:4840", "OPCUA")
    log_json("INFO", f"Namespace: {uri} (index: {idx})", "OPCUA")
    
    async with server:
        cycle = 0
        while True:
            await asyncio.sleep(1)
            cycle += 1
            
            await cycle_count.write_value(cycle)
            
            if cycle % 5 == 0:
                if random.random() > 0.05:
                    current_good = await parts_good.read_value()
                    await parts_good.write_value(current_good + 1)
                else:
                    current_bad = await parts_bad.read_value()
                    await parts_bad.write_value(current_bad + 1)
            
            base_temp = 72.0
            temp_variation = math.sin(cycle / 30) * 5 + random.uniform(-1, 1)
            await temperature.write_value(round(base_temp + temp_variation, 2))
            
            base_pressure = 14.7
            pressure_variation = math.sin(cycle / 60) * 0.5 + random.uniform(-0.1, 0.1)
            await pressure.write_value(round(base_pressure + pressure_variation, 2))
            
            base_vibration = 0.5
            if random.random() > 0.98:
                await vibration.write_value(round(random.uniform(2.0, 5.0), 2))
            else:
                await vibration.write_value(round(base_vibration + random.uniform(-0.2, 0.2), 2))
            
            if cycle % 10 == 0:
                log_json("INFO", f"Cycle {cycle}: Temp={round(base_temp + temp_variation, 1)}", "PLC")

if __name__ == "__main__":
    asyncio.run(main())
