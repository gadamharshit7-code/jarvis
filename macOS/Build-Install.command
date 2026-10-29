#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP_NAME="J.A.R.V.I.S."
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
RESOURCES="$CONTENTS/Resources"
mkdir -p "$MACOS" "$RESOURCES" "$HOME/Library/LaunchAgents"
echo "Building J.A.R.V.I.S. for this Mac…"
swiftc JarvisApp.swift -o "$MACOS/Jarvis" -framework SwiftUI -framework AppKit -framework AVFoundation -framework Speech
cat > "$CONTENTS/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>J.A.R.V.I.S.</string>
<key>CFBundleDisplayName</key><string>J.A.R.V.I.S.</string>
<key>CFBundleIdentifier</key><string>com.personal.jarvisassistant</string>
<key>CFBundleExecutable</key><string>Jarvis</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleVersion</key><string>1.0</string>
<key>CFBundleShortVersionString</key><string>1.0</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSMicrophoneUsageDescription</key><string>J.A.R.V.I.S. uses the microphone locally to detect your wake phrase or claps and hear commands.</string>
<key>NSSpeechRecognitionUsageDescription</key><string>J.A.R.V.I.S. uses speech recognition to detect your wake phrase and understand spoken commands.</string>
</dict></plist>
PLIST
PLIST_PATH="$HOME/Library/LaunchAgents/com.personal.jarvisassistant.plist"
cat > "$PLIST_PATH" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>com.personal.jarvisassistant</string>
<key>ProgramArguments</key><array><string>$MACOS/Jarvis</string></array>
<key>RunAtLoad</key><true/>
<key>KeepAlive</key><true/>
<key>StandardOutPath</key><string>$HOME/Library/Logs/jarvis.log</string>
<key>StandardErrorPath</key><string>$HOME/Library/Logs/jarvis-error.log</string>
</dict></plist>
PLIST
launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH"
open "$APP_DIR"
echo
echo "J.A.R.V.I.S. was built and added to your login startup items."
echo "Approve microphone and speech recognition when macOS asks."
echo "Open Settings in the app and enter your deployed backend URL."
echo "If macOS blocks this script, right-click it and choose Open."
