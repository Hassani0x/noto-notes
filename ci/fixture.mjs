// Simulator-only deterministic service. The app's release build cannot select it.
import {createServer} from 'node:http'
createServer(async(req,res)=>{
  if(req.url !== '/v1/writing' || req.headers.authorization !== 'Bearer simulator-fixture') {
    res.writeHead(401).end()
    return
  }
  const chunks=[]
  for await(const chunk of req) chunks.push(chunk)
  const {text}=JSON.parse(Buffer.concat(chunks))
  const original='I goes', start=text.indexOf(original)
  res.setHeader('content-type','application/json')
  res.end(JSON.stringify({suggestions:start<0?[]:[{id:crypto.randomUUID(),original,replacement:'I went',category:'Grammar',explanation:'Use the past tense for yesterday.',start,length:original.length}]}))
}).listen(8989,'127.0.0.1')
