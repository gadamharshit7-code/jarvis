export default function handler(req,res){
  res.setHeader("Cache-Control","no-store");
  return res.status(200).json({ok:true,groqConfigured:Boolean(process.env.GROQ_API_KEY),fishConfigured:Boolean(process.env.FISH_API_KEY),message:"J.A.R.V.I.S. backend is running."});
}