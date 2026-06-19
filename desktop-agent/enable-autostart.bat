@echo off
SET "AGENT_DIR=%~dp0"
SET "APP_NAME=RemoteConnectAgent"
SET "STARTUP_KEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run"

echo ============================================================
echo   RemoteConnect — Local AutoStart Installer
echo ============================================================
echo.
echo Target Folder: %AGENT_DIR%
echo.

:: 1. Verify files exist
if not exist "%AGENT_DIR%src\server.js" (
    echo [X] Error: Could not find src\server.js.
    echo     Please make sure this script is in the desktop-agent directory.
    pause
    exit /b 1
)

if not exist "%AGENT_DIR%run-silent.vbs" (
    echo [X] Error: Could not find run-silent.vbs.
    pause
    exit /b 1
)

:: 2. Register to Startup via Registry
SET "STARTUP_CMD=wscript.exe "%AGENT_DIR%run-silent.vbs""
reg add "%STARTUP_KEY%" /v "%APP_NAME%" /t REG_SZ /d "%STARTUP_CMD%" /f >nul

if %errorLevel% neq 0 (
    echo [X] Error: Failed to add registry key. Please try running as Administrator.
    pause
    exit /b 1
)
echo [+] Registered successfully in Windows Startup Registry.

:: 3. Terminate any existing instance and start in background
echo [+] Restarting Agent silently in background...
wmic process where "name='node.exe' and CommandLine like '%%src/server.js%%'" call terminate >nul 2>&1
wscript.exe "%AGENT_DIR%run-silent.vbs"

echo.
echo ============================================================
echo   Success! 
echo   - The agent is now running silently in the background.
echo   - It will start automatically when your PC turns on.
echo.
echo   To stop the server at any time, run: stop.bat
echo ============================================================
echo.
pause

