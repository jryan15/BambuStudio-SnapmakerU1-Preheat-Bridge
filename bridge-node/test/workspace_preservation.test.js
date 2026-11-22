const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('fs'),os=require('os'),path=require('path');
test('AI workspace initialization respects isolation and preserves user edits',()=>{
 const dir=fs.mkdtempSync(path.join(os.tmpdir(),'u1-workspace-'));
 const old=process.env.BRIDGE_CONFIG_DIR;process.env.BRIDGE_CONFIG_DIR=dir;
 try{
  const agent=require('../slice_agent');
  const work=path.join(dir,'ai-lab','workspace');
  assert(fs.existsSync(path.join(work,'soul.md')));
  fs.writeFileSync(path.join(work,'soul.md'),'User identity');
  fs.writeFileSync(path.join(work,'skills','print_qa.md'),'User skill');
  fs.unlinkSync(path.join(work,'knowledge.md'));
  agent.setAppDataDir(path.join(dir,'ai-lab'));
  assert.equal(fs.readFileSync(path.join(work,'soul.md'),'utf8'),'User identity');
  assert.equal(fs.readFileSync(path.join(work,'skills','print_qa.md'),'utf8'),'User skill');
  assert(fs.existsSync(path.join(work,'knowledge.md')));
 }finally{if(old===undefined)delete process.env.BRIDGE_CONFIG_DIR;else process.env.BRIDGE_CONFIG_DIR=old;fs.rmSync(dir,{recursive:true,force:true});}
});
