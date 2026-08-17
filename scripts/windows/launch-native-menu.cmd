@echo off
setlocal
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0launch-router.ps1" -NativeMenu -NoManager %*
if errorlevel 1 pause
