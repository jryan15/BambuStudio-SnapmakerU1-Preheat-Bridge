// Exercises the real bridge and browser against a loopback-only simulated printer.

const {WebSocketServer}=require('../../bridge-node/node_modules/ws');
const fs=require('fs'),os=require('os'),path=require('path'),http=require('http'),{spawn}=require('child_process');
const root=path.resolve(__dirname,'../..'),tmp=fs.mkdtempSync(path.join(os.tmpdir(),'u1-ui-audit-'));
const output=process.env.AUDIT_OUTPUT||path.join(tmp,'screenshots');fs.mkdirSync(output,{recursive:true});
const status={toolhead:{position:[0,0,0],homed_axes:'xyz',extruder:'extruder'},heater_bed:{temperature:25,target:0},print_stats:{state:'standby',filename:'',print_duration:0,total_duration:0,filament_used:0},display_status:{progress:0},gcode_move:{speed_factor:1,extrude_factor:1},fan:{speed:0},'fan_generic cavity_fan':{speed:0},'led cavity_led':{color_data:[[0,0,0,0]]},virtual_sdcard:{progress:0,is_active:false},motion_report:{live_velocity:0},idle_timeout:{state:'Ready'},machine_state_manager:{},filament_parameters:{}};
for(let i=0;i<4;i++)status['extruder'+(i||'')]={temperature:25,target:0,power:0};
const calls=[];
const mock=http.createServer((req,res)=>{calls.push(req.url);res.setHeader('Content-Type','application/json');let result={};if(req.url==='/audit-calls'){res.end(JSON.stringify(calls));return;}
if(req.url.includes('objects/query'))result={status,eventtime:1};
else if(req.url.includes('/server/info'))result={klippy_connected:true,klippy_state:'ready',components:['file_manager'],failed_components:[],warnings:[]};
else if(req.url.includes('/printer/info'))result={state:'ready',state_message:'Ready',hostname:'Audit mock'};
else if(req.url.includes('files/list'))result=[];
res.end(JSON.stringify({result}));});
const wss=new WebSocketServer({server:mock});wss.on('connection',ws=>ws.on('message',raw=>{const m=JSON.parse(raw);calls.push(m);ws.send(JSON.stringify({jsonrpc:'2.0',id:m.id,result:m.method.includes('objects')?{status,eventtime:1}:{}}));}));
let bridge,browser;
(async()=>{await new Promise(r=>mock.listen(14629,'127.0.0.1',r));
fs.writeFileSync(path.join(tmp,'bridge_config.json'),JSON.stringify({host:'127.0.0.1',port:14629}));
bridge=spawn(process.execPath,['bridge-node/server.js'],{cwd:root,env:{...process.env,BRIDGE_PORT:'14628',BRIDGE_CONFIG_DIR:tmp},stdio:'ignore'});
for(let i=0;i<50;i++){try{if((await fetch('http://127.0.0.1:14628/api/bridge/config')).ok)break}catch{}await new Promise(r=>setTimeout(r,100))}
if(process.env.AUDIT_DOM){await new Promise((resolve,reject)=>{const child=spawn(process.execPath,['tools/audit/dom-audit.cjs'],{cwd:root,env:process.env,stdio:'inherit'});child.on('exit',code=>code?reject(Error('DOM audit failed')):resolve());});return;}
if(process.env.AUDIT_SERVE){console.log('Mock printer and bridge ready on 14628');await new Promise(()=>{});}
const {chromium}=require('playwright');
browser=await chromium.launch({executablePath:process.env.CHROMIUM_PATH||'/usr/bin/chromium',headless:true,args:['--no-sandbox']});
const page=await browser.newPage({viewport:{width:1280,height:900}}),errors=[],missing=[];
page.on('pageerror',e=>errors.push(e.message));page.on('response',r=>{if(r.status()>=400&&r.url().startsWith('http://127.0.0.1:14628/'))missing.push([r.status(),r.url()])});
await page.goto('http://127.0.0.1:14628');await page.waitForTimeout(1500);
const initialLang=await page.evaluate(()=>curLang);await page.evaluate(()=>setLang('en'));
const results=[];
for(const tab of ['device','fluidd','debug','ailab','gcvt','about']){
await page.click('[data-tab="'+tab+'"]');await page.waitForTimeout(tab==='fluidd'?2000:500);
const box=await page.locator('#'+tab+'-content').boundingBox();const text=await page.locator('#'+tab+'-content').innerText();
results.push({tab,visible:!!box,width:box?.width,height:box?.height,text:text.slice(0,1100)});
await page.screenshot({path:path.join(output,tab+'.png')});}
console.log(JSON.stringify({initialLang,errors,missing,results,output},null,2));
fs.writeFileSync(path.join(output,'audit.json'),JSON.stringify({initialLang,errors,missing,results},null,2));
})().catch(e=>{console.error(e);process.exitCode=1}).finally(async()=>{if(browser)await browser.close();if(bridge)bridge.kill();for(const c of wss.clients)c.terminate();wss.close();mock.close();fs.rmSync(tmp,{recursive:true,force:true});});
