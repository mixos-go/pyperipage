"""
Python Service Entry Point for Chaquopy Android Integration
Bridges Flutter Dart code with Python printing logic
"""

from peripage_a9.driver import PeriPageDriver
from peripage_a9.transport_usb import USBTransport
from peripage_a9.transport_ble import BLETransport
from PIL import Image
import io
import base64

# Global driver instance
_driver = None

def initialize_driver(transport_type: str = "usb"):
    """Initialize the printer driver with specified transport"""
    global _driver
    if transport_type == "ble":
        transport = BLETransport()
    else:
        transport = USBTransport()
    
    _driver = PeriPageDriver(transport)
    return {"status": "initialized", "transport": transport_type}

def connect_printer(device_address: str = None):
    """Connect to the printer"""
    global _driver
    if not _driver:
        return {"error": "Driver not initialized"}
    
    try:
        _driver.connect(device_address)
        return {"status": "connected", "address": device_address}
    except Exception as e:
        return {"error": str(e)}

def disconnect_printer():
    """Disconnect from the printer"""
    global _driver
    if _driver:
        _driver.disconnect()
        return {"status": "disconnected"}
    return {"error": "Driver not initialized"}

def scan_ble_devices():
    """Scan for BLE devices (PeriPage A9)"""
    from peripage_a9.transport_ble import scan_for_printer
    try:
        devices = scan_for_printer(timeout=5.0)
        return {
            "devices": [
                {"address": d.address, "name": d.name, "rssi": d.rssi} 
                for d in devices
            ]
        }
    except Exception as e:
        return {"error": str(e)}

def print_image(image_data: str, options: dict = None):
    """
    Print image from base64 encoded string
    image_data: base64 encoded image
    options: dict with print settings (width, density, etc.)
    """
    global _driver
    if not _driver:
        return {"error": "Driver not initialized"}
    
    try:
        # Decode base64 image
        image_bytes = base64.b64decode(image_data)
        image = Image.open(io.BytesIO(image_bytes))
        
        # Apply print options
        width = options.get("width", 576) if options else 576
        dither = options.get("dither", True) if options else True
        
        # Print the image
        _driver.print_image(image, width=width, dither=dither)
        
        return {"status": "success", "message": "Image printed"}
    except Exception as e:
        return {"error": str(e)}

def print_pdf(pdf_data: str, options: dict = None):
    """
    Print PDF from base64 encoded string
    pdf_data: base64 encoded PDF
    options: dict with print settings
    """
    global _driver
    if not _driver:
        return {"error": "Driver not initialized"}
    
    try:
        # Decode base64 PDF
        pdf_bytes = base64.b64decode(pdf_data)
        
        # Use driver's PDF print method
        _driver.print_pdf_from_bytes(pdf_bytes, options=options)
        
        return {"status": "success", "message": "PDF printed"}
    except Exception as e:
        return {"error": str(e)}

def print_text(text: str, options: dict = None):
    """Print plain text"""
    global _driver
    if not _driver:
        return {"error": "Driver not initialized"}
    
    try:
        _driver.print_text(text, options=options)
        return {"status": "success", "message": "Text printed"}
    except Exception as e:
        return {"error": str(e)}

def get_printer_status():
    """Get printer status"""
    global _driver
    if not _driver:
        return {"error": "Driver not initialized"}
    
    try:
        status = _driver.get_status()
        return {"status": "success", "data": status}
    except Exception as e:
        return {"error": str(e)}

def feed_paper(lines: int = 3):
    """Feed paper by specified lines"""
    global _driver
    if not _driver:
        return {"error": "Driver not initialized"}
    
    try:
        _driver.feed(lines)
        return {"status": "success", "lines": lines}
    except Exception as e:
        return {"error": str(e)}

def cut_paper():
    """Cut the paper"""
    global _driver
    if not _driver:
        return {"error": "Driver not initialized"}
    
    try:
        _driver.cut()
        return {"status": "success", "message": "Paper cut"}
    except Exception as e:
        return {"error": str(e)}
