@echo off
rem RagnaMusic Patch starten: SpotX + Spicetify + RagnaMusic-Theme
rem Weitere Optionen werden durchgereicht, z. B.:  "Start Patch.bat" -Scheme light
setlocal
title RagnaMusic Patch
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1" %*
echo.
pause
