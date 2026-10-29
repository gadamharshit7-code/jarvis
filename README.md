# J.A.R.V.I.S. Personal AI

A responsive J.A.R.V.I.S.-style web interface with secure server-side endpoints for Groq AI chat and Fish Audio speech.

## Features
- Futuristic responsive chat interface
- AI replies through Groq
- Optional Fish Audio voice output, with browser speech fallback
- Browser microphone input where supported
- Live backend status check
- API keys remain server-side

## Deploy with Vercel
1. Open [Vercel](https://vercel.com/) and sign in with GitHub.
2. Import the repository `gadamharshit7-code/jarvis`.
3. In the Vercel project settings, open **Environment Variables** and add:
   - `GROQ_API_KEY` — your private Groq API key
   - `FISH_API_KEY` — your private Fish Audio API key (optional; browser speech fallback works without it)
   - `FISH_VOICE_ID` — `14129c3e320149449d6bada6862f7338`
   - Optional: `GROQ_MODEL` — `llama-3.3-70b-versatile`
   - Optional: `FISH_MODEL` — `s2.1-pro-free`
4. Redeploy the project after saving the variables.
5. Open the deployed site and send a test message.

## Create API keys safely
Create keys only through the official [Groq Console](https://console.groq.com/) and [Fish Audio](https://fish.audio/). Never put secret keys in `index.html`, commit them to GitHub, or share them in chat. If a key was ever posted publicly or in a chat, revoke it and create a replacement.

## Local development
Install Node.js and the Vercel CLI, configure secrets in a local `.env.local` file (never commit it), and run `vercel dev`.

## Troubleshooting
- **BACKEND NOT DEPLOYED:** import this repository into Vercel and deploy it.
- **API KEY NEEDED:** add `GROQ_API_KEY` in Vercel Environment Variables, then redeploy.
- **Speech fallback:** check the Fish Audio key, model, voice access, and account limits.
- Microphone input requires a supported browser and permission.

This is a web-based assistant, not a system-level agent; it cannot control your computer unless you separately build and authorize such integrations.
