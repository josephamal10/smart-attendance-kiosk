@echo off
rem One-click DEMO with made-up data (separate demo.db; your real data is never touched).
rem Opens the web dashboard in your browser: the sign-in page lists the demo accounts and
rem lets you open any employee's own dashboard without a face scan.
cd /d "%~dp0"
set PY="%~dp0.venv\Scripts\python.exe"
if not exist "technerdz_app\build\web_admin\index.html" (
  echo Building the web dashboard once ^(takes about a minute^)...
  call scripts\build_web.bat
)
start "Attendance DEMO server" /min /d "%~dp0" cmd /k "%PY% scripts\run_demo.py"
echo Starting the demo (about 10 seconds)...
:wait
"%SystemRoot%\System32\timeout.exe" /t 2 /nobreak >nul
powershell -NoProfile -Command "try { Invoke-WebRequest -UseBasicParsing http://127.0.0.1:8001/ -TimeoutSec 2 | Out-Null; exit 0 } catch { exit 1 }"
if errorlevel 1 goto wait
start "" "http://127.0.0.1:8001/app/"
