@echo off
chcp 65001 >nul
cd /d "%~dp0"
title Delivery App Server

if not exist ".venv\Scripts\python.exe" (
  echo [1/3] Creating virtual environment...
  py -3 -m venv .venv
  if errorlevel 1 (
    echo Failed. Install Python from python.org then retry.
    pause
    exit /b 1
  )
)

echo [2/3] Installing packages...
.venv\Scripts\python.exe -m pip install -q -r requirements.txt
if errorlevel 1 (
  echo pip install failed.
  pause
  exit /b 1
)

if not exist ".env" (
  echo Creating .env from template...
  copy /Y .env.example .env >nul
)

findstr /R /C:"^OPENAI_API_KEY=sk-" .env >nul 2>&1
if errorlevel 1 (
  echo.
  echo  *** تنبيه: مفتاح OpenAI غير مضبوط ***
  echo  افتح ملف .env وضع سطراً مثل:
  echo  OPENAI_API_KEY=sk-proj-xxxxxxxx
  echo  ثم احفظ الملف وأعد تشغيل start.bat
  echo  رفع الفواتير لن يعمل حتى تضيف المفتاح.
  echo.
)

echo [3/3] Starting server...
.venv\Scripts\python.exe server.py
pause
