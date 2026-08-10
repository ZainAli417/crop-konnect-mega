import minimalmodbus
import serial
import time

# ── CONFIGURATION ────────────────────────────────────────────────────────────
PORT = '/dev/ttyUSB1'      # Your specified port
SLAVE_ID = 1               # node.begin(1, ...)
BAUD_RATE = 4800           # RS485Serial.begin(4800)

# Initialize the instrument
instrument = minimalmodbus.Instrument(PORT, SLAVE_ID)

# Port Settings
instrument.serial.baudrate = BAUD_RATE
instrument.serial.bytesize = 8
instrument.serial.parity   = serial.PARITY_NONE
instrument.serial.stopbits = 1
instrument.serial.timeout  = 1          # 1 second timeout

# Communication mode
instrument.mode = minimalmodbus.MODE_RTU
instrument.clear_buffers_before_each_transaction = True

def main():
    print(f"Modbus RTU Rainfall Sensor ready on {PORT} @{BAUD_RATE}bps")
    
    while True:
        try:
            # 1) Read raw rainfall from register 0x0000
            # Matches: node.readHoldingRegisters(0x0000, 1)
            # functioncode=3 is for Holding Registers
            raw_rain = instrument.read_register(0, functioncode=3)
            
            # 2) Logic: rawRain / 10.0
            rainfall = raw_rain / 10.0
            
            print(f"Rainfall: {rainfall:.1f} mm")

            # 3) Simple "rain prediction" logic
            if raw_rain > 0:
                print("Prediction: Yes It's Raining ✔")
            else:
                print("Prediction: No It's Raining ✘")

        except IOError:
            print("Rainfall read error: Check connection or Slave ID")
        except Exception as e:
            print(f"Unexpected error: {e}")

        print("-----------------------------")
        
        # Matches delay(5000)
        time.sleep(5)

if __name__ == "__main__":
    main() 