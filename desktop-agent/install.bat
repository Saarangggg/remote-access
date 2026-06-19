@echo off
REM RemoteConnect Desktop Agent — Windows Startup Installer
REM Run this script as Administrator to register the agent as a startup program

SET AGENT_DIR=%~dp0
SET NODE_PATH=node
SET SCRIPT_PATH=%AGENT_DIR%src\server.js
SET STARTUP_KEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run
SET APP_NAME=RemoteConnectAgent

REM Check if node is available
where node >nul 2>nul
IF ERRORLEVEL 1 (
    echo ERROR: Node.js not found. Please install Node.js from https://nodejs.org
    pause
    exit /b 1
)

REM Install dependencies if needed
IF NOT EXIST "%AGENT_DIR%node_modules" (
    echo Installing dependencies...
    cd /d "%AGENT_DIR%"
    npm install
    IF ERRORLEVEL 1 (
        echo ERROR: Failed to install dependencies
        pause
        exit /b 1
    )
)

REM Copy .env.example to .env if not exists
IF NOT EXIST "%AGENT_DIR%.env" (
    copy "%AGENT_DIR%.env.example" "%AGENT_DIR%.env"
    echo Created .env from template. Edit it to customize settings.
)

REM Register in Windows startup via registry
SET STARTUP_CMD=wscript.exe "%AGENT_DIR%run-silent.vbs"
REG ADD "%STARTUP_KEY%" /V "%APP_NAME%" /T REG_SZ /D "%STARTUP_CMD%" /F

IF ERRORLEVEL 1 (
    echo ERROR: Failed to register startup entry. Try running as Administrator.
    pause
    exit /b 1
)

echo.
echo ============================================================
echo  RemoteConnect Agent installed successfully!
echo  The agent will start automatically with Windows.
echo.
echo  To start now, run: node "%SCRIPT_PATH%"
echo  To uninstall startup, run: uninstall.bat
echo ============================================================
echo.
pause
