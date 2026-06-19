# RemoteConnect — Cross-Platform Remote Connectivity Platform

A production-ready remote desktop, file manager, input controller, and clipboard sync system built with **Node.js** (Windows Background Agent) and **Flutter** (Mobile App client). Connected securely via **Cloudflare Tunnels**.

---

## Features

1. **Device Pairing**: Enter a 6-digit pin code shown on the desktop or scan the QR code to pair over Cloudflare Tunnel (HTTPS).
2. **Real-time Screen Mirroring**: Custom-tuned JPEG-over-WebSocket streaming pipeline with configurable quality (Low/Med/High) and frame rates (15/30/60 FPS).
3. **Remote Inputs**:
   - Single tap → Left click.
   - Double tap → Double click.
   - Long press → Right click.
   - Drag/Pan → Mouse movement & click drag.
   - Scale pinch → Two-finger scroll wheel emulation.
   - Desktop Keyboard control with modifier keys (Ctrl, Alt, Shift, Win/Super) and Function keys (F1-F12).
4. **Encrypted File Manager**:
   - Safe sandbox roots: Desktop, Downloads, Documents, Pictures, Videos.
   - Upload & download files with linear progress tracking.
   - Directory navigation, search, create folder, move, rename, delete.
5. **Real-time Clipboard Sync**: Sync clipboard bidirectionally. Options for manual push/pull or background auto-sync.
6. **Windows Agent Service**: Installs silently as a Windows background agent starting automatically on login.

---

## Project Structure

```
remote/
├── desktop-agent/         # Node.js Desktop Background Agent
│   ├── src/
│   │   ├── auth/          # JWT auth & pairing database
│   │   ├── clipboard/     # Clipboard polling & sync
│   │   ├── device/        # Device info & monitor config
│   │   ├── files/         # File sandbox REST API
│   │   ├── input/         # Keyboard & mouse robot inputs
│   │   ├── screen/        # Multi-monitor screenshot encoder
│   │   ├── tunnel/        # Cloudflared subprocess spawn manager
│   │   ├── utils/         # Config & Winston Logger
│   │   └── server.js      # Main Express + Socket.IO Server
│   ├── install.bat        # Add to Windows Registry Run keys
│   └── uninstall.bat      # Remove from Windows startup
│
└── mobile-app/            # Flutter (Material 3) Mobile Client
    ├── lib/
    │   ├── core/          # Theme, Navigation Shell
    │   ├── features/      # Screens (Dashboard, Screen, Files, Keyboard, etc.)
    │   └── shared/        # API Clients, Socket manager, Storage service
    └── pubspec.yaml       # App dependencies configuration
```

---

## Getting Started

### Prerequisites
- Node.js (>= 18.0.0)
- Flutter SDK (>= 3.3.0)
- Cloudflared installed in system path (optional, if you want automatic public Cloudflare tunneling)

### Setup Desktop Agent
1. Open terminal in `desktop-agent` directory:
   ```bash
   cd desktop-agent
   npm install
   ```
2. Copy `.env.example` to `.env` and configure port or paths.
3. Start the agent:
   ```bash
   npm start
   ```
4. A pairing QR code and 6-digit pin code will be printed in the terminal.

#### Autostart with Windows
To configure the agent to run silently in the background on startup, run the installer:
1. Double-click `install.bat` or run it from an Administrator command prompt.
2. The script registers the startup key in `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`.

To disable autostart:
1. Double-click `uninstall.bat`.

---

## Setup Mobile App
1. Go to `mobile-app` directory:
   ```bash
   cd mobile-app
   flutter pub get
   ```
2. Run the application on your Android/iOS device:
   ```bash
   flutter run
   ```
3. Scan the QR code displayed on the desktop command line or enter the trycloudflare URL and pin code to pair!
