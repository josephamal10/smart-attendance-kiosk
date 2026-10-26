@echo off
rem One-click start: starts the servers in their own (minimised) windows, waits until they
rem answer, then opens the kiosk app full screen. A server that crashes restarts by itself.
rem To stop everything: close the "Attendance" server windows, and close the app from a super
rem admin's account menu ("Close the kiosk app").
cd /d "%~dp0"
rem LAN=1 lets other devices on the office network use the web dashboard
rem (https://THIS-PC-IP:8443/app/) and download reports from the QR codes, over HTTPS with a
rem self-signed certificate made on this PC (browsers warn once). LAN=0 keeps it to this PC.
set LAN=1
set PY="%~dp0.venv\Scripts\python.exe"
set CHECK=powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/ -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"

%CHECK%
if not errorlevel 1 goto app

if "%LAN%"=="1" (
  %PY% scripts\make_cert.py
  set HTTPS_PORT=8443
  start "Attendance network server (HTTPS)" /min /d "%~dp0" cmd /k "set DISABLE_SCHEDULER=1&& scripts\serve.bat 0.0.0.0 8443 --ssl-keyfile certs\server.key --ssl-certfile certs\server.crt"
)
rem The kiosk app talks to this one, on this PC only: plain HTTP never leaves the machine.
rem It also runs the daily jobs (auto check-out, HR email, backups).
start "Attendance server" /min /d "%~dp0" cmd /k "scripts\serve.bat 127.0.0.1 8000"
echo Starting the server (first start takes ~10 seconds while models load)...
:wait
"%SystemRoot%\System32\timeout.exe" /t 2 /nobreak >nul
%CHECK%
if errorlevel 1 goto wait

:app
echo Server is running. Opening the kiosk...
start "" "%~dp0technerdz_app\build\windows\x64\runner\Release\technerdz_app.exe" --kiosk
