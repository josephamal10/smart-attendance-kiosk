@echo off
rem Builds the admin web dashboard into technerdz_app\build\web_admin.
rem The API server serves it at /app/ (restart the server after building).
cd /d "%~dp0..\technerdz_app"
set FLUTTER=C:\flutter\flutter\bin\flutter.bat
if not exist "%FLUTTER%" set FLUTTER=flutter
call "%FLUTTER%" build web --release --base-href /app/ -o build\web_admin --no-web-resources-cdn --no-wasm-dry-run
