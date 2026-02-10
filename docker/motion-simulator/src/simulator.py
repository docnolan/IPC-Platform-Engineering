"""
Motion/Gantry Simulator for DMC IPC Platform PoC
Simulates a 3-axis servo gantry system via OPC-UA

This demonstrates:
- Real-time correlated state (X, Y, Z positions)
- Standard industrial protocol (OPC-UA)
- Temperature with feedback control (fan simulation)
"""

import asyncio
import json
import random
import math
import threading
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from asyncua import Server, ua

OPCUA_PORT = 4841
HEALTH_PORT = 8080
UPDATE_INTERVAL = 0.1  # 10Hz

# --- Op Maturity: Structured Logging ---
def log_json(level, message, component="MotionSimulator", **kwargs):
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


class GantrySimulator:
    def __init__(self):
        self.x_pos = 0.0
        self.y_pos = 0.0
        self.z_pos = 0.0
        self.x_vel = 0.0
        self.y_vel = 0.0
        self.z_vel = 0.0
        self.motor_temp = 25.0
        self.ambient_temp = 22.0
        self.fan_on = False
        self.fan_threshold_high = 45.0
        self.fan_threshold_low = 35.0
        self.pattern_phase = 0.0
        self.motion_mode = "CIRCLE"
        self.cycle_count = 0
        self.in_motion = False
        self.alarm_active = False
        self.servo_enabled = True
        
    def update(self, dt: float):
        self.pattern_phase += dt
        
        if self.motion_mode == "CIRCLE":
            radius = 100.0
            speed = 0.5
            self.x_pos = radius * math.cos(self.pattern_phase * speed)
            self.y_pos = radius * math.sin(self.pattern_phase * speed)
            self.z_pos = 50.0 + 20.0 * math.sin(self.pattern_phase * speed * 2)
            self.in_motion = True
            
        elif self.motion_mode == "PICK_PLACE":
            cycle_time = 4.0
            phase = (self.pattern_phase % cycle_time) / cycle_time
            
            if phase < 0.25:
                self.x_pos = 0.0
                self.y_pos = 0.0
                self.z_pos = 100.0 - (phase * 4 * 80)
            elif phase < 0.5:
                progress = (phase - 0.25) * 4
                self.x_pos = 150.0 * progress
                self.y_pos = 75.0 * progress
                self.z_pos = 20.0 + 30.0 * math.sin(progress * math.pi)
            elif phase < 0.75:
                self.x_pos = 150.0
                self.y_pos = 75.0
                self.z_pos = 50.0 - ((phase - 0.5) * 4 * 30)
            else:
                progress = (phase - 0.75) * 4
                self.x_pos = 150.0 * (1 - progress)
                self.y_pos = 75.0 * (1 - progress)
                self.z_pos = 20.0 + 80.0 * progress
            
            self.in_motion = True
            if phase < 0.1 and self.pattern_phase > 1:
                self.cycle_count += 1
        
        # Add noise
        self.x_pos += random.gauss(0, 0.01)
        self.y_pos += random.gauss(0, 0.01)
        self.z_pos += random.gauss(0, 0.005)
        
        self.x_vel = random.uniform(100, 200) if self.in_motion else 0
        self.y_vel = random.uniform(100, 200) if self.in_motion else 0
        self.z_vel = random.uniform(50, 100) if self.in_motion else 0
        
        # Temperature simulation
        if self.in_motion:
            self.motor_temp += 0.02 * dt
        
        cooling_rate = 0.05 if self.fan_on else 0.01
        self.motor_temp -= cooling_rate * (self.motor_temp - self.ambient_temp) * dt
        
        # Fan control with hysteresis
        if self.motor_temp > self.fan_threshold_high and not self.fan_on:
            self.fan_on = True
            log_json("INFO", f"Fan ON - Temp: {self.motor_temp:.1f}°C", "Thermal")
        elif self.motor_temp < self.fan_threshold_low and self.fan_on:
            self.fan_on = False
            log_json("INFO", f"Fan OFF - Temp: {self.motor_temp:.1f}°C", "Thermal")
        
        if self.motor_temp > 55.0 and not self.alarm_active:
            self.alarm_active = True
            log_json("WARNING", f"Overtemperature! {self.motor_temp:.1f}°C", "Alarm")
        elif self.motor_temp <= 55.0:
            self.alarm_active = False


async def main():
    # Start Health Server
    threading.Thread(target=start_health_server, daemon=True).start()

    log_json("INFO", "Motion/Gantry OPC-UA Simulator Starting")
    log_json("INFO", f"OPC-UA Port: {OPCUA_PORT}")
    log_json("INFO", f"Update interval: {UPDATE_INTERVAL}s ({1/UPDATE_INTERVAL:.0f} Hz)")
    
    server = Server()
    await server.init()
    
    endpoint = f"opc.tcp://0.0.0.0:{OPCUA_PORT}/freeopcua/server/"
    server.set_endpoint(endpoint)
    server.set_server_name("DMC Gantry Simulator")
    
    uri = "http://dmc.com/opcua/gantry"
    idx = await server.register_namespace(uri)
    
    objects = server.nodes.objects
    gantry = await objects.add_object(idx, "GantryB")
    
    # Create variables
    x_pos = await gantry.add_variable(idx, "Axis_X_Pos", 0.0)
    y_pos = await gantry.add_variable(idx, "Axis_Y_Pos", 0.0)
    z_pos = await gantry.add_variable(idx, "Axis_Z_Pos", 0.0)
    x_vel = await gantry.add_variable(idx, "Axis_X_Vel", 0.0)
    y_vel = await gantry.add_variable(idx, "Axis_Y_Vel", 0.0)
    z_vel = await gantry.add_variable(idx, "Axis_Z_Vel", 0.0)
    motor_temp = await gantry.add_variable(idx, "Motor_Temp", 25.0)
    fan_status = await gantry.add_variable(idx, "Fan_Status", False)
    servo_enabled = await gantry.add_variable(idx, "Servo_Enabled", True)
    in_motion = await gantry.add_variable(idx, "In_Motion", False)
    alarm_active = await gantry.add_variable(idx, "Alarm_Active", False)
    cycle_count = await gantry.add_variable(idx, "Cycle_Count", 0)
    motion_mode = await gantry.add_variable(idx, "Motion_Mode", "CIRCLE")
    
    for var in [x_pos, y_pos, z_pos, x_vel, y_vel, z_vel, motor_temp, 
                fan_status, servo_enabled, in_motion, alarm_active, 
                cycle_count, motion_mode]:
        await var.set_writable()
    
    log_json("INFO", f"OPC-UA Server started at {endpoint}", "OPCUA")
    log_json("INFO", f"Namespace: {uri}", "OPCUA")
    
    gantry_sim = GantrySimulator()
    modes = ["CIRCLE", "PICK_PLACE"]
    mode_index = 0
    mode_timer = 0
    mode_duration = 30
    
    async with server:
        try:
            while True:
                gantry_sim.update(UPDATE_INTERVAL)
                
                mode_timer += UPDATE_INTERVAL
                if mode_timer >= mode_duration:
                    mode_timer = 0
                    mode_index = (mode_index + 1) % len(modes)
                    gantry_sim.motion_mode = modes[mode_index]
                    gantry_sim.pattern_phase = 0
                    log_json("INFO", f"Switching to {gantry_sim.motion_mode}", "Mode")
                
                await x_pos.write_value(round(gantry_sim.x_pos, 3))
                await y_pos.write_value(round(gantry_sim.y_pos, 3))
                await z_pos.write_value(round(gantry_sim.z_pos, 3))
                await x_vel.write_value(round(gantry_sim.x_vel, 1))
                await y_vel.write_value(round(gantry_sim.y_vel, 1))
                await z_vel.write_value(round(gantry_sim.z_vel, 1))
                await motor_temp.write_value(round(gantry_sim.motor_temp, 1))
                await fan_status.write_value(gantry_sim.fan_on)
                await servo_enabled.write_value(gantry_sim.servo_enabled)
                await in_motion.write_value(gantry_sim.in_motion)
                await alarm_active.write_value(gantry_sim.alarm_active)
                await cycle_count.write_value(gantry_sim.cycle_count)
                await motion_mode.write_value(gantry_sim.motion_mode)
                
                await asyncio.sleep(UPDATE_INTERVAL)
                
        except KeyboardInterrupt:
            log_json("INFO", "Shutting down...", "System")


if __name__ == "__main__":
    asyncio.run(main())
