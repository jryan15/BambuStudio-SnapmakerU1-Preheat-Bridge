const {test}=require('node:test'),assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm');
const mapping=require('../../bridge/web/filament_mapping');
const html=fs.readFileSync(path.resolve(__dirname,'../../bridge/web/webui.html'),'utf8');
const script=html.match(/<script>\s*([\s\S]*?)<\/script>/)[1];
test('all inline Device scripts parse',()=>{new vm.Script(script);});
test('Device screen displays sparse slots and sends manual assignments despite wrong labels',()=>{
 const alerts=[],sent=[],elements={},rendered=[];
 for(const id of ['btnDoPrint','optLevel','optFlow','optTimelapse'])elements[id]={checked:true};
 elements.sharedHeadWarning={style:{}};elements.sharedHeadSummary={};
 const ctx={U1FilamentMapping:mapping,curLang:'en',console:{log(){}},D:{},t:x=>x,escHtml:x=>String(x),
   colorDist:()=>0,alert:x=>alerts.push(x),printTaskData:{filament_type:['PETG','PETG','PETG','PETG']},
   gcodeMeta:{filament_type:'PLA;PLA;PLA;PLA;PLA;PLA;PLA;PLA',filament_colour:Array(8).fill('#FFFFFF'),bridge_used_slots:[1,3,5,7]},
   pendingFilePath:'sparse.gcode',mapRowIdx:[],filamentMap:[],FILAMENT_TYPES:['PLA','PETG'],
   document:{getElementById:id=>elements[id]||null,body:{insertAdjacentHTML:(_,s)=>rendered.push(s)}},
   bridgeGET:(p,cb)=>{if(p==='/api/bridge/pending_print')cb({filename:'sparse.gcode'});},
   bridgePOST:(p,data)=>sent.push({path:p,data})};
 vm.createContext(ctx);
 // Evaluate the real mapping/dialog code without starting WebSockets or polling.
 vm.runInContext(script.slice(script.indexOf('function extractFilType('),script.indexOf('var statusPollId=')),ctx);
 // The extracted code declares some defaults; set the selected job again.
 ctx.pendingFilePath='sparse.gcode';
 ctx.showPrintDialog('sparse.gcode',ctx.printTaskData,ctx.gcodeMeta);
 const renderedHTML=rendered.join('');
 for(const slot of [2,4,6,8])assert(renderedHTML.includes('>#'+slot+'</span>'));
 for(const slot of [1,3,5,7])assert(!renderedHTML.includes('>#'+slot+'</span>'));
 for(const head of [0,1,2,3])assert(renderedHTML.includes('selectDropdown(5,'+head+')'));
 // Manual assignments override suggestions, even though all labels say PETG.
 ctx.filamentMap[1]=3;ctx.filamentMap[3]=0;ctx.filamentMap[5]=2;ctx.filamentMap[7]=1;
 ctx.doPrint();assert.deepEqual(alerts,[]);assert.equal(sent.length,1);
 assert.deepEqual(JSON.parse(sent[0].data.extruder_map_table),[[1,3],[3,0],[5,2],[7,1]]);
 assert.equal(sent[0].data.filename,'sparse.gcode');
 ctx.filamentMap[7]=2;ctx.refreshSharedWarning();
 assert.equal(elements.sharedHeadWarning.style.display,'block');
 assert.match(elements.sharedHeadSummary.textContent,/Head 3.*#6.*#8/);
 ctx.doPrint();assert.equal(sent.length,2);assert.deepEqual(alerts,[]);
 ctx.gcodeMeta.bridge_used_slots=[0,1,2,3,4,5];ctx.gcodeMeta.bridge_pause_count=0;ctx.showPrintDialog('six.gcode',ctx.printTaskData,ctx.gcodeMeta);
 for(const slot of [1,2,3,4,5,6])assert(rendered.at(-1).includes('>#'+slot+'</span>'));
 assert(rendered.at(-1).includes('More than 4 filaments used without a pause'));
 assert(!rendered.at(-1).includes('optCombine'));
 ctx.gcodeMeta.bridge_pause_count=1;ctx.showPrintDialog('six.gcode',ctx.printTaskData,ctx.gcodeMeta);
 assert(!rendered.at(-1).includes('without a pause'));
 ctx.gcodeMeta.bridge_used_slots=[0,1,2,3];ctx.gcodeMeta.bridge_pause_count=0;ctx.showPrintDialog('four.gcode',ctx.printTaskData,ctx.gcodeMeta);
 assert(!rendered.at(-1).includes('without a pause'));
});
