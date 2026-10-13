@echo off
rem One-click start: launches the server in its own window, waits until it answers,
rem then opens the kiosk app. Close the "TECHNERDZ server" window to stop the server.
cd /d "%~dp0"
set PY="%~dp0.venv\Scripts\python.exe"
set CHECK=powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/ -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"

%CHECK%
if not errorlevel 1 goto app

start "TECHNERDZ server" /d "%~dp0" cmd /k "%PY% -m uvicorn main:app"
echo Starting the server (first start takes ~10 seconds while models load)...
:wait
"%SystemRoot%\System32\timeout.exe" /t 2 /nobreak >nul
%CHECK%
if errorlevel 1 goto wait

:app
echo Server is running. Opening the app...
start "" "%~dp0technerdz_app\build\windows\x64\runner\Release\technerdz_app.exe"
