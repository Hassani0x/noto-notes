import { createServer, type IncomingMessage } from 'node:http'
import { createHash, timingSafeEqual } from 'node:crypto'

export const actions = ['Proofread Note','Improve Note','Summarize','Change Tone','Fix Grammar','Improve Writing','Make Clearer','Make Shorter','Make Longer','Make Professional','Make Friendly','Make Natural','Simplify','Rewrite','Fix Punctuation'] as const
export const tones = ['Professional','Friendly','Casual','Formal','Confident','Simple','Academic']
export type RequestData = {text:string; action:string; language:string; tone?:string}
export type Edit = {original:string; replacement:string; category:string; explanation:string}
export type Provider = (data:RequestData, signal:AbortSignal) => Promise<unknown>
class Failure extends Error {
  status:number
  constructor(status:number) {super(); this.status=status}
}
function record(v:unknown): v is Record<string,unknown> {
  return typeof v === 'object' && v !== null && !Array.isArray(v)
}
function requestData(v:unknown):RequestData {
  if (!record(v) || typeof v.text !== 'string' || !v.text.trim() || v.text.length > 16000 ||
    !actions.some(a => a === v.action) || typeof v.language !== 'string' || !/^[a-zA-Z-]{2,24}$/.test(v.language) ||
    (v.action === 'Change Tone' && !tones.includes(String(v.tone)))) throw new Failure(400)
  return {text:v.text, action:String(v.action), language:v.language, tone:v.action === 'Change Tone' ? String(v.tone) : undefined}
}
export function validatedEdits(raw:unknown, source:string) {
  if (!record(raw) || !Array.isArray(raw.suggestions) || raw.suggestions.length > 50) throw new Failure(502)
  const occupied:{start:number; end:number}[] = []
  return raw.suggestions.map((e:unknown) => {
    if (!record(e) || !['original','replacement','category','explanation'].every(k => typeof e[k] === 'string') ||
        !(e.original as string).length || (e.replacement as string).length > 32000 ||
        (e.explanation as string).length > 1500 || (e.category as string).length > 100) throw new Failure(502)
    const edit = e as Edit
    const start = source.indexOf(edit.original), end = start + edit.original.length
    if (start < 0 || source.indexOf(edit.original,start+1) >= 0 || occupied.some(r=>start<r.end && r.start<end)) throw new Failure(502)
    occupied.push({start,end})
    return {id:crypto.randomUUID(), ...Object.fromEntries(['original','replacement','category','explanation'].map(k=>[k,e[k]])),start,length:end-start}
  })
}
async function body(req:IncomingMessage) {
  const parts:Buffer[]=[]
  let bytes=0
  for await (const chunk of req) {
    bytes+=chunk.length
    if (bytes>100000) throw new Failure(413)
    parts.push(Buffer.from(chunk))
  }
  try {return JSON.parse(Buffer.concat(parts).toString())} catch {throw new Failure(400)}
}
export function service(token:string, provider:Provider, quota=30) {
  if(token.length<32) throw Error('Set SERVICE_TOKEN to at least 32 characters')
  const digest=(s:string)=>createHash('sha256').update(s).digest()
  const secret=digest('Bearer '+token)
  let requests:number[]=[]
  return createServer(async(req,res)=>{
    res.setHeader('Content-Type','application/json')
    res.setHeader('Cache-Control','no-store')
    try {
      if(req.url!='/v1/writing' || req.method!=='POST') throw new Failure(404)
      if(!timingSafeEqual(digest(req.headers.authorization??''),secret)) throw new Failure(401)
      if(!req.headers['content-type']?.startsWith('application/json')) throw new Failure(415)
      requests=requests.filter(t=>Date.now()-t<60000)
      if(requests.length>=quota) throw new Failure(429)
      requests.push(Date.now())
      const input=requestData(await body(req))
      const disconnect=new AbortController()
      res.on('close',()=>disconnect.abort())
      const raw=await provider(input,AbortSignal.any([disconnect.signal,AbortSignal.timeout(45000)]))
      res.end(JSON.stringify({suggestions:validatedEdits(raw,input.text)}))
    } catch(err) {
      if(res.destroyed) return
      res.statusCode=err instanceof Failure ? err.status : 502
      res.end(JSON.stringify({error:res.statusCode}))
    }
  })
}
