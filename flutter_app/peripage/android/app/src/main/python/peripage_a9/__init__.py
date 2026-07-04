"""
peripage_a9/__init__.py

Package driver PeriPage A9 dengan arsitektur transport-agnostic.
Support USB (desktop) dan BLE (mobile) melalui interface yang sama.
"""

from .driver import PeriPageA9USB, PeriPageA9BLE
from .protocol import (
    SUPPORTED_PAPER_WIDTHS_MM,
    DEFAULT_PAPER_WIDTH_MM,
    load_paper_width_mm,
    save_paper_width_mm,
    get_paper_dimensions,
    smart_crop_and_resize,
)
from .transport_usb import UsbTransport, TransportError as UsbTransportError
from .transport_ble import BleTransportDefault as BleTransport, TransportError as BleTransportError

__version__ = "2.0.0"
__all__ = [
    "PeriPageA9USB",
    "PeriPageA9BLE",
    "UsbTransport",
    "BleTransport",
    "UsbTransportError",
    "BleTransportError",
    "SUPPORTED_PAPER_WIDTHS_MM",
    "DEFAULT_PAPER_WIDTH_MM",
    "load_paper_width_mm",
    "save_paper_width_mm",
    "get_paper_dimensions",
    "smart_crop_and_resize",
]
