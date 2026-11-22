// DOM/script integration test. Not a visual browser test; uses a simulated printer.
const {JSDOM,VirtualConsole,ResourceLoader}=require(process.env.JSDOM_PATH||'jsdom');
const {WebSocket}=require('../../bridge-node/node_modules/ws');
const assert=require('node:assert/strict'),fs=require('fs');
const base='http://127.0.0.1:14628',errors=[],alerts=[];let win;
class Loader extends ResourceLoader{fetch(url,options){if(url===base+'/fluidd/')return Promise.resolve(Buffer.from('<title>Fluidd separately HTTP-tested</title>'));return super.fetch(url,options)}}
const delay=ms=>new Promise(r=>setTimeout(r,ms));
(async()=>{
const vc=new VirtualConsole();vc.on('jsdomError',e=>{if(!e.message.includes('Not implemented'))errors.push(e.message)});
const dom=await JSDOM.fromURL(base,{resources:new Loader(),runScripts:'dangerously',pretendToBeVisual:true,virtualConsole:vc,beforeParse(w){w.WebSocket=WebSocket;w.fetch=(url,opts)=>fetch(new URL(url,base),opts);w.alert=m=>alerts.push(m);w.confirm=()=>false;w.HTMLCanvasElement.prototype.getContext=()=>null;}});win=dom.window;
await delay(1600);assert.equal(win.curLang,'en');assert.equal(win.document.documentElement.lang,'en');
const result=[];
for(const tab of ['device','fluidd','debug','ailab','gcvt','about']){
win.document.querySelector('[data-tab="'+tab+'"]').click();await delay(300);
assert.notEqual(win.document.getElementById(tab+'-content').style.display,'none');
result.push({tab,loaded:true,text:win.document.getElementById(tab+'-content').textContent.trim().slice(0,180)});
}
assert.equal(win.cmpVer('5.48.0-u1.3','5.48.0-u1.4-test.5'),-1);
assert.equal(win.cmpVer('5.48.0-u1.4','5.48.0-u1.4-test.5'),1);
assert.equal(win.cmpVer('5.48.0-u1.4-test.10','5.48.0-u1.4-test.5'),1);
assert.equal(win.cmpVer('garbage','5.48.0'),null);
win.switchTab('debug');win.toggleDebugAuto();assert.ok(win.dbgAutoInterval);win.switchTab('device');assert.equal(win.dbgAutoInterval,null);
win.switchTab('gcvt');win.gcvtConvert();assert.match(alerts.pop(),/select a G-code/i);
win.setLang('zh');assert.equal(win.document.documentElement.lang,'zh-CN');win.setLang('en');assert.equal(win.document.documentElement.lang,'en');
assert.equal(win.document.querySelector('#debug-content').style.flexDirection,'column');
assert.match(win.document.querySelector('#about-content').textContent,/jryan15/);
assert.match(win.document.querySelector('#about-content').textContent,/SETUP.bat/);
// Device controls send to the simulated loopback printer only.
win.switchTab('device');win.document.getElementById('t0Set').value='200';win.setToolTemp(0);
win.document.getElementById('bedSet').value='55';win.setBedTemp();win.setLight(true);win.setSpeed(80);await delay(200);
const calls=await (await fetch('http://127.0.0.1:14629/audit-calls')).json();
for(const method of ['printer.control.extruder_temp','printer.control.bed_temp','printer.control.led','printer.control.print_speed'])assert.ok(calls.some(c=>c.method===method),method);
win.switchTab('ailab');win.aiCfg={provider:'unconfigured',apiKey:''};win.aiOptimizeGcode();assert.notEqual(win.document.getElementById('aiErrorModal').style.display,'none');win.hideAiError();
// Verify the real console assets independently of jsdom's lack of module rendering.
const html=await (await fetch(base+'/fluidd/')).text();const asset=html.match(/src="(\.\/assets\/[^" ]+)"/)[1];assert.equal((await fetch(base+'/fluidd/'+asset.slice(2))).status,200);
assert.deepEqual((await (await fetch(base+'/fluidd/config.json')).json()).endpoints,[base]);
assert.equal((await fetch(base+'/api/bridge/debug/export')).status,200);
const ts=await fetch(base+'/api/bridge/tailscale_status.js?cb=callback');assert.equal(ts.status,200);assert.match(await ts.text(),/^callback\(/);win.showPrinterConfig();await delay(250);assert.ok(win.document.getElementById('cfgHost'));win.closePrinterConfig();assert.equal(win.document.getElementById('printerConfigModal'),null);
const sample=['; HEADER_BLOCK_START','; BambuStudio audit fixture','; HEADER_BLOCK_END','; EXECUTABLE_BLOCK_START','M104 T2 S140','M140 S60','T2','PRINT_START','; EXECUTABLE_BLOCK_END','; MACHINE_START_GCODE_END',';BEFORE_LAYER_CHANGE',';LAYER:0','; FEATURE: Outer Wall','G1 X100 Y100 E1 F1800','PRINT_END','M104 S0','M140 S0'].join('\n');
const form=new FormData();form.append('gcode',new Blob([sample]),'audit.gcode');
const uploaded=await (await fetch(base+'/api/ai/upload_gcode',{method:'POST',body:form})).json();assert.equal(uploaded.ok,true);
const convertedText=await (await fetch(base+'/api/ai/convert_gcode.js?cb=callback&gcode_name='+encodeURIComponent(uploaded.gcode_name))).text();
const converted=JSON.parse(convertedText.slice('callback('.length,-2));assert.equal(converted.ok,true);assert.equal(converted.info.first_tool,2);
const convertedFile=await (await fetch(base+'/api/ai/download_gcode?gcode_name='+encodeURIComponent(converted.converted_gcode_name))).text();assert.match(convertedFile,/;TYPE:/);
const originalFile=await (await fetch(base+'/api/ai/download_gcode?gcode_name='+encodeURIComponent(uploaded.gcode_name))).text();assert.equal(originalFile,sample);
// No detached callbacks or tab scripts should throw.
assert.deepEqual(errors,[]);
console.log(JSON.stringify({result,errors,checks:'six tabs; simulated temperature/light/speed commands; settings modal; AI unconfigured guard; upload/convert/download preserving original; Console HTTP assets; Debug export; English default, language toggle, debug timer lifecycle, empty Convert guard, revision comparison, About ownership'},null,2));
})().catch(e=>{console.error(e);process.exitCode=1}).finally(()=>{if(win){if(win.ws){win.ws.onclose=null;win.ws.onerror=null;win.ws.onmessage=null;win.ws.close();}win.close()}setTimeout(()=>process.exit(process.exitCode||0),100)});
