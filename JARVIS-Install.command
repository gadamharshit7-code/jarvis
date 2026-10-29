#!/bin/bash
set -euo pipefail

APP_NAME="J.A.R.V.I.S."
APP_DIR="$HOME/Applications/$APP_NAME.app"
CONTENTS="$APP_DIR/Contents"
MACOS="$CONTENTS/MacOS"
SOURCE_DIR="$(mktemp -d)"
trap 'rm -rf "$SOURCE_DIR"' EXIT
mkdir -p "$MACOS" "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"

echo "========================================"
echo "   J.A.R.V.I.S. — ONE-FILE INSTALLER"
echo "========================================"
echo "Building the Mac app…"

cat > "$SOURCE_DIR/JarvisApp.swift" <<'JARVIS_SWIFT_SOURCE'
import SwiftUI
import AVFoundation
import Speech
import AppKit

@MainActor
final class JarvisController: ObservableObject {
    @Published var status = "Starting"
    @Published var transcript = ""
    @Published var reply = "Hello, sir. J.A.R.V.I.S. is ready when you are."
    @Published var backendURL = UserDefaults.standard.string(forKey: "backendURL") ?? ""
    @Published var isListening = false
    @Published var showSettings = false

    private let audioEngine = AVAudioEngine()
    private let speechSynth = AVSpeechSynthesizer()
    private var recognizer: SFSpeechRecognizer? = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var lastWake = Date.distantPast
    private var lastClap = Date.distantPast
    private var clapCooldown = Date.distantPast
    private var isArmed = false
    private var pendingSpeech = ""

    func start() {
        status = "Requesting permissions"
        SFSpeechRecognizer.requestAuthorization { [weak self] auth in
            DispatchQueue.main.async {
                guard let self else { return }
                guard auth == .authorized else {
                    self.status = "Speech permission needed"
                    return
                }
                AVCaptureDevice.requestAccess(for: .audio) { granted in
                    DispatchQueue.main.async {
                        guard granted else { self.status = "Microphone permission needed"; return }
                        self.beginListening()
                    }
                }
            }
        }
    }

    func saveBackend() {
        backendURL = backendURL.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        UserDefaults.standard.set(backendURL, forKey: "backendURL")
        status = backendURL.isEmpty ? "Backend URL not set" : "Backend URL saved"
    }

    func stop() {
        audioEngine.stop()
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isListening = false
        status = "Paused"
    }

    private func beginListening() {
        guard !audioEngine.isRunning else { return }
        do {
            let input = audioEngine.inputNode
            let format = input.outputFormat(forBus: 0)
            guard format.sampleRate > 0 else { status = "No microphone found"; return }
            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { status = "Speech setup failed"; return }
            request.shouldReportPartialResults = true
            request.requiresOnDeviceRecognition = false
            input.removeTap(onBus: 0)
            input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
                request.append(buffer)
                guard let self, let channel = buffer.floatChannelData?[0] else { return }
                let count = Int(buffer.frameLength)
                if count > 0 {
                    var sum: Float = 0
                    for i in 0..<count { sum += channel[i] * channel[i] }
                    let rms = sqrt(sum / Float(count))
                    if rms > 0.42 {
                        DispatchQueue.main.async { self.detectClap() }
                    }
                }
            }
            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
            status = "Listening for “Hey JARVIS” or a clap"
            startRecognitionTask()
        } catch {
            status = "Audio error: \(error.localizedDescription)"
        }
    }

    private func startRecognitionTask() {
        guard let request = recognitionRequest else { return }
        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            DispatchQueue.main.async {
                guard let self else { return }
                if let result {
                    let text = result.bestTranscription.formattedString
                    self.transcript = text
                    let normalized = text.lowercased()
                    if normalized.contains("hey jarvis") || normalized.contains("hey j.a.r.v.i.s") || normalized.contains("hey jars") {
                        if Date().timeIntervalSince(self.lastWake) > 5 {
                            self.lastWake = Date()
                            self.wake()
                        }
                    } else if self.isArmed && !result.isFinal {
                        self.pendingSpeech = text
                    } else if self.isArmed && result.isFinal {
                        self.pendingSpeech = text
                        self.handleCommand(text)
                    }
                }
                if error != nil || (result?.isFinal == true) {
                    self.restartRecognition()
                }
            }
        }
    }

    private func restartRecognition() {
        guard isListening else { return }
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest?.endAudio()
        recognitionRequest = nil
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.beginListening()
        }
    }

    private func detectClap() {
        guard Date().timeIntervalSince(clapCooldown) > 1.2 else { return }
        clapCooldown = Date()
        if Date().timeIntervalSince(lastClap) < 0.7 {
            lastClap = .distantPast
            wake()
        } else {
            lastClap = Date()
        }
    }

    private func wake() {
        isArmed = true
        status = "Awake — speak your command"
        reply = "Hello, sir. All systems are online. How may I assist you?"
        speak(reply)
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first { window.makeKeyAndOrderFront(nil) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in
            self?.isArmed = false
            if self?.isListening == true { self?.status = "Listening for wake phrase or clap" }
        }
    }

    func sendTypedCommand(_ command: String) {
        let text = command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        handleCommand(text)
    }

    private func handleCommand(_ command: String) {
        isArmed = false
        transcript = command
        Task { await askBackend(command) }
    }

    private func askBackend(_ command: String) async {
        guard !backendURL.isEmpty, let url = URL(string: backendURL + "/api/chat") else {
            reply = "Sir, please configure the deployed J.A.R.V.I.S. backend URL in Settings first."
            speak(reply)
            status = "Backend URL not set"
            return
        }
        status = "Thinking"
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 45
            request.httpBody = try JSONSerialization.data(withJSONObject: [
                "messages": [["role": "user", "content": command]]
            ])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            let payload = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let answer = payload?["reply"] as? String ?? "I received an unexpected response, sir."
            reply = answer
            speak(answer)
            status = "Listening for wake phrase or clap"
        } catch {
            reply = "I'm unable to reach the AI service, sir. Please check the backend URL and deployment."
            speak(reply)
            status = "Backend connection failed"
        }
    }

    private func speak(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-GB")
        utterance.rate = 0.48
        speechSynth.stopSpeaking(at: .immediate)
        speechSynth.speak(utterance)
    }
}

@main
struct JarvisApp: App {
    @StateObject private var controller = JarvisController()

    var body: some Scene {
        WindowGroup {
            ContentView(controller: controller)
                .frame(minWidth: 720, minHeight: 540)
                .preferredColorScheme(.dark)
                .onAppear { controller.start() }
        }
        .windowStyle(.titleBar)
    }
}

struct ContentView: View {
    @ObservedObject var controller: JarvisController
    @State private var command = ""

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0.015, green: 0.045, blue: 0.08), Color(red: 0.025, green: 0.12, blue: 0.19)], startPoint: .topLeading, endPoint: .bottomTrailing).ignoresSafeArea()
            VStack(spacing: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("STARK INDUSTRIES // PERSONAL AI").font(.system(size: 10, weight: .semibold, design: .monospaced)).tracking(3).foregroundStyle(.cyan)
                        Text("J.A.R.V.I.S.").font(.system(size: 28, weight: .light, design: .rounded)).tracking(6)
                    }
                    Spacer()
                    Circle().fill(controller.isListening ? .green : .orange).frame(width: 8, height: 8)
                    Text(controller.status.uppercased()).font(.system(size: 10, design: .monospaced)).foregroundStyle(.cyan)
                }
                Divider().overlay(.cyan.opacity(0.25))
                Spacer()
                ZStack {
                    Circle().stroke(.cyan.opacity(0.25), lineWidth: 1).frame(width: 240, height: 240)
                    Circle().stroke(style: StrokeStyle(lineWidth: 1, dash: [3, 7])).foregroundStyle(.cyan.opacity(0.55)).frame(width: 205, height: 205)
                    Circle().stroke(.cyan.opacity(0.45), lineWidth: 2).frame(width: 165, height: 165)
                    Circle().fill(RadialGradient(colors: [.cyan, Color(red: 0.02, green: 0.16, blue: 0.27), .black], center: .center, startRadius: 3, endRadius: 70)).frame(width: 112, height: 112).shadow(color: .cyan.opacity(0.65), radius: 22)
                }
                Text(controller.status == "Paused" ? "STANDBY" : "SYSTEMS ONLINE").font(.system(size: 22, weight: .light, design: .monospaced)).tracking(5)
                Text("Say “Hey JARVIS” or clap twice to wake me").font(.system(size: 12, design: .monospaced)).foregroundStyle(.white.opacity(0.6))
                Text(controller.reply).font(.system(size: 15)).multilineTextAlignment(.center).lineSpacing(5).frame(maxWidth: 560).padding(.horizontal, 20)
                Spacer()
                HStack {
                    TextField("Speak after wake-up, or type a command…", text: $command).textFieldStyle(.roundedBorder).onSubmit { controller.sendTypedCommand(command); command = "" }
                    Button("SEND") { controller.sendTypedCommand(command); command = "" }.buttonStyle(.borderedProminent).tint(.cyan)
                    Button("SETTINGS") { controller.showSettings = true }.buttonStyle(.bordered)
                    Button(controller.isListening ? "PAUSE MIC" : "START MIC") { controller.isListening ? controller.stop() : controller.start() }.buttonStyle(.bordered)
                }
                Text("Wake detection runs on this Mac. Commands sent to the AI backend are processed by the configured online service.").font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
            }.padding(28)
        }
        .sheet(isPresented: $controller.showSettings) {
            VStack(alignment: .leading, spacing: 16) {
                Text("J.A.R.V.I.S. SETTINGS").font(.headline).foregroundStyle(.cyan)
                Text("Deployed backend URL").font(.subheadline)
                TextField("https://your-project.vercel.app", text: $controller.backendURL).textFieldStyle(.roundedBorder)
                Text("Paste only the public website URL here — never an API key. The AI secret stays on the server.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save") { controller.saveBackend(); controller.showSettings = false }.buttonStyle(.borderedProminent)
                    Button("Cancel") { controller.showSettings = false }
                }
            }.padding(24).frame(width: 430)
        }
    }
}
JARVIS_SWIFT_SOURCE

swiftc "$SOURCE_DIR/JarvisApp.swift" -o "$MACOS/Jarvis" -framework SwiftUI -framework AppKit -framework AVFoundation -framework Speech

cat > "$CONTENTS/Info.plist" <<'JARVIS_INFO_PLIST'
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
JARVIS_INFO_PLIST

PLIST_PATH="$HOME/Library/LaunchAgents/com.personal.jarvisassistant.plist"
cat > "$PLIST_PATH" <<JARVIS_LAUNCH_PLIST
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
JARVIS_LAUNCH_PLIST

launchctl bootout "gui/$(id -u)" "$PLIST_PATH" >/dev/null 2>&1 || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_PATH" || true
open "$APP_DIR"

echo
echo "J.A.R.V.I.S. is installed. Approve microphone and speech recognition when asked."
echo "To enable AI answers, deploy the existing backend and set its public URL in app Settings."
echo "If this file does not open, open Terminal and run: chmod +x ~/Downloads/JARVIS-Install.command"
echo "Then double-click it again. This installer requires macOS and Xcode Command Line Tools."
