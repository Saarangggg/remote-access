# RemoteConnect 🖥️📱

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Flutter](https://img.shields.io/badge/Flutter-v3.0+-blue.svg)](https://flutter.dev)
[![Node.js](https://img.shields.io/badge/Node.js-v18+-green.svg)](https://nodejs.org)
[![Platform](https://img.shields.io/badge/Platform-Windows%20%7C%20Android-lightgrey.svg)](#)

RemoteConnect is a robust, production-ready, open-source remote desktop, background input injector, sandboxed file manager, and bidirectional clipboard synchronization suite. It consists of a **Node.js Desktop Background Agent** for Windows and a beautiful **Flutter Mobile Client** for Android.

The system features a **Dual-User Coexistence (Independent Seat Mode)**, allowing a remote mobile user to fully interact with applications on a secondary virtual display without taking focus away from the primary user's mouse and keyboard on Monitor 1.

---

## Key Features 🚀

- **Dual-User Coexistence (True Independent Seat)**:
  - Injects mouse inputs (`click`, `move`, `scroll`, `drag`) and keyboard typing directly into specific application window queues (`HWND`) via a background C# Win32 compiler bridge.
  - Allows two users to operate the same PC simultaneously without cursor hijacking or focus-stealing.
  - Multi-monitor coordinate translation propagates accurately across mixed-DPI screen layouts (e.g. 125% scale on Monitor 1, 100% on Monitor 2).
- **Fast Screen Streaming**:
  - Encoded JPEG-over-WebSocket mirroring pipeline.
  - Configure performance dynamically: low, medium, or high quality, and target frame rates of 15, 30, or 60 FPS.
  - Fast monitor switching support for multi-display layouts.
- **Remote Input Controls**:
  - Native OTG hardware mouse passthrough (move, drag, left/right/middle click, and scrolling) directly to the desktop agent.
  - Touchscreen controls: single-tap (left click), double-tap (double click), long-press (right click), and double-finger drag (scroll wheel emulation).
  - Full keyboard controller with modifier toggles (`Ctrl`, `Alt`, `Shift`, `Win`) and arrow navigation D-Pad.
- **Sandboxed File Explorer**:
  - Browse home folders (Desktop, Downloads, Documents, Pictures, Videos) via interactive chips.
  - Download, upload, rename, move, and delete files with dynamic transfer progress bars.
- **Bidirectional Clipboard Synchronizer**:
  - Sync clips instantly. Turn on Auto-Sync to push/pull clipboard text in the background.
- **Silent Windows Autostart**:
  - Built-in registry installer that registers the agent as a silent Windows background startup process.

---

## Project Structure 📁

```
remote/
├── LICENSE                 # MIT License file
├── README.md               # SEO-optimized documentation
├── desktop-agent/         # Node.js Desktop Background Agent
│   ├── src/
│   │   ├── auth/          # JWT auth & pairing database
│   │   ├── clipboard/     # Clipboard polling & sync
│   │   ├── device/        # Device info & monitor config
│   │   ├── files/         # File sandbox REST API
│   │   ├── input/         # Keyboard & mouse robot inputs (C# bridge compiler)
│   │   ├── screen/        # Multi-monitor screenshot encoder
│   │   ├── tunnel/        # Cloudflared subprocess spawn manager
│   │   └── server.js      # Main Express + Socket.IO Server
│   ├── install.bat        # Add to Windows Registry Run keys
│   └── stop.bat           # Safely terminate agent process
└── mobile-app/            # Flutter (Material 3) Mobile Client
    ├── lib/
    │   ├── core/          # Theme, Navigation Shell, Router
    │   ├── features/      # Screens (Dashboard, Screen, Files, Keyboard, etc.)
    │   └── shared/        # API Clients, Socket manager, Storage service
    └── pubspec.yaml       # App dependencies configuration
```

---

## Desktop Agent Setup (Windows) 💻

### Prerequisites
- Node.js (>= 18.0.0)
- .NET Framework (csc.exe compiler pre-installed on Windows for background C# injection)

### Setup & Run
1. Navigate to the `desktop-agent` directory:
   ```bash
   cd desktop-agent
   npm install
   ```
2. Initialize and configure the environment variables:
   - Run the automated setup script to create `.env` (if not present) and populate it with strong cryptographic JWT secrets:
     ```bash
     node generate-secrets.js
     ```
   - Open the newly generated `.env` file and set your secure agent credentials and optional custom URL:
     ```env
     AGENT_USER=admin
     AGENT_PASSWORD=your_secure_password
     CUSTOM_URL=https://your-custom-tunnel.com
     ```
3. Start the agent:
   ```bash
   npm start
   ```

### Autostart on Boot
- Double-click **`install.bat`** (or run it as Administrator). This registers the startup key under registry path `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`, which silently boots the agent hidden in the background using VBScript on system start.
- To terminate the server, run **`stop.bat`**.

---

## Mobile App Setup (Flutter Client) 📱

### Quick Download
- **Pre-compiled APK**: Download the latest release directly from [sarang-space.site/remote](https://sarang-space.site/remote)

### Prerequisites
- Flutter SDK (>= 3.0.0)
- Android SDK / Device (USB Debugging enabled)

### Build-Time Environment Configuration
For open-source deployment, default credentials and domains are configured via environment compile-time definitions rather than being hardcoded in the source:

```bash
flutter run --dart-define=DEFAULT_URL=https://your-custom-tunnel-url.site \
            --dart-define=DEFAULT_USER=admin \
            --dart-define=DEFAULT_PASSWORD=your_password
```

If these parameters are omitted, the app defaults to safe local development values:
- URL: `http://192.168.1.100:9678`
- User: `admin`
- Password: `admin123`

### Compile Release APK
To build the release Android package with desugaring libraries enabled:
```bash
cd mobile-app
flutter build apk --release
```
The compiled APK will be available at:
`mobile-app/build/app/outputs/flutter-apk/app-release.apk`

---

## True Dual-User Independent Seat (Secondary Monitor Setup) 🖥️🖥️

To work on Monitor 2 from your mobile client while someone else uses Monitor 1 locally:

1. **Virtual Display Driver (VDD)**: Install the Virtual Display Driver (VDD) on Windows:
   ```bash
   winget install VirtualDrivers.Virtual-Display-Driver
   ```
2. **Activate Monitor 2**: Launch the `VDD Control.exe` tool with admin privileges to create a virtual Monitor 2.
3. **Connect Mobile Client**:
   - Log in and navigate to the **Screen** tab.
   - Tap the **Switch Monitor** icon in the App Bar and select **Monitor 2**.
   - Tap the **Coexist Mode** button to cycle to **Independent Seat Mode**.
4. **Result**: Your taps, typing, and mouse scrolls are sent through `PostMessage` directly to background window message queues on Monitor 2. The host PC's primary cursor remains completely uninterrupted on Monitor 1!

---

## License 📄

This project is licensed under the terms of the [MIT License](LICENSE).



## Profile

- GitHub: https://github.com/Saarangggg
- Instagram: https://instagram.com/5araang