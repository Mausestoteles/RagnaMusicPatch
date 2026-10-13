@echo off
rem RagnaMusic Patch aktualisieren: neueste Version von GitHub holen und aufspielen.
rem Klappt auch von 0.1.0 aus. Ist Spotify nicht mehr gepatcht, laeuft der komplette Patch.
setlocal
title RagnaMusic Patch aktualisieren
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1" -Update %*
echo.
pause
