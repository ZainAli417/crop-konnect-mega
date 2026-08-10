import minimalmodbus
import serial
import time

# --- Configuration ---
PORT = '/dev/ttyUSB3'
SLAVE_ADDRESS = 1       # Default Modbus address for most of these sensors is 1
BAUDRATE = 4800         # Default is usually 9600 (sometimes 4800, change if you get errors)
REGISTER_ADDRESS = 0    # Address where the radiation value is stored (usually 0x0000)
# ---------------------

try:
    # Initialize the Modbus instrument
    sensor = minimalmodbus.Instrument(PORT, SLAVE_ADDRESS)

    # Serial port setup for standard industrial Modbus RTU
    sensor.serial.baudrate = BAUDRATE
    sensor.serial.bytesize = 8
    sensor.serial.parity   = serial.PARITY_NONE
    sensor.serial.stopbits = 1
    sensor.serial.timeout  = 1.0     # 1 second timeout

    sensor.mode = minimalmodbus.MODE_RTU

    print(f"Successfully connected to RS485 converter on {PORT}.")
    print("Beginning solar radiation readings...\n")

except Exception as e:
    print(f"Error initializing serial port: {e}")
    exit()

while True:
    try:
        # Read the solar radiation value
        # Arg 1: Register address (0)
        # Arg 2: Number of decimals (0, since resolution is 1 W/m^2)
        # Arg 3: Function code (3 = Read Holding Registers, 4 = Read Input Registers)
        # Note: If function code 3 throws an error, try function code 4.
        solar_radiation = sensor.read_register(REGISTER_ADDRESS, 0, functioncode=3)

        print(f"Total Solar Radiation: {solar_radiation} W/m²")

        # In a full IoT script, you would append this value to your Firebase upload payload here.

    except minimalmodbus.NoResponseError:
        print("Error: No response from sensor. Check 7-30V power supply, A/B wiring, and Baudrate.")
    except minimalmodbus.IllegalRequestError:
        print("Error: Illegal request. The register address (0) or function code (3) might be different for this specific batch. Try functioncode=4.")
    except Exception as e:
        print(f"Unexpected error reading from sensor: {e}")

    time.sleep(2) # Poll every 2 seconds
