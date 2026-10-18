@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo   CriptoBot Institutional - Windows Launcher
echo ===================================================

cd /d "%~dp0"

REM 1. Check if backend API is running on port 8000
netstat -ano | findstr ":8000 " | findstr "LISTENING" >nul 2>&1
if %errorlevel% neq 0 (
    echo [*] Starting backend server in background...
    start /min "CriptoBot Backend" cmd /c ".venv\Scripts\python.exe -m uvicorn src.api.app:app --host 127.0.0.1 --port 8000"
    timeout /t 3 /nobreak >nul
) else (
    echo [v] Backend server is already running on port 8000.
)

REM 2. Check for Release executable first, fallback to Debug
set "EXE_PATH=criptobot_ui\build\windows\x64\runner\Release\criptobot_ui.exe"
set "EXE_DIR=criptobot_ui\build\windows\x64\runner\Release"

if not exist "!EXE_PATH!" (
    set "EXE_PATH=criptobot_ui\build\windows\x64\runner\Debug\criptobot_ui.exe"
    set "EXE_DIR=criptobot_ui\build\windows\x64\runner\Debug"
)

if not exist "!EXE_PATH!" (
    echo [!] Executable not found. Compiling Windows desktop application...
    cd criptobot_ui
    call flutter build windows
    cd ..
    set "EXE_PATH=criptobot_ui\build\windows\x64\runner\Release\criptobot_ui.exe"
    set "EXE_DIR=criptobot_ui\build\windows\x64\runner\Release"
)

echo [*] Launching CriptoBot Desktop Application...
pushd "!EXE_DIR!"
start "" "criptobot_ui.exe"
popd

echo [v] Application launched successfully.
