# wind_direction_gear_fixed.py
import minimalmodbus
import time

# ============================= CONFIG =============================
PORT = '/dev/ttyUSB3'          # Your port
BAUDRATE = 4800        # Fixed for your model
SLAVE_ID = 1          # Detected/working
POLL_INTERVAL = 1.0
# =================================================================

# 16 universal directions (standard meteorological)
UNIVERSAL_DIRS = [
    'Shumal',        # N
    'Shumal Mashriq',# NNE
    'Mashriq Shumal',# NE
    'Mashriq',       # ENE
    'Mashriq',       # E
    'Junub Mashriq', # ESE
    'Mashriq Junub', # SE
    'Junub Mashriq', # SSE
    'Junub',         # S
    'Junub Maghrib', # SSW
    'Maghrib Junub', # SW
    'Maghrib',       # WSW
    'Maghrib',       # W
    'Shumal Maghrib',# WNW
    'Maghrib Shumal',# NW
    'Shumal Maghrib' # NNW
]


instrument = minimalmodbus.Instrument(PORT, SLAVE_ID)
instrument.serial.baudrate = BAUDRATE
instrument.serial.timeout = 0.5
instrument.serial.bytesize = 8
instrument.serial.parity = minimalmodbus.serial.PARITY_NONE
instrument.serial.stopbits = 1
instrument.mode = minimalmodbus.MODE_RTU
instrument.debug = False  # Set True for raw Modbus debug

def read_wind_gear():
    try:
        # Read gear code (0-15) from register 0x0000
        gear_raw = instrument.read_register(0x0000, functioncode=3, signed=False, number_of_decimals=0)
        
        # Clamp to valid range (handles noise >15)
        gear = max(0, min(15, gear_raw))
        
        # Compute mid-sector degrees (gear * 22.5°)
        degrees = gear * 22.5
        
        # Map to universal direction
        direction = UNIVERSAL_DIRS[gear]
        
        return degrees, direction, gear
    
    except Exception as e:
        print(f"Read error: {e}")
        return None, None, None

print("Wind Direction Sensor - 16-Gear Model Fixed")
print("Rotate vane full circle: Expect jumps every ~22.5° (e.g., 0° N → 22.5° NNE → 45° NE, etc.)\n")

try:
    while True:
        deg, dir_str, gear = read_wind_gear()
        if deg is not None:
            print(f"Gear: {gear:2d} → Degrees: {deg:4.1f}° → Direction: {dir_str}")
        else:
            print("No response - check power/wiring")
        time.sleep(POLL_INTERVAL)

except KeyboardInterrupt:
    print("\nStopped by user")
finally:
    instrument.serial.close()
