@echo off
rem RagnaMusic Patch entfernen: Spotify wieder im Originalzustand
rem Mit -RemoveSpicetify wird auch das Programm Spicetify geloescht.
setlocal
title RagnaMusic Patch entfernen
powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%~dp0patch.ps1" -Uninstall %*
echo.
pause
