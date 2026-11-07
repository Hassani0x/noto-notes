import test from 'node:test'
import assert from 'node:assert/strict'
import {service,validatedEdits} from '../src/service.ts'
import {once} from 'node:events'
import type {AddressInfo} from 'node:net'
const e={original:'teh',replacement:'the',category:'spelling',explanation:'Spelling'}
test('UTF-16 anchors; reject ambiguous, missing, overlapping edits',()=>{
  assert.equal(validatedEdits({suggestions:[e]},'🙂 teh')[0].start,3)
  for(const [text,edits] of [['teh teh',[e]],['ok',[e]],['teh',[e,e]]] as const)
    assert.throws(()=>validatedEdits({suggestions:edits},text))
})
test('authenticated HTTP path, invalid inputs, quota and provider failure',async t=>{
  const token='x'.repeat(32)
  const server=service(token,async d=>{if(d.text==='fail')throw Error();return {suggestions:[e]}},4)
  server.listen(0,'127.0.0.1')
  await once(server,'listening')
  t.after(()=>server.close())
  const url='http://127.0.0.1:'+(server.address() as AddressInfo).port+'/v1/writing'
  const post=(text:string,key=token)=>fetch(url,{method:'POST',headers:{Authorization:'Bearer '+key,'Content-Type':'application/json'},body:JSON.stringify({text,action:'Fix Grammar',language:'en'})})
  assert.equal((await post('teh','wrong')).status,401)
  assert.equal((await (await post('teh')).json()).suggestions[0].replacement,'the')
  assert.equal((await post('')).status,400)
  assert.equal((await post('fail')).status,502)
  assert.equal((await post('absent')).status,502)
  assert.equal((await post('teh')).status,429)
})
