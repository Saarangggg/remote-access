@echo off
REM RemoteConnect Desktop Agent — Background Start Script
SET "AGENT_DIR=%~dp0"
IF EXIST "%AGENT_DIR%src\server.js" GOTO FOUND

REM Try other common locations
SET "AGENT_DIR=C:\remote\desktop-agent\"
IF EXIST "%AGENT_DIR%src\server.js" GOTO FOUND

SET "AGENT_DIR=C:\Users\Asus\Downloads\remote\desktop-agent\"
IF EXIST "%AGENT_DIR%src\server.js" GOTO FOUND

REM Read from startup registry using pure batch without quotes inside loop
for /f "tokens=2,*" %%A in ('reg query HKCU\Software\Microsoft\Windows\CurrentVersion\Run /v RemoteConnectAgent 2^>nul') do (
    set "REG_VAL=%%B"
)
if defined REG_VAL (
    set "CLEAN_VAL=%REG_VAL:~12%"
)
if defined CLEAN_VAL (
    set "CLEAN_VAL=%CLEAN_VAL:"=%"
)
if defined CLEAN_VAL (
    for %%i in ("%CLEAN_VAL%") do set "AGENT_DIR=%%~dpi"
)
IF EXIST "%AGENT_DIR%src\server.js" GOTO FOUND

echo ERROR: Could not locate desktop-agent folder.
echo Please run this script from the desktop-agent folder or ensure it is installed correctly.
pause
exit /b 1

:FOUND
REM Check if already running using wmic
wmic process where "name='node.exe' and CommandLine like '%%src/server.js%%'" get ProcessId 2>nul | findstr /r "[0-9]" >nul
IF %ERRORLEVEL% EQU 0 (
    echo RemoteConnect Agent is already running in the background.
    pause
    exit /b 0
)

echo Starting RemoteConnect Agent in background...
cd /d "%AGENT_DIR%"
wscript.exe "%AGENT_DIR%run-silent.vbs"
echo Started!
pause
