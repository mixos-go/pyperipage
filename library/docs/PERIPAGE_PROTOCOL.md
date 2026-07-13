# PeriPage Bluetooth Printer Protocol — Reverse Engineering Reference

Sumber: decompile `com.ileadtek.peripage` (app resmi PeriPage) via jadx 1.5.5 + analisis
native lib `libCode.so` (arm64-v8a, tidak di-strip). Semua nilai byte di bawah sudah
diverifikasi langsung dari bytecode/binary, bukan tebakan.

---

## 1. Transport Layer

**Bluetooth Classic SPP (RFCOMM)** — bukan BLE GATT, bukan USB (app ini tidak punya
permission/kode USB sama sekali).

```java
BluetoothDevice device = adapter.getRemoteDevice(macAddress);
BluetoothSocket socket = device.createRfcommSocketToServiceRecord(
    UUID.fromString("00001101-0000-1000-8000-00805F9B34FB") // SPP standar
);
socket.connect();

// Fallback kalau method di atas exception (device lama / driver bermasalah):
socket = (BluetoothSocket) device.getClass()
    .getMethod("createRfcommSocket", int.class)
    .invoke(device, 1); // paksa channel RFCOMM 1
socket.connect();
```

- Kirim data dalam chunk **maksimal 1024 byte** per `OutputStream.write()`, delay 1ms antar chunk kalau data > 1024 byte.
- Setelah connect sukses, app langsung start thread reader terus-menerus (polling `InputStream.available()`).

---

## 2. Command Packet Format

Pola umum command kontrol: **`0x10 0xFF <cmd> [params...]`**

Nilai hex di bawah sudah di-resolve dari konstanta Apache POI yang "menyamar" jadi byte
literal saat decompile (jadx artifact) — sudah saya verifikasi manual satu per satu.

| Command | Bytes (hex) | Keterangan |
|---|---|---|
| Get status | `10 FF 40` | minta status printer |
| Feed N dots | `10 FF 12 <hi> <lo>` | N = 16-bit big endian |
| Set density/darkness | `10 FF A0 00 <b3> <b2> <b1> <b0>` | int 32-bit |
| Pilih tipe kertas | `10 FF 10 03 <type>` | |
| Print mode select | `10 FF 10 00 <mode>` | |
| Set label gap threshold | `10 FF FE 45` | |
| Init/reset session | `10 FF 30 12` | dipanggil saat awal konek |
| Init session (variant b) | `10 FF 30 10` | |
| Query firmware/heartbeat | `1D 0C` | |
| Start print job marker | `10 FF A0 01` | |
| Cancel print (stop) | `10 FF FD 01` diikuti `1D 0C` lalu `10 FF FE 45` | urutan `U()`→`Q()`→`Y()` |
| Query battery | `10 FF 50 F1` | |
| Query battery (variant) | `10 FF 20 F1` | |
| Query firmware version | `10 FF 20 F2` | |
| Query SN | `10 FF 70` | |
| Query model | `10 FF 20 F0` | |
| Get status v2 | `10 FF 81 01` / `10 FF 81 00` | toggle |

### 2.1 Print bitmap — RAW mode (device lama: A8, PRT1, dll)
```
Header: 1D 76 30 <mode> <widthBytesLo> <widthBytesHi> <heightLo> <heightHi>
Body:   bitmap 1bpp, MSB-first per baris, pixel gelap = bit 1
```
`mode` = 0..3 (kepadatan cetak).

### 2.2 Print bitmap — COMPRESSED mode (A9, A9s, A9Pro+, Q9s, Q10s, A40, H2, P9, dll — lihat §5)
```
Header: 1F 00 <widthHi> <widthLo> <heightHi> <heightLo> <len3><len2><len1><len0>
Body:   zlib-compressed bitmap, 2-byte zlib header (CMF+FLG) DIBUANG sebelum kirim
```
`len` = panjang payload **setelah** header zlib dibuang (4 byte big-endian).

---

## 3. Kompresi Bitmap — `Code.code()` = zlib 1.2.3 standar

**Bukan algoritma proprietary.** Terverifikasi dari symbol table `libCode.so`:
```
T Java_com_example_sdk_Code_code / Java_com_example_sdk_Code_decode  (JNI wrapper)
T compress / compress2 / compressBound / uncompress                  (API publik zlib)
t compress_block / gen_codes ; R _dist_code / _length_code            (internal zlib)
string: "deflate 1.2.3 Copyright 1995-2005 Jean-loup Gailly"
string: "inflate 1.2.3 Copyright 1995-2005 Mark Adler"
```

Bukti tambahan dari caller Java (`u0.h.w()`):
```java
byte[] compressed = Code.code(rawBitmap1bpp);
// buang 2 byte pertama (zlib header CMF+FLG) sebelum kirim:
System.arraycopy(compressed, 2, packet, 10, compressed.length - 2);
```

### Implementasi Python (siap pakai, sudah diuji logikanya cocok)
```python
import zlib

def encode_bitmap_for_compressed_printers(bitmap_1bpp: bytes) -> bytes:
    compressed = zlib.compress(bitmap_1bpp)   # level default OK, decoder printer level-agnostic
    return compressed[2:]                      # strip 2-byte zlib header

def build_image_packet(width_dots: int, height: int, payload: bytes) -> bytes:
    length = len(payload)
    header = bytes([
        0x1F, 0x00,
        (width_dots >> 8) & 0xFF, width_dots & 0xFF,
        (height >> 8) & 0xFF,      height & 0xFF,
        (length >> 24) & 0xFF, (length >> 16) & 0xFF,
        (length >> 8) & 0xFF,   length & 0xFF,
    ])
    return header + payload
```

### Bit-packing bitmap (raw, sebelum kompresi) — dari `u0.h.t()`
```python
def pack_1bpp(pixels, width, height, threshold=190):
    """pixels: fungsi/array getpixel(x,y) -> (r,g,b). Gelap = bit 1."""
    row_bytes = (width + 7) // 8
    out = bytearray(row_bytes * height)
    for y in range(height):
        for x in range(width):
            r, g, b = pixels(x, y)
            if (r + g + b) / 3 < threshold:
                bit_index_in_row = x % 8
                byte_index = y * row_bytes + (x // 8)
                out[byte_index] |= (1 << (7 - bit_index_in_row))
    return bytes(out)
```

---

## 4. Response / Event dari Printer (arah printer → HP)

Dispatcher pertama cek byte pertama respons:

| Byte pertama | what (internal) | Event | Makna |
|---|---|---|---|
| `0xFF` + `bArr[1]==1` | 1 | onOutPaper | kertas habis |
| `0xFF` + `bArr[1]==2` | 2 | onOpenCover | penutup terbuka |
| `0xFF` + `bArr[1]==3` | 3 | onOverHeat | overheat |
| `0xFF` + `bArr[1]==4` | 4 | onLowBattery | baterai lemah (set battery=9%) |
| `0xFF` + `bArr[1]==5` | 5 | onCloseCover | penutup tertutup |
| `0xFF` + `bArr[1]==6` | 18 | onPrinterLowMileageAuto | mileage/umur pakai cetak rendah |
| `0xFE` | 6 | onPaperError | lihat tabel jenis kertas §4.1 |
| `0xFD` + `bArr[1]==3` | 16 | (status ok, no-op di app) | |
| `0xFD` + `bArr[1]==4` | 17 | (status ok, no-op di app) | |
| `0xFD` + lainnya | 7 | onStartOrStopSend | `bArr[1]==1`→abort command diterima; `bArr[1]==2`→lanjut/start command |
| `0xFC` | 8 | (no-op di app) | |
| lainnya | 0 | generic passthrough | dipakai utk data ACK saat handshake awal |

### 4.1 Jenis kertas (`onPaperError`, prefix `0xFE`, byte kedua)
| `bArr[1]` | Jenis kertas (asli, dari komentar sumber) |
|---|---|
| 1 | 折叠黑标纸 — kertas lipat dengan black-mark |
| 2 | 连续卷筒纸 — kertas roll kontinu |
| 3 | 不干胶缝隙纸 — label adhesive dengan gap |
| 4 | 打孔纸 — kertas berlubang (die-cut) |

---

## 5. Deteksi Model & Konfigurasi Lebar Cetak

Deteksi dilakukan dari **nama Bluetooth device** (bukan dari query command khusus), lihat `z4/f.java`.

### 5.1 Model yang pakai protokol COMPRESSED (§2.2)
```
PeriPage_A8_*, PeriPage_A8+, PRT1_*, PeriPage_A9, PeriPage_A9+, PeriPage_A9Pro+,
PeriPage_A9s, PeriPage_Q9s, PeriPage_A9sMAX, PeriPage_A9MAX, PeriPage_Q9Pro+,
PeriPage_Q10s, PeriPage_A40, PeriPage_H2, PeriPage_H2+, PeriPage_P40, PeriPage_P9,
SQAI_PP_G10, SQAI_PP_G40, PeriPage_A3X, PeriPage_A3X+, PeriPage_A40+,
PeriPage_A40Pro+, PeriPage_A40Pro, PeriPage_Y200, PeriPage_Y200+, PPG_P40W*, PPG_P40*
```
Semua model lain (default) → protokol RAW (§2.1).

### 5.2 Lebar cetak per model (dots) — contoh yang relevan
| Nama device | Lebar (dots) | Catatan |
|---|---|---|
| `PeriPage_A9` | 400 atau 576 | tergantung flag `isA9576` (query firmware variant) |
| `PPG_A9_*` / `PPG_A9s_*` | sama seperti A9 | |
| `PeriPage_A9s` | 600 atau 864 | |
| `PeriPage_A9+` | 600 atau 864 | |
| `PeriPage_A9Pro+` | 600 atau 864 | |
| `PeriPage_Q9Pro+` | 600 atau 864 | |
| `PeriPage_Q9s` | 600 atau 864 | |
| `PeriPage_Q10s` | 600 / 864 / 1236 | |
| `PeriPage_A9sMAX` / `A9MAX` | 600 / 864 / 1236 | |
| `PeriPage_A2` / varian PPG_A2/PC20/PC21 | 384 | |

`isA9576` (0/1/2) adalah flag internal yang menentukan varian firmware/resolusi —
kemungkinan didapat dari respons query, bukan dari nama device. Field ini disimpan
di `DevInfoEntity` bersama battery, version, sn, printerModel, printMileage, dll.

---

## 5a. Source Asli — `z4/f.java` method `Y3(DevInfoEntity)`

Method Java asli (hasil decompile jadx, nama field obfuscated dipertahankan apa
adanya) yang jadi sumber tabel §5.2. `f57080p` = kode internal printer type,
`f57081q` = lebar cetak dalam **dots** (float), `f57082r` = offset/margin
(satuan berbeda-beda tergantung model).

```java
private void Y3(DevInfoEntity devInfoEntity) {
    if (devInfoEntity == null) {
        return;
    }
    String name = devInfoEntity.getName();
    if (name.startsWith("PeriPage_A3_")) {
        this.f57080p = 6;
        this.f57081q = 576.0f;
        this.f57082r = 48;
    } else if (name.equalsIgnoreCase("PeriPage_A3X") || name.startsWith("PPG_P30_")) {
        this.f57080p = devInfoEntity.isA9576() == 0 ? 38 : 37;
        this.f57081q = devInfoEntity.isA9576() == 0 ? 400.0f : 576.0f;
        this.f57082r = 80;
    } else if (name.equalsIgnoreCase("PeriPage_A3X+") || name.startsWith("PPG_P30+_")) {
        this.f57080p = devInfoEntity.isA9576() == 0 ? 40 : 39;
        this.f57081q = devInfoEntity.isA9576() == 0 ? 600.0f : 864.0f;
        this.f57082r = 120;
    } else {
        if (z0(name)) {
            // --- Grup printer lebar "A4-like" (PPG_A40W / P40 / P50 / P80 dst) ---
            int iF = PreferencesUtils.f("a4DeviceType", 2);
            int iF2 = PreferencesUtils.f("a4PaperTypePopup", iF == 2 ? 0 : 3);
            if (iF != 0 || iF2 == 0) {
                int iF3 = PreferencesUtils.f("a4BigPaperTypePopup", 1);
                if ("PeriPage_A40+".equals(name) || "PeriPage_A40Pro+".equals(name) || "PeriPage_Y200+".equals(name)
                        || name.startsWith("PPG_A40+") || name.startsWith("PPG_P40W+") || name.startsWith("PPG_P40+")
                        || name.startsWith("PPG_P4O+") || name.startsWith("PPG_A4O_UHD") || name.startsWith("PPG_P50+")
                        || name.startsWith("PPG_P80+")) {
                    this.f57080p = 36;
                    if (iF3 == 0) {
                        this.f57081q = 2454.4f;
                    } else if (iF3 == 4) {
                        this.f57081q = 1770.0f;
                    } else if (iF3 == 5) {
                        this.f57081q = 2120.0f;
                    } else {
                        this.f57081q = 2496.0f;
                    }
                    this.f57082r = 24;
                } else {
                    this.f57080p = 35;
                    if (iF3 == 0) {
                        boolean zA = PreferencesUtils.a("KEY_NAME_A4O_AND_KOREA_LANGUAGE_BLACK_PAPER", false);
                        if (CommonUtil.T().x0() && zA) {
                            this.f57081q = 1680.0f;
                        } else {
                            this.f57081q = D2(name) ? 1664.0f : 1646.0f;
                        }
                    } else if (iF3 == 4) {
                        this.f57081q = 1165.0f;
                    } else if (iF3 == 5) {
                        this.f57081q = 1383.0f;
                    } else {
                        this.f57081q = 1664.0f;
                    }
                    this.f57082r = 16;
                }
            } else if (name.startsWith("PPG_A4O_UHD")) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 24 : devInfoEntity.isA9576() == 2 ? 25 : 26;
                this.f57081q = devInfoEntity.isA9576() == 0 ? 566.4f : devInfoEntity.isA9576() == 2 ? 1203.6f : 849.6f;
                this.f57082r = 12;
            } else if (B2()) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 27 : devInfoEntity.isA9576() == 2 ? 28 : 26;
                if (devInfoEntity.isA9576() == 0) { f = 384.0f; } else if (devInfoEntity.isA9576() == 2) { f = 816.0f; }
                this.f57081q = f;
                this.f57082r = x2() ? 12 : 8;
            } else if ("PeriPage_A40+".equals(name) || "PeriPage_A40Pro+".equals(name) || "PeriPage_Y200+".equals(name)
                    || name.startsWith("PPG_A40+") || name.startsWith("PPG_P40W+") || name.startsWith("PPG_P40+") || name.startsWith("PPG_P4O+")) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 24 : devInfoEntity.isA9576() == 2 ? 25 : 26;
                this.f57081q = devInfoEntity.isA9576() != 0 ? (devInfoEntity.isA9576() == 2 ? 1224.0f : 864.0f) : 576.0f;
                this.f57082r = 120;
            } else if (!p1()) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 27 : devInfoEntity.isA9576() == 2 ? 28 : 26;
                if (devInfoEntity.isA9576() == 0) { f = 384.0f; } else if (devInfoEntity.isA9576() == 2) { f = 816.0f; }
                this.f57081q = f;
                this.f57082r = 80;
            } else if (name.startsWith("PPG_P80+") || name.startsWith("PPG_P50+")) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 24 : devInfoEntity.isA9576() == 2 ? 25 : 23;
                this.f57081q = devInfoEntity.isA9576() != 0 ? (devInfoEntity.isA9576() == 2 ? 1224.0f : 864.0f) : 576.0f;
                this.f57082r = 24;
            } else {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 27 : devInfoEntity.isA9576() == 2 ? 28 : 26;
                if (devInfoEntity.isA9576() == 0) { f = 384.0f; } else if (devInfoEntity.isA9576() == 2) { f = 816.0f; }
                this.f57081q = f;
                this.f57082r = 16;
            }
        } else if (T3(name)) {
            // --- Grup P91/P92/P93 ---
            if (name.startsWith("PPG_P91s+_") || name.startsWith("PPG_P91+") || name.startsWith("PPG_P92+") || name.startsWith("PPG_P93+")) {
                this.f57080p = 36;
                this.f57081q = 2496.0f;
                this.f57082r = 24;
            } else {
                int iH = CommonUtil.T().H();
                if (M3() && iH == 2) {
                    this.f57080p = devInfoEntity.isA9576() == 0 ? 27 : devInfoEntity.isA9576() == 2 ? 28 : 26;
                    if (devInfoEntity.isA9576() == 0) { f = 384.0f; } else if (devInfoEntity.isA9576() == 2) { f = 816.0f; }
                    this.f57081q = f;
                    this.f57082r = 80;
                } else {
                    this.f57080p = 35;
                    this.f57081q = 1646.0f;
                    this.f57082r = 16;
                }
            }
        } else if (name.equals("PeriPage_Q7Pro")) {
            this.f57080p = 18; this.f57081q = 576.0f; this.f57082r = 96;
        } else if (name.equals("PeriPage_Q7") || name.startsWith("PPG_P20")) {
            this.f57080p = 19; this.f57081q = 384.0f; this.f57082r = 64;
        } else if (name.startsWith("PeriPage_A8_")) {
            this.f57080p = 4; this.f57081q = 384.0f; this.f57082r = 56;
        } else if (name.startsWith("PeriPage_A8+") || name.startsWith("PeriPage_A8Plus")) {
            this.f57080p = 5; this.f57081q = 576.0f; this.f57082r = 84;
        } else {
            int i10 = 108;
            if (name.equals("PeriPage_Q10s")) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 31 : devInfoEntity.isA9576() == 2 ? 32 : 30;
                this.f57081q = devInfoEntity.isA9576() == 0 ? 600.0f : devInfoEntity.isA9576() == 2 ? 1236.0f : 864.0f;
                this.f57082r = 108;
            } else if (name.equals("PeriPage_A9sMax") || name.equals("PeriPage_A9sMAX")) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 24 : devInfoEntity.isA9576() == 2 ? 25 : 26;
                this.f57081q = devInfoEntity.isA9576() == 0 ? 600.0f : devInfoEntity.isA9576() == 2 ? 1236.0f : 864.0f;
                this.f57082r = 120;
            } else if (l1(name)) {
                this.f57080p = 28; this.f57081q = 824.0f; this.f57082r = 64;
            } else if (name.equals("PeriPage_A9Max") || name.equals("PeriPage_A9MAX") || name.equals("SQAI_PP_G10")
                    || name.startsWith("PPG_A9sMAX_UHD") || name.startsWith("PPG_A9sMAX_UD") || name.startsWith("PPG_A9sMAX_HD")) {
                this.f57080p = devInfoEntity.isA9576() == 0 ? 27 : devInfoEntity.isA9576() == 2 ? 28 : 26;
                if (devInfoEntity.isA9576() == 0) { f = 400.0f; } else if (devInfoEntity.isA9576() == 2) { f = 824.0f; }
                this.f57081q = f;
                this.f57082r = 80;
            } else {
                if (name.startsWith("PPG_A9s_UHD") || name.startsWith("PPG_A9s_UD") || name.startsWith("PPG_A9s_HD")) {
                    this.f57080p = devInfoEntity.isA9576() != 1 ? 10 : 9;
                    this.f57081q = devInfoEntity.isA9576() != 1 ? 400.0f : 576.0f;
                    this.f57082r = 108;
                } else if (name.startsWith("PeriPage_A9+")) {
                    this.f57080p = devInfoEntity.isA9576() != 1 ? 10 : 9;
                    this.f57081q = devInfoEntity.isA9576() == 1 ? 864.0f : 600.0f;
                    this.f57082r = 108;
                } else if (name.equals("PeriPage_A9s")) {
                    this.f57080p = devInfoEntity.isA9576() == 1 ? 14 : 15;
                    this.f57081q = devInfoEntity.isA9576() == 1 ? 864.0f : 600.0f;
                    this.f57082r = 108;
                } else if (name.equals("PeriPage_Q9Pro+")) {
                    this.f57080p = devInfoEntity.isA9576() == 1 ? 33 : 34;
                    this.f57081q = devInfoEntity.isA9576() == 1 ? 864.0f : 600.0f;
                    this.f57082r = 108;
                } else if (name.equals("PeriPage_Q9s")) {
                    this.f57080p = devInfoEntity.isA9576() == 1 ? 16 : 17;
                    this.f57081q = devInfoEntity.isA9576() == 1 ? 864.0f : 600.0f;
                    this.f57082r = 108;
                } else if (name.equals("PeriPage_A9Pro+")) {
                    this.f57080p = devInfoEntity.isA9576() == 1 ? 11 : 12;
                    this.f57081q = devInfoEntity.isA9576() == 1 ? 864.0f : 600.0f;
                    this.f57082r = 108;
                } else if (name.equals("PeriPage_A9") || name.startsWith("PPG_A9_") || name.startsWith("PPG_A9s_")) {
                    this.f57080p = devInfoEntity.isA9576() == 1 ? 7 : 8;
                    this.f57081q = devInfoEntity.isA9576() != 1 ? 400.0f : 576.0f;
                    if (!name.startsWith("PPG_A9_") && !name.startsWith("PPG_A9s_")) {
                        i10 = 72;
                    }
                    this.f57082r = i10;
                } else if (name.equalsIgnoreCase("PeriPage_A2") || name.startsWith("PPG_A2+") || name.startsWith("PPG_A2")
                        || name.startsWith("PPG_A2Neo") || name.startsWith("PPG_P21_") || name.startsWith("PPG_PC20_")
                        || name.startsWith("PPG_PC21_") || name.startsWith("PPG_PC20Pro_") || name.startsWith("PPG_PC21Pro_")) {
                    this.f57080p = 0;
                    this.f57081q = 384.0f;
                    this.f57082r = (name.startsWith("PPG_P21_") ? 12 : 9) * 8;
                } else if (name.startsWith("PPG_P22")) {
                    if (name.startsWith("PPG_P22+")) {
                        this.f57080p = 0; this.f57081q = 384.0f; this.f57082r = 144;
                    } else {
                        this.f57080p = 0; this.f57081q = 384.0f; this.f57082r = 72;
                    }
                } else if (name.equalsIgnoreCase("PeriPage_A2+") || name.startsWith("PPG_PC20+_") || name.startsWith("PPG_PC21+_")
                        || name.startsWith("PPG_PC20Pro+_") || name.startsWith("PPG_PC21Pro+_") || name.equalsIgnoreCase("PeriPage_H2+")
                        || name.startsWith("PPG_P21+_")) {
                    this.f57080p = 2; this.f57081q = 576.0f; this.f57082r = 108;
                } else if (name.startsWith("PRT1_")) {
                    this.f57080p = 13; this.f57081q = 576.0f; this.f57082r = 84;
                } else if (name.startsWith("Alison")) {
                    this.f57080p = 0; this.f57081q = 384.0f; this.f57082r = 64;
                } else if (name.startsWith("PeriPage+")) {
                    this.f57080p = 2; this.f57081q = 576.0f; this.f57082r = 96;
                } else if (name.startsWith("PeriPage_C6+")) {
                    this.f57080p = 29; this.f57081q = 576.0f; this.f57082r = 96;
                } else if (name.equals("PeriPage_C6")) {
                    this.f57080p = 20; this.f57081q = 384.0f; this.f57082r = 64;
                } else if (name.equals("PeriPage_L1Pro") || name.equals("PeriPage_L1Plus")) {
                    this.f57080p = 21; this.f57081q = 96.0f; this.f57082r = 84;
                } else if (name.startsWith("PeriPage_L1_")) {
                    this.f57080p = 22; this.f57081q = 96.0f; this.f57082r = 84;
                } else if (name.startsWith("PPG_P10") || name.startsWith("PPG_P11")) {
                    this.f57080p = 22; this.f57081q = 96.0f; this.f57082r = 72;
                } else if (z3(name)) {
                    this.f57080p = devInfoEntity.isA9576() == 0 ? 24 : devInfoEntity.isA9576() == 2 ? 25 : 26;
                    this.f57081q = 840.0f;
                    this.f57082r = 72;
                } else if (r3(name)) {
                    this.f57080p = 0;
                    this.f57081q = 384.0f;
                    this.f57082r = (u3(name) ? 3 : 9) * 8;
                } else if (name.contains("+")) {
                    this.f57080p = 2; this.f57081q = 576.0f; this.f57082r = 96;
                } else if (H2(name)) {
                    this.f57080p = 2; this.f57081q = 384.0f; this.f57082r = 128;
                } else {
                    this.f57080p = 0; this.f57081q = 384.0f; this.f57082r = 64;
                }
            }
        }
    }
}
```

> **Catatan:** helper method yang dipanggil di dalamnya (`z0()`, `T3()`, `B2()`,
> `x2()`, `l1()`, `z3()`, `r3()`, `u3()`, `H2()`, `D2()`, `M3()`, `p1()`) masing-masing
> berisi daftar `startsWith`/`equals` nama device tambahan, tersebar di `z4/f.java`
> dan `z4/b.java`. Kalau Sj menemukan device yang jatuh ke salah satu cabang ini,
> kasih tau nama device-nya — saya trace method spesifik itu untuk detail lengkap.

## 5b. Source Asli — `u0/h.java` method `l()` (pemilih RAW vs COMPRESSED)

```java
public void l(Bitmap bitmap, int i10) {
    if (this.f51126i.contains("PeriPage_A8_") || this.f51126i.contains("PeriPage_A8+")
            || this.f51126i.contains("PRT1_") || this.f51126i.equals("PeriPage_A9")
            || this.f51126i.equals("PeriPage_A9+") || this.f51126i.equals("PeriPage_A9Pro+")
            || this.f51126i.equals("PeriPage_A9s") || this.f51126i.equals("PeriPage_Q9s")
            || this.f51126i.equals("PeriPage_A9sMAX") || this.f51126i.equals("PeriPage_A9MAX")
            || this.f51126i.equals("PeriPage_Q9Pro+") || this.f51126i.equals("PeriPage_Q10s")
            || this.f51126i.equals("PeriPage_A40") || this.f51126i.equals("PeriPage_H2")
            || this.f51126i.equals("PeriPage_H2+") || this.f51126i.equals("PeriPage_P40")
            || this.f51126i.equals("PeriPage_P9") || this.f51126i.equals("SQAI_PP_G10")
            || this.f51126i.equals("SQAI_PP_G40") || this.f51126i.equals("PeriPage_A3X")
            || this.f51126i.equals("PeriPage_A3X+") || this.f51126i.equals("PeriPage_A40+")
            || this.f51126i.equals("PeriPage_A40Pro+") || this.f51126i.equals("PeriPage_A40Pro")
            || this.f51126i.equals("PeriPage_Y200") || this.f51126i.equals("PeriPage_Y200+")
            || this.f51126i.contains("PPG_P40W") || this.f51126i.contains("PPG_P40")) {
        w(bitmap, i10);   // COMPRESSED (zlib) — lihat §2.2 & §3
    } else {
        C(bitmap, i10);   // RAW 1bpp — lihat §2.1
    }
}
```

---

## 6. Parser Response Query (Battery / Version / SN / MAC / Model / UserKey)

Ditemukan di `z4/a.java` — class `a extends u0.d`, method `v(byte[] bArr)`
(1780-2436), dispatcher `switch` berbasis enum `OperteType` (lookup table di
inner class `n`, sudah saya map manual ke nama enum aslinya).

### 6.1 Helper decode dasar
```java
// H0(byte[]) — decode string generic (dipakai utk BTNAME/VER/MODEL/SN/INFO)
private String H0(byte[] bArr) {
    return new String(bArr, "GB2312");  // GB2312, tapi ASCII-compatible untuk versi/model/SN standar
}

// CommonUtil.d(byte[]) — decode MAC address
public String macFromBytes(byte[] bArr) {
    StringBuilder sb = new StringBuilder();
    for (int i = 0; i < bArr.length; i++) {
        sb.append(String.format("%02X", bArr[i] & 0xFF));
        if (i != bArr.length - 1) sb.append(":");
    }
    return sb.toString(); // format "AA:BB:CC:DD:EE:FF"
}
```

### 6.2 Tabel query → response parsing (per `OperteType`)

| Query (`OperteType`) | Cara parse response | Catatan |
|---|---|---|
| `OPETATE_BTNAME` | `H0(bArr)` → string apa adanya | nama BT device |
| `OPETATE_PRINTERVER` | `H0(bArr)`, strip `"OK"`, kalau ada `"_"` ambil bagian sebelum `_` | contoh: `"V1.31_xxx"` → `"V1.31"` |
| `OPETATE_BTMAC` | `macFromBytes(bArr)` | format `AA:BB:CC:DD:EE:FF` |
| `OPETATE_BTVER` | `H0(bArr)`, strip `"OK"`/`"ok"` | versi modul bluetooth (beda dari versi firmware printer) |
| `OPETATE_PRINTERMODEL` | `H0(bArr)` apa adanya | string model |
| `OPETATE_PRINTERSN` | `H0(bArr)`; kalau hasilnya persis `"OK"` → berarti device tidak punya SN (fallback ke method lain `G0()`) | |
| `OPETATE_BATVOL` | **`bArr[1]`** langsung sebagai int (response 2 byte, byte kedua = persentase 0-100) | `int battery = (int) bArr[1];` |
| `OPETATE_PRINTERINFO` | Response bisa datang multi-packet, di-*append* ke buffer sampai ketemu **4 karakter `\|`** (delimiter), lalu diserahkan sebagai satu string panjang `"field1\|field2\|field3\|field4\|..."` | field breakdown belum saya trace (butuh sample data asli dari printer untuk cocokkan urutan field) |
| `OPETATE_GET_USERKEY` | `H0(bArr)`, strip `\r\n` | user key/license string |
| `OPETATE_GET_LABEL_HEIGHT` | `((bArr[0]&0xFF)<<8) | (bArr[1]&0xFF)` (16-bit, dipaksa ke int 32-bit dgn 2 byte leading zero) | tinggi label dalam dots |

### 6.3 Deteksi flag `isA9576` — bukan dari query khusus!
Ditemukan di `default` branch dari switch yang sama — flag ini disisipkan di
**byte terakhir dari response print-status** (bukan hasil query terpisah):
```java
// bArr[terakhir] == 17  -> isA9576 = 1  (varian "576-line")
// bArr[terakhir] == 18  -> isA9576 = 0  (varian default/non-576)
// dicek juga: bArr[0]==0x59('Y'), bArr[1]==0xFF sebagai pola frame pembuka
int isA9576 = (bArr[bArr.length - 1] == 17) ? 1 : 0;
```

### 6.4 Ack sederhana ("OK"/"ER")
Banyak command kontrol simpel (set density, set paper type, dst) cukup dibalas
2 byte ASCII literal:
```
'O','K' (0x4F, 0x4B) → sukses
'E','R' (0x45, 0x52) → error
```

---

## 7. Yang Masih Bisa Digali Lebih Lanjut (opsional)

1. Breakdown persis field-field di dalam string `OPETATE_PRINTERINFO` (dipisah `|`)
   — perlu sample byte asli dari printer fisik untuk cocokkan urutan field (battery,
   version, sn, dst kemungkinan digabung di sini, tapi urutannya belum pasti tanpa data nyata).
2. Command exact untuk `choosePaperType`, print mode 0-3, density level — byte-nya
   sudah ada di §2, tapi belum saya cocokkan ke label UI (misal "density level 3" di
   app = command byte berapa persisnya).
3. BLE (GATT) tidak ditemukan dipakai untuk *print* sama sekali di app ini — hanya
   untuk OTA firmware update pada sebagian model (`com.example.sdk.BtUpdate`). Kalau
   printer Sj ternyata konek via BLE bukan Classic BT, kemungkinan itu app/versi lain
   — perlu dikonfirmasi langsung ke device Sj (cek muncul di
   `BluetoothAdapter.getBondedDevices()` sebagai Classic, atau perlu BLE scan).

---

## 7. Disclaimer

Dokumen ini hasil reverse engineering untuk keperluan **interoperabilitas** (membangun
software sendiri yang bisa bicara dengan hardware PeriPage yang sudah dibeli/dimiliki).
Semua nilai sudah diverifikasi ulang dari bytecode/binary asli, bukan hasil tebakan —
tapi tetap disarankan untuk diuji langsung ke unit fisik sebelum dipakai produksi,
terutama untuk command yang belum ada catatan "sudah dites" (§6).
