// Identify used logical project slots from this print, not the project library.
function usedSlotsFromGcode(content) {
  const header = content.match(/^;\s*filament:\s*([0-9,\s]+)\s*$/m);
  if (header) {
    const slots = header[1].trim().split(',').map(s => Number(s.trim()) - 1);
    if (slots.length && slots.every(s => Number.isInteger(s) && s >= 0 && s < 32))
      return [...new Set(slots)].sort((a,b) => a-b);
  }
  const lines = content.split(/\r?\n/);
  // Exclude initialization/calibration extrusion; retain initial tool/mode.
  const boundary = lines.findIndex(l => /^;\s*MACHINE_START_GCODE_END\s*$/.test(l));
  const layer = lines.findIndex(l => /^;(?:BEFORE_LAYER_CHANGE|LAYER_CHANGE|LAYER:)/.test(l));
  const body = boundary >= 0 ? boundary : layer;
  if (body < 0) return [];
  let active = null, relative = false;
  const positions = new Map(), used = new Set();
  for (let i=0; i<lines.length; i++) {
    const code = lines[i].split(';')[0].trim();
    const tool = code.match(/^T(\d+)\s*$/);
    if (tool) active = Number(tool[1]);
    if (/^M83\b/.test(code)) relative = true;
    if (/^M82\b/.test(code)) relative = false;
    const e = code.match(/\bE\s*(-?(?:\d+(?:\.\d*)?|\.\d+))/);
    if (!e || active === null) continue;
    const value = Number(e[1]);
    if (/^G92\b/.test(code)) positions.set(active,value);
    else if (/^G[0123]\b/.test(code)) {
      const previous = positions.get(active) ?? 0;
      const delta = relative ? value : value - previous;
      positions.set(active,relative ? previous+value : value);
      if (i>body && delta>0 && active>=0 && active<32) used.add(active);
    }
  }
  return [...used].sort((a,b)=>a-b);
}
module.exports = {usedSlotsFromGcode};
