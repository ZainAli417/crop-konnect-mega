from gpiozero import OutputDevice
from gpiozero.pins.lgpio import LGPIOFactory
from time import sleep

factory = LGPIOFactory()

# Your real GPIO mapping:
# IN4 -> GPIO17 / Physical Pin 11
# IN3 -> GPIO27 / Physical Pin 13
# IN2 -> GPIO22 / Physical Pin 15
# IN1 -> GPIO23 / Physical Pin 16

# Most 5V relay modules are ACTIVE LOW
# relay.on()  = Relay ON
# relay.off() = Relay OFF

relays = {
    "IN1": OutputDevice(23, active_high=False, initial_value=False, pin_factory=factory),
    "IN2": OutputDevice(22, active_high=False, initial_value=False, pin_factory=factory),
    "IN3": OutputDevice(27, active_high=False, initial_value=False, pin_factory=factory),
    "IN4": OutputDevice(17, active_high=False, initial_value=False, pin_factory=factory),
}

ON_TIME = 3
OFF_TIME = 1


def all_relays_off():
    for relay in relays.values():
        relay.off()
    print("All relays OFF")


try:
    print("Starting 4-channel relay test with your real wiring...")
    all_relays_off()
    sleep(2)

    for name, relay in relays.items():
        print(f"{name} ON")
        relay.on()
        sleep(ON_TIME)

        print(f"{name} OFF")
        relay.off()
        sleep(OFF_TIME)

    print("Relay test completed successfully.")
    all_relays_off()

except KeyboardInterrupt:
    print("\nTest stopped by user.")
    all_relays_off()

except Exception as e:
    print(f"Error: {e}")
    all_relays_off()

finally:
    for relay in relays.values():
        relay.close()
