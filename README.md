# J.A.R.V.I.S. Personal AI

A responsive J.A.R.V.I.S.-style web interface with secure server-side endpoints for Gemini AI chat and Fish Audio speech, plus a native macOS companion.

## Features
- Futuristic responsive chat interface
- AI replies through Google Gemini
- Fish Audio speech using your configured reference voice ID
- Browser microphone input where supported
- Live backend status check
- API keys remain server-side

## Deploy with Vercel
1. Open [Vercel](https://vercel.com/) and sign in with GitHub.
2. Import the repository `gadamharshit7-code/jarvis`.
3. In the Vercel project settings, open **Environment Variables** and add:
   - `GEMINI_API_KEY` — your private Google AI Studio API key
   - `FISH_API_KEY` — your private Fish Audio API key
   - `FISH_VOICE_ID` — `612b878b113047d9a770c069c8b4fd`
   - Optional: `GEMINI_MODEL` — `gemini-3.8-flash`
   - Optional: `FISH_MODEL` — `s2.1-pro-free`
4. Redeploy the project after saving the variables.
5. Open the deployed site and send a test message.

## Create API keys safely
Create keys only through the official [Google AI Studio](https://aistudio.google.com/) and [Fish Audio](https://fish.audio/). Never put secret keys in `index.html`, commit them to GitHub, or share them in chat. If a key was ever posted publicly or in a chat, revoke it and create a replacement.

## Local development
Install Node.js and the Vercel CLI, configure secrets in a local `.env.local` file (never commit it), and run `vercel dev`.

## Troubleshooting
- **BACKEND NOT DEPLOYED:** import this repository into Vercel and deploy it.
- **API KEY NEEDED:** add `GEMINI_API_KEY` in Vercel Environment Variables, then redeploy.
- **Fish Audio unavailable:** check `FISH_API_KEY`, `FISH_VOICE_ID`, model, voice access, and account limits.
- Microphone input requires a supported browser and permission.

The macOS companion is built locally from `macOS/JarvisApp.swift` using `macOS/Build-Install.command`. It requires macOS 13 or later, Xcode Command Line Tools, microphone permission, and Speech Recognition permission. It listens for a single clap or “Hey JARVIS”; spoken responses use the configured Fish Audio voice through `/api/speak`.
