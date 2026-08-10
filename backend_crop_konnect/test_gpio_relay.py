import logging
import sys
import types
import unittest

from app.config import Settings
from app.gpio_relay import create_gpio_output


class FakeGPIO:
    BCM = 1
    OUT = 0
    _used = set()

    @staticmethod
    def setwarnings(*_args, **_kwargs):
        pass

    @staticmethod
    def setmode(*_args, **_kwargs):
        pass

    @staticmethod
    def setup(pin, *_args, **_kwargs):
        if pin in FakeGPIO._used:
            raise RuntimeError("GPIO busy")
        FakeGPIO._used.add(pin)

    @staticmethod
    def output(*_args, **_kwargs):
        pass

    @staticmethod
    def cleanup():
        FakeGPIO._used.clear()


class TestRelayGPIO(unittest.TestCase):
    def setUp(self):
        FakeGPIO._used.clear()
        fake_rpi = types.ModuleType("RPi")
        fake_rpi.GPIO = FakeGPIO
        sys.modules["RPi"] = fake_rpi
        sys.modules["RPi.GPIO"] = FakeGPIO

    def test_create_gpio_output_allows_same_pin_to_be_reused(self):
        settings = Settings(_env_file=".env")
        logger = logging.getLogger("test")

        first = create_gpio_output(settings, [23], logger)
        second = create_gpio_output(settings, [23], logger)

        self.assertIsNotNone(first)
        self.assertIsNotNone(second)
        self.assertEqual(first.driver_name, second.driver_name)


if __name__ == "__main__":
    unittest.main()
