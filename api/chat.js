export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Use POST." });
  if (!process.env.GROQ_API_KEY) return res.status(503).json({ error: "GROQ_API_KEY is not configured in the hosting environment." });
  try {
    const input = Array.isArray(req.body?.messages) ? req.body.messages : [];
    const messages = input.slice(-20).filter(m => m && ["user","assistant"].includes(m.role) && typeof m.content === "string" && m.content.length <= 4000);
    if (!messages.length || messages[messages.length-1].role !== "user") return res.status(400).json({error:"Send a user message."});
    const r = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method:"POST", headers:{"Authorization":`Bearer ${process.env.GROQ_API_KEY}`,"Content-Type":"application/json"},
      body:JSON.stringify({model:process.env.GROQ_MODEL||"llama-3.3-70b-versatile",messages:[{role:"system",content:"You are J.A.R.V.I.S., a helpful, calm, concise personal AI assistant inspired by a fictional futuristic assistant. Be honest about your capabilities. Never claim to control the user's device unless a real authorized tool is available."},...messages],temperature:0.7,max_tokens:900})
    });
    const data=await r.json();
    if(!r.ok){console.error("Groq error",r.status,data?.error?.message);return res.status(502).json({error:"Groq request failed. Check API key, model, and account limits."});}
    const reply=data?.choices?.[0]?.message?.content;
    if(typeof reply!=="string")return res.status(502).json({error:"Unexpected AI response."});
    return res.status(200).json({reply});
  } catch(e){console.error("Chat handler error",e);return res.status(500).json({error:"Unexpected server error."});}
}