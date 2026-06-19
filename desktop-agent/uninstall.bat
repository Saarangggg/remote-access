@echo off
SET STARTUP_KEY=HKCU\Software\Microsoft\Windows\CurrentVersion\Run
SET APP_NAME=RemoteConnectAgent

REG DELETE "%STARTUP_KEY%" /V "%APP_NAME%" /F
IF ERRORLEVEL 1 (
    echo Agent was not registered for startup.
) ELSE (
    echo RemoteConnect Agent removed from startup successfully.
)
pause
