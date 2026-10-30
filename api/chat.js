export default async function handler(req, res) {
  if (req.method !== "POST") return res.status(405).json({ error: "Use POST." });
  if (!process.env.GEMINI_API_KEY) return res.status(503).json({ error: "GEMINI_API_KEY is not configured in the hosting environment." });
  try {
    const input = Array.isArray(req.body?.messages) ? req.body.messages : [];
    const messages = input.slice(-20).filter(m => m && ["user", "assistant"].includes(m.role) && typeof m.content === "string" && m.content.length <= 4000);
    if (!messages.length || messages[messages.length - 1].role !== "user") return res.status(400).json({ error: "Send a user message." });

    const contents = messages.map(m => ({
      role: m.role === "assistant" ? "model" : "user",
      parts: [{ text: m.content }]
    }));

    const model = process.env.GEMINI_MODEL || "gemini-3.8-flash";
    const response = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${model}:generateContent`, {
      method: "POST",
      headers: {
        "x-goog-api-key": process.env.GEMINI_API_KEY,
        "Content-Type": "application/json"
      },
      body: JSON.stringify({
        systemInstruction: {
          parts: [{ text: "You are J.A.R.V.I.S., a helpful, calm, concise personal AI assistant inspired by a fictional futuristic assistant. Be honest about your capabilities. Never claim to control the user's device unless a real authorized tool is available." }]
        },
        contents,
        generationConfig: { temperature: 0.7, maxOutputTokens: 900 }
      })
    });

    const data = await response.json();
    if (!response.ok) {
      console.error("Gemini error", response.status, data?.error?.message);
      return res.status(502).json({ error: "Gemini request failed. Check the Gemini API key, model, and Google AI Studio access." });
    }

    const reply = data?.candidates?.[0]?.content?.parts?.map(p => p.text || "").join("").trim();
    if (!reply) {
      console.error("Gemini returned no text", data?.promptFeedback || data?.candidates?.[0]?.finishReason);
      return res.status(502).json({ error: "Gemini returned no text. Try rephrasing your message." });
    }
    return res.status(200).json({ reply });
  } catch (e) {
    console.error("Chat handler error", e);
    return res.status(500).json({ error: "Unexpected server error." });
  }
}
