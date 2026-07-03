"""
python_service.py - Entry Point untuk Chaquopy (Android)

File ini berfungsi sebagai jembatan antara Kotlin/Flutter dengan logic Python.
Semua fungsi dipanggil secara synchronous dari Java/Kotlin melalui Chaquopy.
"""
import json
import io
from PIL import Image

# Import driver dan protocol
from . import driver
from . import protocol


def get_supported_paper_widths():
    """Return daftar lebar kertas yang didukung (mm)."""
    return protocol.SUPPORTED_PAPER_WIDTHS_MM


def get_default_paper_width():
    """Return lebar kertas default."""
    return protocol.DEFAULT_PAPER_WIDTH_MM


def load_current_paper_width():
    """Load setting lebar kertas terakhir yang disimpan."""
    return protocol.load_paper_width_mm()


def save_paper_width(paper_width_mm):
    """Simpan setting lebar kertas."""
    protocol.save_paper_width_mm(paper_width_mm, warning_tag="ANDROID")
    return True


def scan_ble_devices(timeout=5.0):
    """
    Scan device BLE PeriPage A9 di sekitar.
    Return list of dict: [{'name': str, 'address': str, 'rssi': int}]
    """
    try:
        from .transport_ble import BleTransportSync
        transport = BleTransportSync()
        devices = transport.discover_devices(timeout=timeout)
        return devices
    except Exception as e:
        print(f"[ANDROID SERVICE ERROR] Gagal scan BLE: {e}")
        import traceback
        traceback.print_exc()
        return []


def connect_usb(vid=0x09c5, pid=0x0200, paper_width_mm=None):
    """
    Koneksi ke printer via USB.
    Return dict: {'success': bool, 'message': str}
    """
    try:
        printer = driver.PeriPageA9USB(vid=vid, pid=pid, paper_width_mm=paper_width_mm)
        success = printer.connect()
        
        if success:
            # Simpan reference printer di global state untuk digunakan nanti
            global _usb_printer
            _usb_printer = printer
            return {'success': True, 'message': 'USB connected successfully'}
        else:
            return {'success': False, 'message': 'Failed to connect via USB'}
    except Exception as e:
        return {'success': False, 'message': f'USB connection error: {str(e)}'}


def connect_ble(device_address=None, paper_width_mm=None):
    """
    Koneksi ke printer via BLE.
    Return dict: {'success': bool, 'message': str}
    """
    try:
        printer = driver.PeriPageA9BLE(device_address=device_address, paper_width_mm=paper_width_mm)
        success = printer.connect()
        
        if success:
            # Simpan reference printer di global state untuk digunakan nanti
            global _ble_printer
            _ble_printer = printer
            return {'success': True, 'message': 'BLE connected successfully'}
        else:
            return {'success': False, 'message': 'Failed to connect via BLE'}
    except Exception as e:
        return {'success': False, 'message': f'BLE connection error: {str(e)}'}


def disconnect_usb():
    """Disconnect printer USB."""
    try:
        global _usb_printer
        if '_usb_printer' in globals() and _usb_printer:
            _usb_printer._transport.close()
            _usb_printer = None
        return {'success': True, 'message': 'USB disconnected'}
    except Exception as e:
        return {'success': False, 'message': f'Disconnect error: {str(e)}'}


def disconnect_ble():
    """Disconnect printer BLE."""
    try:
        global _ble_printer
        if '_ble_printer' in globals() and _ble_printer:
            _ble_printer._transport.close()
            _ble_printer = None
        return {'success': True, 'message': 'BLE disconnected'}
    except Exception as e:
        return {'success': False, 'message': f'Disconnect error: {str(e)}'}


def process_image_for_print(image_bytes, paper_width_mm=None):
    """
    Proses image (dari bytes) dengan smart crop dan resize.
    
    Args:
        image_bytes: Image dalam format bytes (PNG/JPG)
        paper_width_mm: Lebar kertas (opsional, pakai default jika None)
    
    Return:
        Dict dengan:
        - 'success': bool
        - 'processed_image_bytes': bytes image yang sudah diproses (PNG)
        - 'width': int (lebar pixel)
        - 'height': int (tinggi pixel)
        - 'error': str (jika ada error)
    """
    try:
        # Load image dari bytes
        img = Image.open(io.BytesIO(image_bytes))
        
        # Gunakan paper width yang diberikan atau default
        if paper_width_mm is None:
            paper_width_mm = protocol.load_paper_width_mm()
        
        # Smart crop dan resize
        processed_img = protocol.smart_crop_and_resize(img, paper_width_mm, error_tag="ANDROID")
        
        # Convert ke bytes (PNG format)
        output = io.BytesIO()
        processed_img.save(output, format='PNG')
        processed_bytes = output.getvalue()
        
        return {
            'success': True,
            'processed_image_bytes': processed_bytes,
            'width': processed_img.width,
            'height': processed_img.height,
            'error': None
        }
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {
            'success': False,
            'processed_image_bytes': None,
            'width': 0,
            'height': 0,
            'error': str(e)
        }


def print_image_via_usb(image_bytes, paper_width_mm=None):
    """
    Print image via USB.
    
    Args:
        image_bytes: Image bytes (PNG/JPG)
        paper_width_mm: Lebar kertas (opsional)
    
    Return:
        Dict: {'success': bool, 'message': str}
    """
    try:
        # Pastikan printer terhubung
        if '_usb_printer' not in globals() or _usb_printer is None:
            return {'success': False, 'message': 'Printer USB tidak terhubung. Panggil connect_usb() terlebih dahulu.'}
        
        printer = _usb_printer
        
        # Update paper width jika diberikan
        if paper_width_mm is not None:
            printer.set_paper_width(paper_width_mm, persist=True)
        
        # Proses image
        img = Image.open(io.BytesIO(image_bytes))
        processed_img = printer.smart_crop_and_resize(img)
        
        # Print (halaman 0 saja karena single image)
        printer.print_pages([0], {0: processed_img})
        
        return {'success': True, 'message': 'Print sukses via USB'}
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {'success': False, 'message': f'Print error: {str(e)}'}


def print_image_via_ble(image_bytes, paper_width_mm=None):
    """
    Print image via BLE.
    
    Args:
        image_bytes: Image bytes (PNG/JPG)
        paper_width_mm: Lebar kertas (opsional)
    
    Return:
        Dict: {'success': bool, 'message': str}
    """
    try:
        # Pastikan printer terhubung
        if '_ble_printer' not in globals() or _ble_printer is None:
            return {'success': False, 'message': 'Printer BLE tidak terhubung. Panggil connect_ble() terlebih dahulu.'}
        
        printer = _ble_printer
        
        # Update paper width jika diberikan
        if paper_width_mm is not None:
            printer.set_paper_width(paper_width_mm, persist=True)
        
        # Proses image
        img = Image.open(io.BytesIO(image_bytes))
        processed_img = printer.smart_crop_and_resize(img)
        
        # Print (halaman 0 saja karena single image)
        printer.print_pages([0], {0: processed_img})
        
        return {'success': True, 'message': 'Print sukses via BLE'}
        
    except Exception as e:
        import traceback
        traceback.print_exc()
        return {'success': False, 'message': f'Print error: {str(e)}'}


def check_usb_connection_status():
    """Cek apakah printer USB sedang terhubung."""
    if '_usb_printer' in globals() and _usb_printer and _usb_printer._transport:
        return {'connected': True}
    return {'connected': False}


def check_ble_connection_status():
    """Cek apakah printer BLE sedang terhubung."""
    if '_ble_printer' in globals() and _ble_printer and _ble_printer._transport:
        return {'connected': True}
    return {'connected': False}


# Global state untuk menyimpan instance printer
_usb_printer = None
_ble_printer = None
