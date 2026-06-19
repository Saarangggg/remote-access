@echo off
SETLOCAL EnableDelayedExpansion
echo ============================================================
echo   RemoteConnect Desktop Agent Quick Installer
echo ============================================================
echo.

:: Check Admin privileges
net session >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] WARNING: Some software installations or startup registrations might require Administrator privileges.
    echo     If the installation fails, please right-click this script and select "Run as Administrator".
    echo.
)

:: 1. Check for Git
where git >nul 2>&1
if %errorLevel% neq 0 (
    echo [-] Git is not installed. Installing Git via winget...
    winget install --id Git.Git -e --silent --accept-source-agreements --accept-package-agreements
    if %errorLevel% neq 0 (
        echo [X] Error: Failed to install Git. Please install it manually from https://git-scm.com/
        pause
        exit /b 1
    )
    echo [+] Git installed successfully.
    :: Refresh PATH for current session
    refreshenv >nul 2>&1 || (
        set "PATH=%PATH%;%ProgramFiles%\Git\cmd"
    )
) else (
    echo [+] Git is already installed.
)

:: 2. Check for Node.js
where node >nul 2>&1
if %errorLevel% neq 0 (
    echo [-] Node.js is not installed. Installing Node.js LTS via winget...
    winget install --id OpenJS.NodeJS.LTS -e --silent --accept-source-agreements --accept-package-agreements
    if %errorLevel% neq 0 (
        echo [X] Error: Failed to install Node.js. Please install it manually from https://nodejs.org/
        pause
        exit /b 1
    )
    echo [+] Node.js installed successfully.
    :: Refresh PATH for current session
    refreshenv >nul 2>&1 || (
        set "PATH=%PATH%;%ProgramFiles%\nodejs"
    )
) else (
    echo [+] Node.js is already installed.
)

:: Double check commands are available now
where git >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Git command not found in current command prompt session.
    echo     Please restart your command prompt or computer, and run this script again.
    pause
    exit /b 1
)

where node >nul 2>&1
if %errorLevel% neq 0 (
    echo [!] Node.js command not found in current command prompt session.
    echo     Please restart your command prompt or computer, and run this script again.
    pause
    exit /b 1
)

:: 3. Clone only the desktop-agent folder using Git Sparse-Checkout
echo.
echo [+] Downloading Desktop Agent files (excluding mobile app)...
set "REPO_URL=https://github.com/Saarangggg/remote-access.git"
set "TARGET_DIR=remote-connect-agent"

if exist "%TARGET_DIR%" (
    echo [!] Target directory "%TARGET_DIR%" already exists.
    set /p "choice=Overwrite existing directory? (Y/N): "
    if /i "!choice!"=="Y" (
        rmdir /s /q "%TARGET_DIR%"
    ) else (
        echo [X] Installation aborted by user.
        pause
        exit /b 0
    )
)

:: Initialize sparse clone
git clone --filter=blob:none --no-checkout --depth 1 %REPO_URL% %TARGET_DIR%
if %errorLevel% neq 0 (
    echo [X] Error: Git clone failed.
    pause
    exit /b 1
)

cd %TARGET_DIR%
git sparse-checkout set desktop-agent
git checkout
if %errorLevel% neq 0 (
    echo [X] Error: Sparse-checkout configuration failed.
    pause
    exit /b 1
)

:: Navigate to agent folder
cd desktop-agent

:: 4. Install Dependencies
echo.
echo [+] Installing npm dependencies...
call npm install
if %errorLevel% neq 0 (
    echo [X] Error: npm install failed.
    pause
    exit /b 1
)

:: 5. Create .env and Generate secure keys
echo.
echo [+] Generating secure cryptographic keys...
if not exist ".env" (
    copy ".env.example" ".env" >nul
)
call node generate-secrets.js

:: 6. Configure Autostart and Boot Server silently in background
echo.
echo [+] Registering Windows Registry Startup Keys and booting background service...
call install.bat

echo.
echo ============================================================
echo   RemoteConnect Agent installation complete!
echo   The server is now running silently in the background on Port 9678.
echo   It will boot automatically whenever Windows starts.
echo.
echo   To stop the server at any time, run stop.bat inside:
echo   %CD%
echo ============================================================
echo.
pause
