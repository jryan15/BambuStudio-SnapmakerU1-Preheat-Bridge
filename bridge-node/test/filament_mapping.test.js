const {test}=require('node:test');
const assert=require('node:assert/strict');
const mapping=require('../../bridge/web/filament_mapping');
test('only used slots appear, including project slots 2,4,6,8',()=>{
 assert.deepEqual(mapping.usedSlots({filament_type:'PLA;PLA;PLA;PLA;PLA;PLA;PLA;PLA',filament_used_mm:'0;10;0;20;0;30;0;40'}),[1,3,5,7]);
});
test('weight usage is supported; project presets alone are never treated as used',()=>{
 assert.deepEqual(mapping.usedSlots({filament_type:['PLA','PLA','PLA'],filament_weight:[0,0,2]}),[2]);
 assert.deepEqual(mapping.usedSlots({filament_type:['PLA','PLA']}),[]);
 assert.deepEqual(mapping.usedSlots({filament_type:Array(8).fill('PLA'),bridge_used_slots:[1,3,5,7]}),[1,3,5,7]);
});
test('suggestions stay unique when no printer labels match',()=>{
 const slots=[1,3,5,7], suggested=mapping.suggest(slots,()=>1000);
 assert.deepEqual(slots.map(i=>suggested[i]),[0,1,2,3]);
 assert.doesNotThrow(()=>mapping.validate([[1,3],[3,0],[5,2],[7,1]],slots));
});
test('suggestions prefer requested ranking without stealing already assigned heads',()=>{
 const suggested=mapping.suggest([1,5],(slot,head)=>head===2?0:100);
 assert.equal(suggested[1],2);assert.equal(suggested[5],0);
});
test('missing and out-of-range assignments fail',()=>{
 for(const table of [[[1,0]],[[1,0],[5,4]],[[1,0],[3,1]],[[1,0],[5,'1']]])
   assert.throws(()=>mapping.validate(table,[1,5]));
 assert.doesNotThrow(()=>mapping.validate([[0,0],[1,1],[2,2],[3,3],[4,0]],[0,1,2,3,4]));
 assert.throws(()=>mapping.validate([],[]),/unavailable/);
});
test('six used colors may share four heads without an extra acknowledgment',()=>{
 const slots=[0,1,2,3,4,5],suggested=mapping.suggest(slots,()=>100);
 assert.deepEqual(slots.map(i=>suggested[i]),[0,1,2,3,0,0]);
 const table=[[0,0],[1,1],[2,2],[3,3],[4,0],[5,1]];
 assert.doesNotThrow(()=>mapping.validate(table,slots,true));
 assert.deepEqual(mapping.sharedHeads(table),[{head:0,slots:[0,4]},{head:1,slots:[1,5]}]);
 assert.throws(()=>mapping.validate([[0,0],[0,1]], [0,1],true),/match this plate/);
});
