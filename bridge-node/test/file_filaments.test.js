const {test}=require('node:test'),assert=require('node:assert/strict');
const {usedSlotsFromGcode:used}=require('../file_filaments');
test('Bambu used-filament header excludes unused project presets',()=>{
 assert.deepEqual(used('; filament: 1,4,5,6\n; filament_type = PLA;PLA;PLA;PLA;PLA;PLA'),[0,3,4,5]);
 assert.deepEqual(used('; filament: 2,4,6,8\r\n'),[1,3,5,7]);
 assert.deepEqual(used('; filament: 1\n'),[0]);
});
test('body extrusion fallback excludes calibration, temperature-only tools and retractions',()=>{
 assert.deepEqual(used('M83\nT0\nG1 E10\n; MACHINE_START_GCODE_END\nT5\nM104 T3 S220\nG1 E-1\nG1 E2\nT7\nG1 E1'),[5,7]);
});
test('absolute extrusion and per-tool positions are tracked',()=>{
 assert.deepEqual(used('M82\nT1\nG92 E100\n; MACHINE_START_GCODE_END\nG1 E99\nG1 E101\nT3\nG92 E10\nG1 E9'),[1]);
});
test('project config alone is not evidence of actual filament usage',()=>{
 assert.deepEqual(used('; filament_type = PLA;PLA;PLA;PLA;PLA;PLA'),[]);
 assert.deepEqual(used('T0\nG1 E5'),[]);
});
