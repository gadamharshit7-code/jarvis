# J.A.R.V.I.S. for macOS

This native SwiftUI app is a first implementation of the always-ready Mac assistant. It can start at login, listen for a wake phrase or two claps, speak a greeting, and send a command to the project's secure `/api/chat` backend.

## Requirements
- macOS 13 or later
- Xcode Command Line Tools / Swift compiler (`xcode-select --install` if Swift is missing)
- A deployed copy of this repository with `GROQ_API_KEY` configured in the hosting provider

## Install
1. Download this repository as a ZIP from GitHub and extract it.
2. Open the extracted `macOS` folder.
3. Double-click `Build-Install.command`. If macOS blocks it, Control-click/right-click the file and select **Open**.
4. Approve microphone and Speech Recognition permissions when macOS asks.
5. In J.A.R.V.I.S., click **Settings** and paste your deployed site's public URL, such as `https://your-project.vercel.app`. Do not paste API keys into the app.
6. Say **“Hey JARVIS”** or clap twice. The app should speak its greeting and bring its window forward.

## Privacy and limitations
- The microphone must remain available while wake detection is enabled. macOS shows and controls permissions under **System Settings → Privacy & Security**.
- The app uses Apple's Speech framework to recognize the wake phrase. Depending on macOS settings, recognition may send audio to Apple's speech service; this is not guaranteed to be fully offline.
- Clap detection is a simple microphone-volume threshold and can have false positives or miss quiet claps depending on the room and microphone.
- When you speak a command after waking, the app sends the recognized text to your configured backend; the backend sends it to Groq. The app does not need your Groq API key.
- The current build is an early implementation, not a signed/notarized release. It must be compiled and tested on the target Mac. It does not control arbitrary apps or execute shell commands.
- Login startup is configured with a per-user LaunchAgent. To disable it, remove `~/Library/LaunchAgents/com.personal.jarvisassistant.plist` and log out/in, or use Terminal: `launchctl bootout gui/$(id -u) ~/Library/LaunchAgents/com.personal.jarvisassistant.plist`.

This installer creates the app under `~/Applications` and a LaunchAgent under `~/Library/LaunchAgents`; it does not request administrator access.
