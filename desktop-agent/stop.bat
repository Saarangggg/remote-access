@echo off
REM RemoteConnect Desktop Agent — Stop Script
SET "AGENT_DIR=%~dp0"
IF EXIST "%AGENT_DIR%src\server.js" GOTO FOUND

REM Try other common locations
SET "AGENT_DIR=C:\remote-access\desktop-agent\"
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

echo ERROR: Could not locate desktop-agent folder to stop the server.
echo Please run this script from the desktop-agent folder or ensure it is installed correctly.
pause
exit /b 1

:FOUND
echo Stopping RemoteConnect Agent...
wmic process where "name='node.exe' and CommandLine like '%%src/server.js%%'" call terminate >nul 2>&1
echo Stopped successfully (if it was running).
pause
