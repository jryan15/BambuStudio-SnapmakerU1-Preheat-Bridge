// Installs the prepared test payload only after an idle check and exact baseline
// verification. This tool never slices a model or starts a print.
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=__dirname,payload=path.join(root,'payload');
const target=path.resolve(process.env.BRIDGE_INSTALL_TARGET||'C:/Program Files/Bambu Studio/bridge');
const bridgeURL=process.env.BRIDGE_INSTALL_URL||'http://127.0.0.1:13628';
const marker=path.join(target,'mapping-test-backup.json');
const manifest=JSON.parse(fs.readFileSync(path.join(root,'manifest.json'),'utf8'));
const hash=p=>crypto.createHash('sha256').update(fs.readFileSync(p)).digest('hex');
function within(base,relative){
 if(typeof relative!=='string'||path.isAbsolute(relative))throw Error('Invalid package path.');
 const resolved=path.resolve(base,relative);
 if(!resolved.startsWith(path.resolve(base)+path.sep))throw Error('Invalid package path.');
 return resolved;
}
async function request(suffix){const r=await fetch(bridgeURL+suffix,{headers:{Connection:'close'},signal:AbortSignal.timeout(10000)});if(!r.ok)throw Error('Cannot reach bridge/printer (HTTP '+r.status+').');return r;}
async function idleCheck(){
 const config=await(await request('/api/bridge/config')).json();
 if(![manifest.previousVersion,manifest.version].includes(config.version))throw Error('This package was prepared for bridge '+manifest.previousVersion+'; detected '+config.version+'.');
 const raw=await(await request('/api/bridge/proxy.js?cb=idlecheck&path='+encodeURIComponent('/printer/objects/query?print_stats'))).text();
 const match=raw.match(/^idlecheck\(([\s\S]*)\);?\s*$/);
 if(!match)throw Error('Cannot confirm printer state.');
 const state=JSON.parse(match[1])?.result?.status?.print_stats?.state;
 if(!['standby','complete','cancelled','error'].includes(state))throw Error('Printer must be idle (current state: '+(state||'unknown')+').');
 return config;
}
function restoreFiles(record){
 const backup=path.resolve(record.backup);
 if(!backup.startsWith(target+path.sep)||!path.basename(backup).startsWith('mapping-test-backup-'))throw Error('Invalid backup location.');
 // Check the entire backup before changing anything.
 for(const [file,original] of Object.entries(record.original)){
   if(original!==null&&(!fs.existsSync(within(backup,file))||hash(within(backup,file))!==original))throw Error('Backup checksum mismatch: '+file);
 }
 for(const [file,original] of Object.entries(record.original)){
   const dest=within(target,file);
   if(original===null){if(fs.existsSync(dest))fs.unlinkSync(dest);}
   else{fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(within(backup,file),dest);}
 }
}
async function restartAndVerify(expected){
 await request('/api/bridge/restart.js?cb=restart');
 for(let i=0;i<30;i++){
   await new Promise(r=>setTimeout(r,1000));
   try{const d=await(await request('/api/bridge/config')).json();if(d.version===expected){console.log('Verified bridge '+d.version+'. Reload the Device tab.');return;}}catch{}
 }
 throw Error('Files updated but restart was not verified. Reopen Bambu Studio and check the bridge version before printing.');
}
(async()=>{
 const config=await idleCheck();
 if(process.argv.includes('--restore')){
   if(!fs.existsSync(marker))throw Error('No mapping-test backup was found.');
   const record=JSON.parse(fs.readFileSync(marker,'utf8'));
   if(record.version!==manifest.version)throw Error('This backup belongs to a different update.');
   await idleCheck();restoreFiles(record);
   console.log('Previous files restored. Backup retained at '+record.backup);
   await restartAndVerify(record.previousVersion);return;
 }
 if(config.version===manifest.version){
   for(const [file,digest] of Object.entries(manifest.patched))if(!fs.existsSync(within(target,file))||hash(within(target,file))!==digest)throw Error('Installed test files have changed: '+file);
   console.log('This test update is already installed. Reload the Device tab.');return;
 }
 for(const [file,digest] of Object.entries(manifest.patched)){
   if(hash(within(payload,file))!==digest)throw Error('Package checksum mismatch: '+file);
   const dest=within(target,file),original=manifest.original[file];
   if(original===null?fs.existsSync(dest):!fs.existsSync(dest)||hash(dest)!==original)
     throw Error('Installed file changed since this package was prepared: '+file+'. No files were changed.');
 }
 const backup=path.join(target,'mapping-test-backup-'+new Date().toISOString().replace(/[:.]/g,'-'));
 fs.mkdirSync(backup,{recursive:true});
 for(const [file,digest] of Object.entries(manifest.original))if(digest!==null){
   const saved=within(backup,file);fs.mkdirSync(path.dirname(saved),{recursive:true});fs.copyFileSync(within(target,file),saved);
 }
 const record={backup,previousVersion:config.version,version:manifest.version,original:manifest.original};
 fs.writeFileSync(path.join(backup,'record.json'),JSON.stringify(record,null,2));
 await idleCheck();
 try{
   // Source server stays running until the complete payload is in place.
   const files=Object.keys(manifest.patched).sort((a,b)=>(a==='server.js')-(b==='server.js'));
   for(const file of files){const dest=within(target,file);fs.mkdirSync(path.dirname(dest),{recursive:true});fs.copyFileSync(within(payload,file),dest);}
   fs.writeFileSync(marker,JSON.stringify(record,null,2));
   await idleCheck();
 }catch(e){restoreFiles(record);throw e;}
 console.log('Update installed. Previous files backed up at '+backup);
 await restartAndVerify(manifest.version);
})().catch(e=>{console.error('\n'+e.message);process.exitCode=1;});
