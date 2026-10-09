// Only loopback mock services; never contacts or starts a real printer.
const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),os=require('node:os'),http=require('node:http');
const {spawn}=require('node:child_process');
const {WebSocketServer}=require('ws');
const {processUpload,verifyPreheats}=require('../advance_preheat');
const listen=s=>new Promise(r=>s.listen(0,'127.0.0.1',r));
const delay=ms=>new Promise(r=>setTimeout(r,ms));
function fixture(){return [
 '; HEADER_BLOCK_START','; BambuStudio 02.08.02.61','; total filament length [mm] : 0,100,0,100,0,100,0,100','; total filament weight [g] : 0,0.3,0,0.3,0,0.3,0,0.3','; HEADER_BLOCK_END',
 '; CONFIG_BLOCK_START','; filament_type = PLA;PLA;PLA;PLA;PLA;PLA;PLA;PLA','; CONFIG_BLOCK_END',
 '; EXECUTABLE_BLOCK_START','PRINT_START','G90','M83','T1','SM_PRINT_CHECK_SWITCH_EXTRUDER','; MACHINE_START_GCODE_END',
 '; FEATURE: Outer wall','G1 X0 Y0 F600','G1 X500 E5',
 'M104 S70 T1 ; cooldown previous extruder','M109 S220 T3','T3','G1 X0 Y0 F600','G1 X500 E5',
 'M104 S70 T3 ; cooldown previous extruder','M109 S230 T5','T5','G1 X0 Y0 F600','G1 X500 E5',
 'M104 S70 T5 ; cooldown previous extruder','M109 S225 T7','T7','G1 X0 Y0 F600','G1 X500 E5',
 'PRINT_END','; EXECUTABLE_BLOCK_END'].join('\n');}
test('upload, settings, sparse manual mapping, cancellation and both API forms',async()=>{
 const temp=fs.mkdtempSync(path.join(os.tmpdir(),'u1-bridge-test-'));
 const requests=[],calls=[],uploads=[];let child,log='',failStart=false,failFile=false,failUpload=false,meta,fileContent=fixture(),preparedFile=null,preparedReply='normal';
 const resetMeta=()=>meta={filament_type:'PLA;PLA;PLA;PLA;PLA;PLA;PLA;PLA'};
 resetMeta();
 const mock=http.createServer(async(req,res)=>{
   requests.push(req.url);res.setHeader('Content-Type','application/json');
   if(req.url==='/server/files/upload'){
     let parts=[];for await(const p of req)parts.push(p);uploads.push(Buffer.concat(parts).toString());
     if(failUpload){res.statusCode=500;res.end('{}');return;}
     const body=uploads.at(-1),start=body.indexOf('\r\n\r\n',body.indexOf('filename="'))+4;
     const gcode=body.slice(start,body.indexOf('\r\n--',start));
     preparedFile=gcode.includes('; U1_SHARED_SCHEDULE')?gcode:null;
     if(!preparedFile) fileContent=gcode;
     if(preparedFile){
       if(preparedReply==='missing'){res.end(JSON.stringify({result:{}}));return;}
       if(preparedReply==='renamed'){res.end(JSON.stringify({result:{item:{path:'gcodes/uploaded_123_Epic Jaban (test).gcode'}}}));return;}
       if(preparedReply==='top-level'){res.end(JSON.stringify({item:{path:'sparse.gcode'}}));return;}
       if(preparedReply==='invalid'){res.end(JSON.stringify({result:{item:{path:'../other.gcode'}}}));return;}
     }
     res.end(JSON.stringify({result:{item:{path:'sparse.gcode'}}}));
   }else if(req.url.startsWith('/server/files/gcodes/')){if(failFile){res.statusCode=404;res.end('{}');}else res.end(preparedReply==='mismatch'?fileContent:preparedFile||fileContent);}
   else if(req.url.startsWith('/server/files/metadata?'))res.end(JSON.stringify({result:meta}));
   else res.end(JSON.stringify({result:{}}));
 });
 const wss=new WebSocketServer({server:mock,path:'/websocket'});
 wss.on('connection',ws=>ws.on('message',data=>{
   const msg=JSON.parse(data);calls.push(msg);
   ws.send(JSON.stringify(failStart&&msg.method==='printer.print.start'
     ? {id:msg.id,error:{message:'simulated start failure'}} : {id:msg.id,result:'ok'}));
 }));
 try{
   await listen(mock);const probe=http.createServer();await listen(probe);const port=probe.address().port;await new Promise(r=>probe.close(r));
   fs.writeFileSync(path.join(temp,'bridge_config.json'),JSON.stringify({host:'127.0.0.1',port:mock.address().port}));
   const entry=process.env.BRIDGE_TEST_ENTRY||path.resolve(__dirname,'../server.js');
   child=spawn(process.execPath,[entry],{env:{...process.env,APPDATA:temp,XDG_CONFIG_HOME:temp,BRIDGE_CONFIG_DIR:temp,BRIDGE_PORT:String(port)},stdio:['ignore','pipe','pipe']});
   child.stdout.on('data',b=>log+=b);child.stderr.on('data',b=>log+=b);
   const url='http://127.0.0.1:'+port;
   let ready=false;for(let i=0;i<100;i++){try{if((await fetch(url+'/api/bridge/config')).ok){ready=true;break;}}catch{}await delay(50);}
   assert(ready,'Bridge startup failed: '+log);
   const upload=async(content,print=true)=>{const form=new FormData();form.append('file',new Blob([content]),'sparse.gcode');form.append('print',String(print));return fetch(url+'/api/files/local',{method:'POST',body:form});};
   const post=(route,data)=>fetch(url+route,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(data)});
   const pending=async()=>await(await fetch(url+'/api/bridge/pending_print')).json();
   const table=[[1,3],[3,0],[5,2],[7,1]],opts={filename:'sparse.gcode',extruder_map_table:JSON.stringify(table),auto_bed_leveling:true,flow_calibrate:false,time_lapse_camera:true};
   let r=await upload(fixture());assert.equal(r.status,200,await r.text());
   assert.equal(uploads.length,1);assert.equal((uploads[0].match(/U1_ADVANCE_PREHEAT/g)||[]).length,0);
   assert(uploads[0].includes('; U1_TOUCHSCREEN_FORMAT v3'));assert(uploads[0].includes(';TYPE:Outer wall'));
   assert(uploads[0].includes('M109 S230 T5'));assert(uploads[0].indexOf('; CONFIG_BLOCK_START')>uploads[0].indexOf('PRINT_END'));
   assert.equal((await pending()).filename,'sparse.gcode');assert.equal(calls.length,0,'Upload must not start printing');
   r=await fetch(url+'/api/bridge/print_filaments.js?cb=done&path=sparse.gcode');
   const info=JSON.parse((await r.text()).slice(5,-2));assert.deepEqual(info.result.bridge_used_slots,[1,3,5,7]);
   for(const bad of [[[1,0]],[[1,0],[3,1],[5,2],[7,4]]]){
     r=await post('/api/bridge/confirm_print',{...opts,extruder_map_table:JSON.stringify(bad)});assert.equal(r.status,422);assert.equal(calls.length,0);assert.equal((await pending()).filename,'sparse.gcode');
   }
   r=await post('/api/bridge/confirm_print',{...opts,filename:'old.gcode'});assert.equal(r.status,409);assert.equal(calls.length,0);
   r=await post('/api/bridge/confirm_print',opts);assert.equal(r.status,200,await r.text());
   assert.deepEqual(calls.filter(c=>c.method==='printer.gcode.script').map(c=>c.params.script),[
     'SET_PRINT_EXTRUDER_MAP CONFIG_EXTRUDER=1 MAP_EXTRUDER=3','SET_PRINT_EXTRUDER_MAP CONFIG_EXTRUDER=3 MAP_EXTRUDER=0',
     'SET_PRINT_EXTRUDER_MAP CONFIG_EXTRUDER=5 MAP_EXTRUDER=2','SET_PRINT_EXTRUDER_MAP CONFIG_EXTRUDER=7 MAP_EXTRUDER=1',
     'SET_PRINT_USED_EXTRUDERS EXTRUDERS=0,1,2,3','SET_PRINT_PREFERENCES BED_LEVEL=1 FLOW_CALIBRATE=0 TIME_LAPSE_CAMERA=1']);
   assert.deepEqual(calls.at(-1).params,{filename:'sparse.gcode'});assert.equal((await pending()).filename,'');
   assert(!calls.some(c=>/FILAMENT_CONFIG|FILAMENT_TYPE/.test(c.params.script||'')),'Printer filament labels must not be overwritten');
   r=await upload(fixture());assert.equal(r.status,200);failStart=true;
   r=await post('/api/bridge/confirm_print',opts);assert.equal(r.status,422);assert.equal((await pending()).filename,'sparse.gcode');failStart=false;
   const qs=new URLSearchParams({...opts,cb:'done',auto_bed_leveling:'1',flow_calibrate:'0',time_lapse_camera:'1'});
   r=await fetch(url+'/api/bridge/confirm_print.js?'+qs);assert.match(await r.text(),/"started":true/);
   r=await upload(fixture());assert.equal(r.status,200);const before=calls.length;
   await post('/api/bridge/cancel_pending',{});assert.equal((await pending()).filename,'');assert.equal(calls.length,before);
   const rejectedCount=uploads.length;r=await upload(fixture()+'\nT32');assert.equal(r.status,422);assert.equal(uploads.length,rejectedCount);
   r=await fetch(url+'/api/bridge/save_config.js?cb=done&host=127.0.0.1&port='+mock.address().port+'&preheat_enabled=false&preheat_seconds=40');assert.match(await r.text(),/"ok":true/);
   r=await upload(fixture(),false);assert.equal(r.status,200);assert(!uploads.at(-1).includes('U1_ADVANCE_PREHEAT'));
   r=await fetch(url+'/api/bridge/save_config.js?cb=done&host=127.0.0.1&preheat_enabled=true&preheat_seconds=999');assert.match(await r.text(),/"ok":false/);
   assert.equal(JSON.parse(fs.readFileSync(path.join(temp,'bridge_config.json'))).advanceHeating.enabled,false);
   // Upload-only strips prior schedules because touchscreen head choices are unknown.
   r=await upload(processUpload(fixture()).content,false);assert.equal(r.status,200);assert(!uploads.at(-1).includes('U1_ADVANCE_PREHEAT'));
   assert(uploads.at(-1).includes('; U1_TOUCHSCREEN_FORMAT v3'));
   failFile=true;const n=calls.length;r=await post('/api/bridge/start_print',{...opts,path:'sparse.gcode'});assert.equal(r.status,422);assert.equal(calls.length,n);failFile=false;resetMeta();
   r=await post('/api/bridge/start_print',{...opts,path:'sparse.gcode'});assert.equal(r.status,200);
   const asset=await fetch(url+'/filament_mapping.js');assert.equal(asset.status,200);assert.match(await asset.text(),/U1FilamentMapping/);
   // Six actual used filaments, including a same-physical-head transition.
   fileContent=fixture().replace('PRINT_END',[
     'M104 S70 T7 ; cooldown previous extruder','PAUSE ; replace two spools','M109 S220 T9','T9','G1 X0 Y0 F600','G1 X500 E5',
     'M104 S70 T9 ; cooldown previous extruder','M109 S240 T11','T11','G1 X0 Y0 F600','G1 X500 E5','PRINT_END'].join('\n'));
   fileContent=fileContent.replace('0,100,0,100,0,100,0,100','0,100,0,100,0,100,0,100,0,100,0,100').replace('0,0.3,0,0.3,0,0.3,0,0.3','0,0.3,0,0.3,0,0.3,0,0.3,0,0.3,0,0.3');
   const shared=[[1,0],[3,0],[5,1],[7,2],[9,3],[11,1]];
   const sharedOpts={...opts,extruder_map_table:JSON.stringify(shared)};
   r=await fetch(url+'/api/bridge/save_config.js?cb=done&host=127.0.0.1&port='+mock.address().port+'&preheat_enabled=true&preheat_seconds=30');assert.match(await r.text(),/"ok":true/);
   r=await upload(fileContent);assert.equal(r.status,200,await r.text());
   const commandCount=calls.length,uploadCount=uploads.length;
   r=await fetch(url+'/api/bridge/print_filaments.js?cb=done&path=sparse.gcode');
   assert.equal(JSON.parse((await r.text()).slice(5,-2)).result.bridge_pause_count,1);
   failUpload=true;r=await post('/api/bridge/confirm_print',sharedOpts);
   assert.equal(r.status,422);assert.equal(calls.length,commandCount);assert.equal((await pending()).filename,'sparse.gcode');
   failUpload=false;r=await post('/api/bridge/confirm_print',sharedOpts);
   assert.equal(r.status,200,await r.text());assert.equal(uploads.length,uploadCount+2);
   assert.equal(verifyPreheats(uploads.at(-1),new Map(shared)),5);
   assert.match(uploads.at(-1),/PAUSE ; replace two spools/);
   assert(uploads.at(-1).indexOf('M104 S240 T11 ; U1_ADVANCE_PREHEAT')>uploads.at(-1).indexOf('PAUSE ;'));
   assert.match(uploads.at(-1),/; U1_SHARED_COOLDOWN M104 S70 T1/);
   assert.equal(calls.at(-1).method,'printer.print.start');
   assert(calls.slice(commandCount).some(c=>c.params.script==='SET_PRINT_USED_EXTRUDERS EXTRUDERS=0,1,2,3'));
   assert.equal((await pending()).filename,'');
   r=await fetch(url+'/api/ai/check_gcode_format.js?cb=done&path=sparse.gcode');
   assert.match(await r.text(),/"format":"prepared"/);
   for(const variant of ['renamed','missing','top-level','invalid','mismatch']){
     preparedReply='normal';r=await upload(fileContent);assert.equal(r.status,200);
     preparedReply=variant;const count=calls.length;
     r=await post('/api/bridge/confirm_print',sharedOpts);
     if(['invalid','mismatch'].includes(variant)){
       assert.equal(r.status,422,variant);assert.equal(calls.length,count);
       assert.equal((await pending()).filename,'sparse.gcode');
     }else{
       assert.equal(r.status,200,await r.text());
       assert.equal(calls.at(-1).params.filename,variant==='renamed'?'uploaded_123_Epic Jaban (test).gcode':'sparse.gcode');
       if(variant==='renamed')assert(requests.includes('/server/files/gcodes/uploaded_123_Epic%20Jaban%20(test).gcode'));
     }
   }
   preparedReply='normal';preparedFile=null;
   // Returning a previously prepared file to unique assignments restores cooldown.
   // Use a two-color file so a genuinely unique mapping fits four heads.
   fileContent=fixture().split('M104 S70 T3')[0]+'PRINT_END\n; EXECUTABLE_BLOCK_END';
   const {prepareSharedPrint}=require('../shared_preheat');
   fileContent=prepareSharedPrint(fileContent,[[1,0],[3,0]],{}).content;
   r=await post('/api/bridge/start_print',{...opts,path:'sparse.gcode',extruder_map_table:JSON.stringify([[1,0],[3,1]])});
   assert.equal(r.status,200,await r.text());assert(!uploads.at(-1).includes('; U1_SHARED_COOLDOWN'));
 }finally{
   if(child){child.kill();await new Promise(r=>child.once('exit',r));}
   for(const ws of wss.clients)ws.terminate();await new Promise(r=>wss.close(r));mock.closeAllConnections();await new Promise(r=>mock.close(r));
   fs.rmSync(temp,{recursive:true,force:true});
 }
});
