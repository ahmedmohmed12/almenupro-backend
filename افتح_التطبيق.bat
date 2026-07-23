@echo off
chcp 65001 >nul
cd /d "%~dp0"

set URL=http://127.0.0.1:5050/
if exist .port set /p PORT=<.port
if defined PORT set URL=http://127.0.0.1:%PORT%/

echo فتح %URL%
echo اذا لم يعمل، شغّل start.bat اولاً ثم جرّب مرة اخرى.
start "" "%URL%"
