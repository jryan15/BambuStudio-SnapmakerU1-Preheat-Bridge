const {test}=require('node:test'),assert=require('node:assert/strict');
const {prepareSharedPrint}=require('../shared_preheat');
const {processUpload,verifyPreheats}=require('../advance_preheat');
function fixture(){return [
 '; HEADER_BLOCK_START','; BambuStudio 02.08.02.61','; filament: 1,2,3,4,5,6','; HEADER_BLOCK_END',
 '; CONFIG_BLOCK_START','; CONFIG_BLOCK_END','; EXECUTABLE_BLOCK_START',
 'G90','M83','T0','; MACHINE_START_GCODE_END','G1 X0 Y0 F600','G1 X500 E5',
 ...[1,2,3,4,5,0].flatMap((tool,i)=>[
   `M104 S70 T${[0,1,2,3,4,5][i]} ; cooldown previous extruder`,
   'G91','G1 Z1.5 F1800','G90','G1 F21000',`M109 S${tool===4?230:220} T${tool}`,
   'M400',`T${tool}`,`SM_PRINT_PREEXTRUDE_FILAMENT INDEX=${tool}`,
   'G1 X0 Y0 F600','G1 X500 E5']),
 'PRINT_END','; EXECUTABLE_BLOCK_END'].join('\n');}
const table=[[0,0],[1,0],[2,1],[3,2],[4,0],[5,3]];
test('shared aliases avoid cooldown and schedule temperature changes only after printing',()=>{
 const original=fixture(),uploaded=processUpload(original).content;
 assert.throws(()=>verifyPreheats(uploaded,new Map(table)),/still extruding|cancelled/);
 const result=prepareSharedPrint(uploaded,table,{});
 assert.equal(result.report.switches,6);assert.equal(result.report.skippedCooldowns,1);
 assert.equal(verifyPreheats(result.content,new Map(table)),6);
 assert.match(result.content,/; U1_SHARED_COOLDOWN M104 S70 T0/);
 assert.match(result.content,/M104 S220 T1 ; U1_ADVANCE_PREHEAT[^\r\n]*\r\nM109 S220 T1/);
 const restore=s=>s.split(/\r?\n/).filter(l=>!l.includes('; U1_ADVANCE_PREHEAT') && l!=='; U1_SHARED_SCHEDULE').map(l=>l.replace(/^; U1_SHARED_COOLDOWN /,''));
 assert.deepEqual(restore(result.content),restore(original));
 assert.equal(prepareSharedPrint(result.content,table,{}).content,result.content);
});
test('changed mapping restores cooldowns and regenerates its original logical commands',()=>{
 const combined=prepareSharedPrint(fixture(),table,{}).content;
 const remapped=[[0,0],[1,1],[2,2],[3,3],[4,0],[5,1]];
 const changed=prepareSharedPrint(combined,remapped,{});
 assert(!changed.content.includes('; U1_SHARED_COOLDOWN'));
 assert.match(changed.content,/^M104 S70 T0 ; cooldown previous extruder/m);
 assert.equal(verifyPreheats(changed.content,new Map(remapped)),6);
});
test('disabled advance heating still avoids shared cooldown and preserves waits',()=>{
 const result=prepareSharedPrint(processUpload(fixture()).content,table,{enabled:false});
 assert(!result.content.includes('U1_ADVANCE_PREHEAT'));
 assert.equal((result.content.match(/^M109 /gm)||[]).length,6);
 assert.equal(result.report.skippedCooldowns,1);
});
test('unknown profiles and ambiguous cooldown blocks are not optimized',()=>{
 assert.throws(()=>prepareSharedPrint(fixture().replace('; BambuStudio','; OrcaSlicer'),table,{}),/Bambu U1/);
 const altered=fixture().replace('G91\nG1 Z1.5','G1 E2\nG91\nG1 Z1.5');
 assert.equal(prepareSharedPrint(altered,table,{}).report.skippedCooldowns,0);
});
test('shared-head preparation preserves pauses with heating enabled or disabled',()=>{
 const source=fixture().replace('M109 S230 T4','PAUSE ; swap two filaments\nM109 S230 T4');
 for(const enabled of [true,false]){
  const result=prepareSharedPrint(source,table,{enabled});
  assert.match(result.content,/PAUSE ; swap two filaments\r\n/);
  if(enabled){
   assert(result.content.indexOf('M104 S230 T4 ; U1_ADVANCE_PREHEAT')>result.content.indexOf('PAUSE ;'));
   assert.equal(verifyPreheats(result.content,new Map(table)),6);
  }else assert(!result.content.includes('; U1_ADVANCE_PREHEAT'));
 }
});
test('same-head temperature change preserves the requested wait and prevents early temperature change',()=>{
 const source=fixture().replace('M109 S220 T1','M109 S240 T1');
 const result=prepareSharedPrint(source,table,{});
 assert.match(result.content,/M104 S240 T1 ; U1_ADVANCE_PREHEAT[^\r\n]*\r\nM109 S240 T1/);
 assert.equal(verifyPreheats(result.content,new Map(table)),6);
});
module.exports={fixture,table};
