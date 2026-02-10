"""
EV Battery Pack Simulator for DMC IPC Platform PoC
Simulates high-speed battery monitoring system (CAN bus style data)

This demonstrates:
- High-cardinality metrics (96 cell voltages)
- High-frequency updates (configurable, default 2Hz for demo)
- Slowly changing state (State of Charge draining)

Business Context: DMC builds EV battery end-of-line test systems.
This is their high-volume revenue driver.
"""

import asyncio
import json
import os
import random
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from azure.iot.device.aio import IoTHubDeviceClient
from azure.iot.device import Message

# Configuration
IOT_HUB_CONNECTION_STRING = os.getenv("IOT_HUB_CONNECTION_STRING", "")
PUBLISH_INTERVAL = float(os.getenv("PUBLISH_INTERVAL", "0.5"))  # 2Hz default
DEVICE_ID = os.getenv("DEVICE_ID", "ev-battery-lab-01")
NUM_CELLS = int(os.getenv("NUM_CELLS", "96"))
HEALTH_PORT = 8080

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="EVBatterySimulator", **kwargs):
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
        # Suppress default HTTP logging to keep stdout clean
        pass

def start_health_server():
    try:
        server = HTTPServer(('0.0.0.0', HEALTH_PORT), HealthHandler)
        log_json("INFO", f"Health server listening on port {HEALTH_PORT}", "HealthCheck")
        server.serve_forever()
    except Exception as e:
        log_json("ERROR", f"Failed to start health server: {e}", "HealthCheck")

# Simulation state
class BatteryPackState:
    def __init__(self, num_cells: int):
        self.num_cells = num_cells
        self.state_of_charge = 100.0  # Starts full
        self.pack_voltage = 400.0  # Nominal 400V pack
        self.pack_current = 0.0
        self.pack_temp = 25.0
        self.cycle_count = 0
        
        # Cell voltages - slight variance around nominal
        self.cell_voltages = [
            3.7 + random.uniform(-0.05, 0.05) 
            for _ in range(num_cells)
        ]
        
        # Discharge rate (% per second at full load)
        self.discharge_rate = 0.02
        
        # Simulate a test cycle
        self.test_phase = "IDLE"  # IDLE, CHARGING, DISCHARGING, REST
        self.phase_timer = 0
        
    def update(self, dt: float):
        """Update battery state based on elapsed time"""
        self.cycle_count += 1
        self.phase_timer += dt
        
        # Cycle through test phases
        if self.test_phase == "IDLE" and self.phase_timer > 5:
            self.test_phase = "DISCHARGING"
            self.phase_timer = 0
            log_json("INFO", "Starting DISCHARGE test")
            
        elif self.test_phase == "DISCHARGING":
            # Discharge at constant current
            self.pack_current = -150.0  # 150A discharge
            self.state_of_charge -= self.discharge_rate * dt * 10
            self.pack_temp += 0.01 * dt  # Slight heating
            
            if self.state_of_charge <= 20.0:
                self.test_phase = "REST"
                self.phase_timer = 0
                log_json("INFO", "Discharge complete, entering REST")
                
        elif self.test_phase == "REST" and self.phase_timer > 10:
            self.test_phase = "CHARGING"
            self.phase_timer = 0
            log_json("INFO", "Starting CHARGE cycle")
            
        elif self.test_phase == "CHARGING":
            # Charge at constant current
            self.pack_current = 75.0  # 75A charge
            self.state_of_charge += self.discharge_rate * dt * 5
            self.pack_temp -= 0.005 * dt  # Slight cooling
            
            if self.state_of_charge >= 95.0:
                self.test_phase = "IDLE"
                self.phase_timer = 0
                log_json("INFO", "Charge complete, entering IDLE")
                
        elif self.test_phase == "IDLE":
            self.pack_current = 0.0
            
        # Keep SoC in bounds
        self.state_of_charge = max(0.0, min(100.0, self.state_of_charge))
        
        # Update pack voltage based on SoC
        # Simplified: 3.0V (empty) to 4.2V (full) per cell
        cell_voltage_base = 3.0 + (self.state_of_charge / 100.0) * 1.2
        
        # Update individual cell voltages with realistic variance
        for i in range(self.num_cells):
            # Each cell drifts slightly
            drift = random.gauss(0, 0.002)
            self.cell_voltages[i] = cell_voltage_base + drift
            # Clamp to realistic range
            self.cell_voltages[i] = max(2.8, min(4.25, self.cell_voltages[i]))
        
        # Pack voltage is sum of cells
        self.pack_voltage = sum(self.cell_voltages)
        
        # Temperature bounds
        self.pack_temp = max(20.0, min(45.0, self.pack_temp))
        
    def to_telemetry(self) -> dict:
        """Generate telemetry message"""
        telemetry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "deviceId": DEVICE_ID,
            "dataType": "ev_battery",
            "pack": {
                "voltage": round(self.pack_voltage, 2),
                "current": round(self.pack_current, 2),
                "stateOfCharge": round(self.state_of_charge, 1),
                "temperature": round(self.pack_temp, 1),
                "testPhase": self.test_phase,
                "cycleCount": self.cycle_count
            },
            "cells": {}
        }
        
        # Add individual cell voltages
        for i, voltage in enumerate(self.cell_voltages):
            telemetry["cells"][f"cell_{i+1:02d}"] = round(voltage, 4)
            
        # Add derived metrics
        telemetry["pack"]["cellMin"] = round(min(self.cell_voltages), 4)
        telemetry["pack"]["cellMax"] = round(max(self.cell_voltages), 4)
        telemetry["pack"]["cellDelta"] = round(
            max(self.cell_voltages) - min(self.cell_voltages), 4
        )
        
        return telemetry


async def main():
    # Start Health Server
    health_thread = threading.Thread(target=start_health_server, daemon=True)
    health_thread.start()

    log_json("INFO", "EV Battery Pack Simulator Starting")
    log_json("INFO", f"Device ID: {DEVICE_ID}")
    log_json("INFO", f"Number of cells: {NUM_CELLS}")
    log_json("INFO", f"Publish interval: {PUBLISH_INTERVAL}s ({1/PUBLISH_INTERVAL:.1f} Hz)")
    
    # Initialize battery state
    battery = BatteryPackState(NUM_CELLS)
    
    # Connect to IoT Hub
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
            log_json("WARNING", "Running in local-only mode", "IoTHub")
            iot_client = None
    else:
        log_json("WARNING", "No connection string provided. Running in local-only mode", "IoTHub")
    
    log_json("INFO", "Starting simulation loop", "Simulator")
    
    try:
        message_count = 0
        while True:
            # Update battery state
            battery.update(PUBLISH_INTERVAL)
            
            # Generate telemetry
            telemetry = battery.to_telemetry()
            message_count += 1
            
            # Log summary (not full payload - too large)
            if message_count % 10 == 0:  # Log every 10th message
                msg = (f"Pack: {telemetry['pack']['voltage']:.1f}V, "
                       f"{telemetry['pack']['current']:.1f}A, "
                       f"SoC: {telemetry['pack']['stateOfCharge']:.1f}%, "
                       f"Phase: {telemetry['pack']['testPhase']}")
                log_json("INFO", msg, "Telemetry")
            
            # Send to IoT Hub
            if iot_client:
                try:
                    message = Message(json.dumps(telemetry))
                    message.content_type = "application/json"
                    message.content_encoding = "utf-8"
                    message.custom_properties["dataType"] = "ev_battery"
                    await iot_client.send_message(message)
                except Exception as e:
                    log_json("ERROR", f"Send failed: {e}", "IoTHub")
            
            await asyncio.sleep(PUBLISH_INTERVAL)
            
    except KeyboardInterrupt:
        log_json("INFO", "Shutting down...", "System")
    finally:
        if iot_client:
            await iot_client.disconnect()
            log_json("INFO", "Disconnected from IoT Hub", "IoTHub")


if __name__ == "__main__":
    asyncio.run(main())
