import minimalmodbus
import serial
import time

# ── CONFIGURATION ────────────────────────────────────────────────────────────
PORT = '/dev/ttyUSB1'      # Your specified port
SLAVE_ID = 1             # node.begin(1, ...)
BAUD_RATE = 4800           # Matching your Arduino code modbusPort.begin(4800)

# Initialize the instrument
# This replaces: node.begin(1, modbusPort)
instrument = minimalmodbus.Instrument(PORT, SLAVE_ID)

# Port Settings
instrument.serial.baudrate = BAUD_RATE
instrument.serial.bytesize = 8
instrument.serial.parity   = serial.PARITY_NONE
instrument.serial.stopbits = 1
instrument.serial.timeout  = 1          # Seconds

# Communication mode (RTU is default)
instrument.mode = minimalmodbus.MODE_RTU

def main():
    print(f"Modbus RTU ready on {PORT} @{BAUD_RATE}bps")
    
    while True:
        try:
            # ── READ HOLDING REGISTER ────────────────────────────────────────
            # Logic: node.readHoldingRegisters(0x0000, 1)
            # functioncode=3 is for Holding Registers
            # number_of_decimals=1 handles the "raw / 10.0" logic automatically
            
            wind_speed = instrument.read_register(0, number_of_decimals=1, functioncode=3)
            
            print(f"Wind Speed: {wind_speed} m/s")

        except IOError:
            print("Modbus Error: Failed to read from instrument")
        except Exception as e:
            print(f"An unexpected error occurred: {e}")

        # Matches delay(1500)
        time.sleep(1.5)

if __name__ == "__main__":
    main()
