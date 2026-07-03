# Mock Bluetooth module untuk mengelabui ppa6 di Python 3.12+
class BluetoothSocket:
    def __init__(self, *args, **kwargs): pass
    def connect(self, *args): pass
    def close(self): pass

RFCOMM = 3

def discover_devices(*args, **kwargs):
    return []
