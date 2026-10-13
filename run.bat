@echo off
rem One-click start: launches the server in its own window, waits until it answers,
rem then opens the kiosk app. Close the "TECHNERDZ server" window to stop the server.
cd /d "%~dp0"

powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/ -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"
if not errorlevel 1 goto app

start "TECHNERDZ server" cmd /k ".venv\Scripts\python -m uvicorn main:app"
echo Starting the server (first start takes ~10 seconds while models load)...
:wait
timeout /t 2 /nobreak >nul
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8000/ -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 goto wait

:app
echo Server is running. Opening the app...
start "" "technerdz_app\build\windows\x64\runner\Release\technerdz_app.exe"
