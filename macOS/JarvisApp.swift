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
    private var fishAudioPlayer: AVAudioPlayer?
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
                    var peak: Float = 0
                    for i in 0..<count { peak = max(peak, abs(channel[i])) }
                    let crest = peak / max(rms, 0.001)
                    if peak > 0.78 && rms > 0.10 && crest > 3.0 {
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
                    let wakePhrases = ["hey j.a.r.v.i.s", "hey jarvis", "hey jars"]
                    let matchedWake = wakePhrases.first { normalized.contains($0) }
                    if let phrase = matchedWake {
                        if Date().timeIntervalSince(self.lastWake) > 5 {
                            self.lastWake = Date()
                            self.wake()
                        }
                        let commandAfterWake = self.textAfterWakePhrase(text, phrase: phrase)
                        if !commandAfterWake.isEmpty {
                            self.pendingSpeech = commandAfterWake
                            if result.isFinal { self.handleCommand(commandAfterWake) }
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

    private func textAfterWakePhrase(_ text: String, phrase: String) -> String {
        guard let range = text.lowercased().range(of: phrase) else { return "" }
        return String(text[range.upperBound...])
            .trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
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
        guard Date().timeIntervalSince(clapCooldown) > 1.4 else { return }
        clapCooldown = Date()
        wake()
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
        Task { await speakWithFishAudio(text) }
    }

    private func speakWithFishAudio(_ text: String) async {
        guard !backendURL.isEmpty, let url = URL(string: backendURL + "/api/speak") else {
            status = "Set backend URL for Fish Audio voice"
            return
        }
        do {
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.timeoutInterval = 45
            request.httpBody = try JSONSerialization.data(withJSONObject: ["text": text])
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200..<300).contains(http.statusCode),
                  http.value(forHTTPHeaderField: "Content-Type")?.contains("audio") == true else {
                throw URLError(.badServerResponse)
            }
            let player = try AVAudioPlayer(data: data)
            fishAudioPlayer = player
            player.prepareToPlay()
            player.play()
        } catch {
            status = "Fish Audio unavailable — check FISH_API_KEY and FISH_VOICE_ID"
        }
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
    @State private var selected = "HOME"
    private let cyan = Color(red: 0.04, green: 0.78, blue: 1)
    private let panel = Color(red: 0.008, green: 0.055, blue: 0.09)

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color(red: 0.002, green: 0.012, blue: 0.025).ignoresSafeArea()
                VStack(spacing: 0) {
                    HStack(spacing: 14) {
                        ZStack {
                            Circle().stroke(cyan, lineWidth: 3).frame(width: 55, height: 55)
                            Circle().stroke(cyan.opacity(0.7), lineWidth: 2).frame(width: 38, height: 38)
                            Circle().fill(cyan).frame(width: 13, height: 13).shadow(color: cyan, radius: 8)
                        }
                        Text("J.A.R.V.I.S.").font(.system(size: 30, weight: .medium)).tracking(8).foregroundStyle(cyan)
                        Spacer()
                        Text(controller.isListening ? "SYSTEMS ONLINE" : "SYSTEM STANDBY")
                        Text(Date(), style: .time)
                        Text(Date(), style: .date)
                    }.font(.system(size: 11, design: .monospaced)).foregroundStyle(cyan).padding(22)
                    Rectangle().fill(cyan.opacity(0.55)).frame(height: 1)
                    HStack(alignment: .top, spacing: 18) {
                        VStack(spacing: 0) {
                            ForEach(["HOME","SYSTEMS","COMMUNICATIONS","DIAGNOSTICS","FILE ACCESS","SETTINGS"], id: \.self) { item in
                                Button {
                                    selected = item
                                    if item == "SETTINGS" { controller.showSettings = true }
                                } label: {
                                    HStack {
                                        Image(systemName: navIcon(item)).frame(width: 25)
                                        Text(item).font(.system(size: 12, design: .monospaced)).tracking(1)
                                        Spacer()
                                    }.foregroundStyle(selected == item ? .white : cyan)
                                     .padding(15).background(selected == item ? cyan.opacity(0.18) : .clear)
                                     .overlay(alignment: .leading) { if selected == item { Rectangle().fill(cyan).frame(width: 3) } }
                                }.buttonStyle(.plain)
                            }
                        }.frame(width: geo.size.width * 0.205).background(panel)
                         .overlay(RoundedRectangle(cornerRadius: 7).stroke(cyan.opacity(0.55)))
                        Spacer(minLength: 0)
                        VStack(spacing: 13) {
                            ZStack {
                                ForEach(0..<8, id: \.self) { i in
                                    Circle().stroke(cyan.opacity(0.2 + Double(i) * 0.035), lineWidth: 1)
                                        .frame(width: CGFloat(170 + i * 37), height: CGFloat(170 + i * 37))
                                }
                                Circle().trim(from: 0.03, to: 0.28).stroke(cyan, style: StrokeStyle(lineWidth: 8, lineCap: .round)).frame(width: 300, height: 300).rotationEffect(.degrees(-35))
                                Circle().trim(from: 0.39, to: 0.72).stroke(cyan.opacity(0.9), style: StrokeStyle(lineWidth: 7, lineCap: .round)).frame(width: 350, height: 350).rotationEffect(.degrees(25))
                                Circle().trim(from: 0.12, to: 0.86).stroke(Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 2, dash: [3,8])).frame(width: 390, height: 390)
                                Circle().fill(RadialGradient(colors: [cyan, Color(red: 0.01, green: 0.16, blue: 0.29), .black], center: .center, startRadius: 3, endRadius: 70)).frame(width: 110, height: 110).shadow(color: cyan, radius: 25)
                            }.frame(height: 470)
                            Text("J.A.R.V.I.S. // ONLINE").font(.system(size: 17, design: .monospaced)).tracking(4).foregroundStyle(cyan)
                            Text("SAY “HEY JARVIS” OR CLAP ONCE TO ACTIVATE").font(.system(size: 10, design: .monospaced)).tracking(1).foregroundStyle(.white.opacity(0.65))
                            Text(controller.reply).font(.system(size: 13)).foregroundStyle(.white).multilineTextAlignment(.center).lineLimit(2)
                            HStack {
                                TextField("Speak or type a command…", text: $command).textFieldStyle(.roundedBorder).onSubmit { controller.sendTypedCommand(command); command = "" }
                                Button("SEND") { controller.sendTypedCommand(command); command = "" }.buttonStyle(.borderedProminent).tint(cyan)
                            }.frame(maxWidth: 510)
                        }.frame(maxWidth: .infinity)
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("HELLO, MASTER").font(.system(size: 20, weight: .medium)).tracking(4).foregroundStyle(cyan)
                            Text("HOW CAN I HELP YOU TODAY?").font(.system(size: 10)).tracking(1.3).foregroundStyle(cyan).padding(.top, 10).padding(.bottom, 20)
                            VStack(spacing: 0) {
                                ForEach(["ARMOR SYSTEMS","FLIGHT SYSTEMS","WEAPONS SYSTEMS","SENSORS","AI CORE"], id: \.self) { item in
                                    HStack {
                                        Text(item).font(.system(size: 10, design: .monospaced))
                                        Spacer()
                                        Text(item == "AI CORE" && !controller.isListening ? "STANDBY" : "ONLINE").font(.system(size: 10, design: .monospaced)).foregroundStyle(cyan)
                                    }.padding(.vertical, 14)
                                    Rectangle().fill(cyan.opacity(0.2)).frame(height: 1)
                                }
                            }.padding(12).background(panel).overlay(RoundedRectangle(cornerRadius: 6).stroke(cyan.opacity(0.5)))
                            Spacer().frame(height: 18)
                            Canvas { ctx, size in
                                for row in 0..<13 {
                                    for col in 0..<28 {
                                        let rect = CGRect(x: CGFloat(col) * size.width / 28 + 1, y: CGFloat(row) * size.height / 13 + 1, width: 2.3, height: 2.3)
                                        ctx.fill(Path(ellipseIn: rect), with: .color(cyan.opacity(0.55)))
                                    }
                                }
                            }.frame(height: 125).background(panel)
                            HStack {
                                Text("GLOBAL NETWORK").font(.system(size: 10, design: .monospaced))
                                Spacer()
                                Text("CONNECTED").font(.system(size: 10, design: .monospaced)).foregroundStyle(cyan)
                            }.padding(10).background(panel).overlay(RoundedRectangle(cornerRadius: 6).stroke(cyan.opacity(0.45)))
                            Spacer().frame(height: 14)
                            Button(controller.isListening ? "PAUSE MICROPHONE" : "START MICROPHONE") {
                                controller.isListening ? controller.stop() : controller.start()
                            }.buttonStyle(.bordered).tint(cyan).frame(maxWidth: .infinity)
                        }.padding(15).frame(width: geo.size.width * 0.255).background(panel.opacity(0.85))
                         .overlay(RoundedRectangle(cornerRadius: 7).stroke(cyan.opacity(0.5)))
                    }.padding(.horizontal, 18).padding(.top, 24)
                    Spacer(minLength: 6)
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("J.A.R.V.I.S.").font(.system(size: 23)).tracking(8).foregroundStyle(cyan)
                            Text("JUST A RATHER VERY INTELLIGENT SYSTEM").font(.system(size: 10, design: .monospaced)).tracking(3).foregroundStyle(cyan)
                            Rectangle().fill(cyan).frame(width: 430, height: 1)
                        }
                        Spacer()
                        HStack(alignment: .bottom, spacing: 4) {
                            ForEach(0..<24, id: \.self) { i in Rectangle().fill(cyan.opacity(0.65)).frame(width: 5, height: CGFloat(10 + (i * 17 % 40))) }
                        }.frame(height: 45, alignment: .bottom)
                    }.padding(.horizontal, 28).padding(.vertical, 14)
                }
            }
        }
        .frame(minWidth: 1250, minHeight: 850)
        .preferredColorScheme(.dark)
        .sheet(isPresented: $controller.showSettings) {
            VStack(alignment: .leading, spacing: 16) {
                Text("J.A.R.V.I.S. SETTINGS").font(.headline).foregroundStyle(cyan)
                Text("Deployed backend URL")
                TextField("https://your-project.vercel.app", text: $controller.backendURL).textFieldStyle(.roundedBorder)
                Text("Fish Audio uses your confirmed voice ID configured securely on the backend.").font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Save") { controller.saveBackend(); controller.showSettings = false }.buttonStyle(.borderedProminent)
                    Button("Cancel") { controller.showSettings = false }
                }
            }.padding(24).frame(width: 440)
        }
    }

    private func navIcon(_ item: String) -> String {
        switch item {
        case "HOME": return "house.fill"
        case "SYSTEMS": return "gearshape.fill"
        case "COMMUNICATIONS": return "antenna.radiowaves.left.and.right"
        case "DIAGNOSTICS": return "waveform.path.ecg"
        case "FILE ACCESS": return "folder"
        default: return "slider.horizontal.3"
        }
    }
}
