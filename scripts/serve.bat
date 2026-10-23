@echo off
rem Keeps one API server running: if it stops or crashes, it starts again after 5 seconds.
rem   scripts\serve.bat <host> <port> [more uvicorn options]
rem Close this window to stop it for good.
cd /d "%~dp0.."
:loop
"%~dp0..\.venv\Scripts\python.exe" -m uvicorn main:app --host %1 --port %2 %3 %4 %5 %6
echo.
echo The server stopped. Starting it again in 5 seconds - close this window to stop it.
"%SystemRoot%\System32\timeout.exe" /t 5 /nobreak >nul
goto loop
