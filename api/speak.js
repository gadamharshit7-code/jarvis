export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({error:"Use POST."});
  if (!process.env.FISH_API_KEY) return res.status(503).json({error:"FISH_API_KEY is not configured; browser speech fallback will be used."});
  try {
    const text=String(req.body?.text||"").trim().slice(0,1800);
    if(!text)return res.status(400).json({error:"Text is required."});
    const r=await fetch("https://api.fish.audio/v1/tts",{
      method:"POST",headers:{"Authorization":`Bearer ${process.env.FISH_API_KEY}`,"Content-Type":"application/json","model":process.env.FISH_MODEL||"s2.1-pro-free"},
      body:JSON.stringify({text,reference_id:process.env.FISH_VOICE_ID||"14129c3e320149449d6bada6862f7338",format:"mp3"})
    });
    if(!r.ok){console.error("Fish Audio error",r.status,(await r.text()).slice(0,300));return res.status(502).json({error:"Fish Audio failed. Check API key, voice access, and account limits."});}
    const audio=Buffer.from(await r.arrayBuffer());res.setHeader("Content-Type","audio/mpeg");res.setHeader("Cache-Control","no-store");return res.status(200).send(audio);
  }catch(e){console.error("Speech handler error",e);return res.status(500).json({error:"Unexpected server error while generating speech."});}
}