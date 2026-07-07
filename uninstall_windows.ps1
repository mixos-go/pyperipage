<#
.SYNOPSIS
  Uninstaller PeriPage A9 GUI untuk Windows.
.DESCRIPTION
  Menghapus folder instalasi + shortcut Desktop & Start Menu.
  Pengaturan pengguna TIDAK dihapus otomatis -- lihat pesan di akhir.
#>

$AppName    = "PeriPage A9 GUI"
$AppId      = "PyPeriPageA9"
$InstallDir = Join-Path $env:LOCALAPPDATA $AppId
$DesktopShortcut = Join-Path ([Environment]::GetFolderPath("Desktop")) "$AppName.lnk"
$StartMenuShortcut = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\$AppName.lnk"

Write-Host "Ini akan menghapus:"
Write-Host "  - $InstallDir"
Write-Host "  - $DesktopShortcut"
Write-Host "  - $StartMenuShortcut"
$answer = Read-Host "Lanjutkan? [y/N]"
if ($answer -notmatch '^[Yy]') {
    Write-Host "Dibatalkan."
    exit 0
}

Remove-Item -Path $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path $DesktopShortcut -Force -ErrorAction SilentlyContinue
Remove-Item -Path $StartMenuShortcut -Force -ErrorAction SilentlyContinue

Write-Host "Selesai. Aplikasi sudah dihapus."
Write-Host "Pengaturan pengguna masih ada di %USERPROFILE%\.pyperipage"
Write-Host "Hapus manual folder itu juga kalau mau benar-benar bersih."
