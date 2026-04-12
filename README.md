# MacExpert

Modern macOS control application for **SPE Expert HF amplifiers** (1.3K-FA / 1.5K-FA / 2K-FA).

Built with Swift and SwiftUI. Supports both **local USB serial** and **WebSocket** connections (via [spe-remote](https://github.com/vu2cpl/spe-remote)).

## Features

- **Dual connection mode** — USB serial (direct) or WebSocket (remote via spe-remote on Raspberry Pi)
- **Full command set** — all 20 SPE commands: Operate, Tune, Antenna, Band, Power, CAT, Display, Set, L/C +/-, Backlight, arrows
- **Live monitoring** — output power, SWR (ATU + antenna), drain current, PA temperature, supply voltage
- **Auto-detect** amplifier model from serial status ID field (13K / 20K)
- **Adaptive polling** — 200ms during TX, 1s when idle (serial mode; WebSocket receives server pushes)
- **Power bar auto-scales** to L/M/H power level setting
- **Warning and alarm display** — all SPE warning/alarm codes decoded
- **Settings persistence** — connection preferences saved across sessions
- **Auto-reconnect** for WebSocket drops
- **Apple Silicon native** — arm64 binary

## Requirements

- macOS 14.0 (Sonoma) or later
- For serial mode: USB cable to SPE Expert amplifier
- For WebSocket mode: [spe-remote](https://github.com/vu2cpl/spe-remote) running on a network-accessible host

## Install and Run

### Option 1: Build from source

```bash
git clone https://github.com/vu2cpl/macexpert-spe.git
cd macexpert-spe
swift build -c release
```

The binary will be at `.build/release/MacExpert`. Run it directly:

```bash
.build/release/MacExpert
```

### Option 2: Build as .app bundle

```bash
git clone https://github.com/vu2cpl/macexpert-spe.git
cd macexpert-spe
swift build -c release

# Create app bundle
mkdir -p MacExpert.app/Contents/MacOS MacExpert.app/Contents/Resources
cp .build/release/MacExpert MacExpert.app/Contents/MacOS/
cp MacExpert/Resources/ExpertIcon.icns MacExpert.app/Contents/Resources/

cat > MacExpert.app/Contents/Info.plist << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>MacExpert</string>
    <key>CFBundleIconFile</key><string>ExpertIcon</string>
    <key>CFBundleIdentifier</key><string>com.vu2cpl.MacExpert</string>
    <key>CFBundleName</key><string>MacExpert</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>2.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSPrincipalClass</key><string>NSApplication</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo 'APPL????' > MacExpert.app/Contents/PkgInfo
```

Then double-click `MacExpert.app` or:

```bash
open MacExpert.app
```

### Option 3: Open in Xcode

```bash
open Package.swift
```

Xcode will resolve the SPM dependency (ORSSerialPort) and you can build/run from there.

## Usage

### Serial Mode

1. Connect the SPE Expert amplifier via USB
2. Launch MacExpert
3. Select **Serial** mode
4. Choose the USB serial port from the dropdown
5. Baud rate: **115200** (default)
6. Click **Connect**

### WebSocket Mode

1. Ensure [spe-remote](https://github.com/vu2cpl/spe-remote) is running on your Raspberry Pi or server
2. Launch MacExpert
3. Select **WebSocket** mode
4. Enter the host IP and port (default: 8888)
5. Click **Connect**

## SPE Protocol

Based on the **SPE Application Programmer's Guide Rev 1.1** (15.10.2015).

- Serial: 115200 baud, 8N1, no parity
- Packet format: `0x55 0x55 0x55 [CNT] [DATA] [CHK]` (host to amp)
- Status response: 67-char ASCII CSV with 19 fields
- 20 commands (0x01-0x11, 0x82, 0x83, 0x90)

## Dependencies

- [ORSSerialPort](https://github.com/armadsen/ORSSerialPort) — macOS serial port library (via SPM)

## Project Structure

```
MacExpert/
├── MacExpertApp.swift           # App entry point
├── Models/
│   ├── AmplifierState.swift     # State model (Codable, serial + WebSocket)
│   ├── AmplifierModel.swift     # Amp model enum with power limits
│   └── SPEProtocol.swift        # Commands, packet builder, status parser
├── Connection/
│   ├── ConnectionProvider.swift # Connection protocol
│   ├── SerialConnection.swift   # USB serial via ORSSerialPort
│   └── WebSocketConnection.swift# WebSocket client
├── ViewModels/
│   └── AmplifierViewModel.swift # Observable state management
├── Views/
│   ├── ContentView.swift        # Main layout
│   ├── ConnectionView.swift     # Connection settings
│   ├── PowerDisplayView.swift   # Power bar + readout
│   ├── GaugeView.swift          # Arc gauges (SWR, drain, temp, voltage)
│   ├── StatusChipsView.swift    # Status indicators
│   ├── ControlsView.swift       # Control button grid
│   └── AlertBarView.swift       # Warning/alarm banner
└── Resources/
    └── ExpertIcon.icns          # App icon
```

## License

MIT

## Credits

- Original MacExpert by Georg Isenbuerger DJ6GI/NZ1C
- SPE protocol reference by SPE s.r.l.
- [spe-remote](https://github.com/vu2cpl/spe-remote) by VU2CPL
- [ORSSerialPort](https://github.com/armadsen/ORSSerialPort) by Andrew Madsen AC7CF
