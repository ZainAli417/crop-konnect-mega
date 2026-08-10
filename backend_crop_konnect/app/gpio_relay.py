from __future__ import annotations

import logging
from typing import Protocol

from app.config import Settings


class GpioOutput(Protocol):
    driver_name: str

    def output(self, pin: int, value: int) -> None:
        ...

    def cleanup(self) -> None:
        ...


_ACTIVE_GPIO_OUTPUTS: dict[int, "SharedGpioOutput"] = {}


class SharedGpioOutput:
    """Allow multiple relay controllers to share one GPIO handle.

    The solar and main sensor relay loops both claim the same pin on startup.
    Reusing the already-allocated handle prevents the duplicate "GPIO busy"
    failure while still letting both callers write to the same relay.
    """

    def __init__(self, output: GpioOutput, pins: list[int]) -> None:
        self._output = output
        self._pins = list(dict.fromkeys(pins))
        self._refcount = 1
        self.driver_name = output.driver_name
        for pin in self._pins:
            _ACTIVE_GPIO_OUTPUTS[pin] = self

    def output(self, pin: int, value: int) -> None:
        self._output.output(pin, value)

    def cleanup(self) -> None:
        if self._refcount <= 0:
            return
        self._refcount -= 1
        if self._refcount > 0:
            return
        try:
            self._output.cleanup()
        finally:
            for pin in self._pins:
                _ACTIVE_GPIO_OUTPUTS.pop(pin, None)


class RpiGpioOutput:
    driver_name = "RPi.GPIO"

    def __init__(self, settings: Settings, pins: list[int]) -> None:
        import RPi.GPIO as GPIO  # type: ignore

        mode = str(settings.relay_gpio_mode or "BCM").strip().upper()
        GPIO.setwarnings(False)
        GPIO.setmode(GPIO.BOARD if mode == "BOARD" else GPIO.BCM)
        for pin in pins:
            GPIO.setup(pin, GPIO.OUT)
        self._gpio = GPIO

    def output(self, pin: int, value: int) -> None:
        self._gpio.output(pin, value)

    def cleanup(self) -> None:
        self._gpio.cleanup()


class LgpioOutput:
    driver_name = "lgpio"

    def __init__(self, settings: Settings, pins: list[int]) -> None:
        mode = str(settings.relay_gpio_mode or "BCM").strip().upper()
        if mode != "BCM":
            raise RuntimeError("lgpio fallback requires RELAY_GPIO_MODE=BCM")

        import lgpio  # type: ignore

        self._lgpio = lgpio
        self._handle = lgpio.gpiochip_open(0)
        self._pins = list(pins)
        for pin in self._pins:
            lgpio.gpio_claim_output(self._handle, pin)

    def output(self, pin: int, value: int) -> None:
        self._lgpio.gpio_write(self._handle, pin, value)

    def cleanup(self) -> None:
        for pin in self._pins:
            try:
                self._lgpio.gpio_free(self._handle, pin)
            except Exception:
                pass
        try:
            self._lgpio.gpiochip_close(self._handle)
        except Exception:
            pass


def create_gpio_output(
    settings: Settings,
    pins: list[int],
    logger: logging.Logger,
) -> GpioOutput:
    if not pins:
        raise RuntimeError("No relay GPIO pins configured")

    unique_pins = list(dict.fromkeys(pin for pin in pins if pin is not None))
    for pin in unique_pins:
        existing = _ACTIVE_GPIO_OUTPUTS.get(pin)
        if existing is not None:
            existing._refcount += 1
            return existing

    try:
        output = RpiGpioOutput(settings, unique_pins)
        return SharedGpioOutput(output, unique_pins)
    except Exception as exc:
        logger.warning("RPi.GPIO relay setup failed: %s", exc)

    try:
        output = LgpioOutput(settings, unique_pins)
        return SharedGpioOutput(output, unique_pins)
    except Exception as exc:
        raise RuntimeError(f"lgpio relay setup failed: {exc}") from exc
