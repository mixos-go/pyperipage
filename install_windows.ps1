<#
.SYNOPSIS
  Installer PeriPage A9 GUI untuk Windows.

.DESCRIPTION
  Skrip ini akan:
    1. Menyalin source code aplikasi ke  %LOCALAPPDATA%\PyPeriPageA9\app
    2. Membuat virtual environment Python + install semua dependency (pip)
    3. Membuat file .ico dari ikon aplikasi (kalau belum ada)
    4. Membuat shortcut di Desktop DAN Start Menu

.NOTES
  Cara pakai (PowerShell, TIDAK perlu run-as-administrator):
      cd ke folder source code aplikasi ini, lalu:
      powershell -ExecutionPolicy Bypass -File install_windows.ps1

  Untuk update aplikasi nanti, TIDAK perlu jalankan skrip ini lagi --
  cukup pakai tombol "🔄 Cek Pembaruan..." di dalam aplikasi.
#>

$ErrorActionPreference = "Stop"

$AppName    = "PeriPage A9 GUI"
$AppId      = "PyPeriPageA9"
$InstallDir = Join-Path $env:LOCALAPPDATA $AppId
$AppDir     = Join-Path $InstallDir "app"
$VenvDir    = Join-Path $InstallDir "venv"
$SourceDir  = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "==> Memasang $AppName ke $InstallDir"

# ------------------------------------------------------------------
# 1) Cek Python tersedia
# ------------------------------------------------------------------
$PythonCmd = $null
foreach ($cand in @("python", "py")) {
    try {
        $v = & $cand --version 2>&1
        if ($LASTEXITCODE -eq 0 -or $v -match "Python") {
            $PythonCmd = $cand
            break
        }
    } catch { }
}
if (-not $PythonCmd) {
    Write-Error "Python tidak ditemukan di PATH. Install Python 3 dulu dari https://python.org/downloads/ (centang 'Add python.exe to PATH' saat instalasi), lalu jalankan skrip ini lagi."
    exit 1
}
Write-Host "==> Menggunakan Python: $PythonCmd"

# ------------------------------------------------------------------
# 2) Salin source code ke folder instalasi (backup kalau sudah ada)
# ------------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

if (Test-Path $AppDir) {
    $backupName = "app_backup_" + (Get-Date -Format "yyyyMMdd_HHmmss")
    $backupPath = Join-Path $InstallDir $backupName
    Write-Host "==> Instalasi lama terdeteksi, membuat backup ke $backupPath"
    Move-Item -Path $AppDir -Destination $backupPath
}
New-Item -ItemType Directory -Force -Path $AppDir | Out-Null

Write-Host "==> Menyalin source code..."
# Salin HANYA berkas yang dipakai aplikasi desktop Tkinter ini -- SENGAJA
# tidak ikut menyalin folder flutter_app/, core_python/, library/, scripts/,
# .github/, atau dokumen markdown (bagian lain dari monorepo yang tidak
# dibutuhkan installer desktop ini).
$DesktopAppFiles = @(
    "peripage_gui.py",
    "peripage_logic.py",
    "peripage_protocol.py",
    "crop_editor.py",
    "app_updater.py",
    "transport_usb.py",
    "bluetooth.py",
    "requirements.txt",
    "VERSION",
    "peripage-icon.png"
)
foreach ($f in $DesktopAppFiles) {
    $srcFile = Join-Path $SourceDir $f
    if (Test-Path $srcFile) {
        Copy-Item -Path $srcFile -Destination $AppDir -Force
    } else {
        Write-Warning "Berkas '$f' tidak ditemukan di source, dilewati."
    }
}
$ToolsSrc = Join-Path $SourceDir "tools"
if (Test-Path $ToolsSrc) {
    Copy-Item -Path $ToolsSrc -Destination $AppDir -Recurse -Force
}
Write-Host "==> Source code tersalin ke $AppDir"

# ------------------------------------------------------------------
# 3) Virtualenv + dependency
# ------------------------------------------------------------------
if (-not (Test-Path $VenvDir)) {
    Write-Host "==> Membuat virtualenv Python di $VenvDir..."
    & $PythonCmd -m venv $VenvDir
}

$VenvPython  = Join-Path $VenvDir "Scripts\python.exe"
$VenvPyw     = Join-Path $VenvDir "Scripts\pythonw.exe"
$VenvPip     = Join-Path $VenvDir "Scripts\pip.exe"

Write-Host "==> Memasang dependency Python (pip)..."
& $VenvPython -m pip install --upgrade pip --quiet
& $VenvPip install -r (Join-Path $AppDir "requirements.txt")

Write-Host ""
Write-Host "PENTING: aplikasi ini butuh 'poppler' (utk membaca PDF)." -ForegroundColor Yellow
Write-Host "  Kalau belum terpasang: download poppler for Windows, ekstrak," -ForegroundColor Yellow
Write-Host "  lalu tambahkan folder 'bin'-nya ke PATH sistem." -ForegroundColor Yellow
Write-Host "  Lihat: https://github.com/oschwartz10612/poppler-windows/releases" -ForegroundColor Yellow
Write-Host ""

# ------------------------------------------------------------------
# 4) Siapkan ikon .ico (Windows shortcut butuh .ico, sumbernya .png)
# ------------------------------------------------------------------
$PngIcon = Join-Path $AppDir "peripage-icon.png"
$IcoIcon = Join-Path $AppDir "peripage-icon.ico"

if ((Test-Path $PngIcon) -and (-not (Test-Path $IcoIcon))) {
    Write-Host "==> Mengonversi ikon .png ke .ico..."
    $convertScript = @"
from PIL import Image
img = Image.open(r'$PngIcon').convert('RGBA')
img.save(r'$IcoIcon', format='ICO', sizes=[(16,16),(32,32),(48,48),(64,64),(128,128),(256,256)])
"@
    $tmpPy = Join-Path $env:TEMP "peripage_icon_convert.py"
    Set-Content -Path $tmpPy -Value $convertScript
    & $VenvPython $tmpPy
    Remove-Item $tmpPy -Force -ErrorAction SilentlyContinue
}
if (-not (Test-Path $IcoIcon)) {
    $IcoIcon = $VenvPyw  # fallback: pakai ikon default python kalau konversi gagal
}

# ------------------------------------------------------------------
# 5) Launcher .bat (biar gampang dipanggil / didebug manual dari cmd)
# ------------------------------------------------------------------
$LauncherBat = Join-Path $InstallDir "run_peripage_a9.bat"
@"
@echo off
"$VenvPyw" "$AppDir\peripage_gui.py"
"@ | Set-Content -Path $LauncherBat -Encoding ASCII

# ------------------------------------------------------------------
# 6) Shortcut Desktop + Start Menu
# ------------------------------------------------------------------
function New-AppShortcut {
    param([string]$ShortcutPath)
    $WshShell = New-Object -ComObject WScript.Shell
    $Shortcut = $WshShell.CreateShortcut($ShortcutPath)
    $Shortcut.TargetPath = $VenvPyw
    $Shortcut.Arguments  = "`"$AppDir\peripage_gui.py`""
    $Shortcut.WorkingDirectory = $AppDir
    $Shortcut.IconLocation = $IcoIcon
    $Shortcut.Description = $AppName
    $Shortcut.Save()
}

$DesktopPath = [Environment]::GetFolderPath("Desktop")
$DesktopShortcut = Join-Path $DesktopPath "$AppName.lnk"
New-AppShortcut -ShortcutPath $DesktopShortcut
Write-Host "==> Shortcut Desktop dibuat: $DesktopShortcut"

$StartMenuDir = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs"
$StartMenuShortcut = Join-Path $StartMenuDir "$AppName.lnk"
New-AppShortcut -ShortcutPath $StartMenuShortcut
Write-Host "==> Shortcut Start Menu dibuat: $StartMenuShortcut"

Write-Host ""
Write-Host "==================================================================" -ForegroundColor Green
Write-Host " Instalasi selesai!" -ForegroundColor Green
Write-Host " Buka '$AppName' dari Start Menu atau shortcut di Desktop." -ForegroundColor Green
Write-Host ""
Write-Host " Untuk update aplikasi nanti, TIDAK perlu jalankan skrip ini lagi --" -ForegroundColor Green
Write-Host " cukup pakai tombol '🔄 Cek Pembaruan...' di dalam aplikasi." -ForegroundColor Green
Write-Host "==================================================================" -ForegroundColor Green
