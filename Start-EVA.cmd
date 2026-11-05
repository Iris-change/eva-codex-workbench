@echo off
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0workbench\start.ps1" -DesktopBoot
if errorlevel 1 pause
