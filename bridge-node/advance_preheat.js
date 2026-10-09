// Deterministic postprocessor for BambuStudio's Snapmaker U1 profile.
// No network, file I/O, or printer control. Call before forwarding an upload.
const MARKER = '; U1_ADVANCE_PREHEAT';
const isBambuU1 = content => /^; (?:BambuStudio\b|U1 source slicer: Bambu Studio\b)/m.test(content);
const isPause = code => /^(?:PAUSE|M600|M0|M1)\b/.test(code);
const countPauses = content => content.split(/\r?\n/).filter(line=>isPause(line.split(';')[0].trim())).length;
function normalizeOptions(value = {}) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) throw Error('Invalid advance-heating settings.');
  const enabled = value.enabled === undefined ? true : value.enabled;
  const leadSeconds = value.leadSeconds === undefined ? 30 : value.leadSeconds;
  if (typeof enabled !== 'boolean') throw Error('Advance heating enabled must be true or false.');
  if (!Number.isFinite(leadSeconds) || leadSeconds < 5 || leadSeconds > 120) throw Error('Heating lead must be 5–120 seconds.');
  return {enabled, leadSeconds};
}
function verifyPreheats(content, toolMap = null) {
  const key = (tool, p = {}) => toolMap && p.A !== 0 ? (toolMap.get(tool) ?? tool) : tool;
  let targets = new Map(), checked = 0, active = null, pending = false, relativeE = false, e = 0;
  const lines = content.split(/\r?\n/);
  const body = lines.findIndex(l => l.trim() === '; MACHINE_START_GCODE_END');
  if (body < 0) throw Error('Cannot verify advance heating: startup boundary missing.');
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i], code = line.split(';')[0].trim(), p = {};
    for (const m of code.matchAll(/([A-Z])\s*(-?(?:\d+(?:\.\d*)?|\.\d+))/g)) p[m[1]] = Number(m[2]);
    // Firmware may cool heaters during an arbitrarily long pause. A pre-pause
    // schedule must never satisfy a post-resume temperature wait.
    if (isPause(code)) { targets.clear(); pending = false; }
    if (/^T\d+\b/.test(code)) {
      if (!/^T\d+$/.test(code) || Number(code.slice(1)) > 31) throw Error('Invalid logical tool ID (supported slots: 1–32).');
      active = key(Number(code.slice(1))); pending = false;
    }
    if (/^M83\b/.test(code)) relativeE = true;
    if (/^M82\b/.test(code)) relativeE = false;
    if (/^G92\b/.test(code) && p.E !== undefined) e = p.E;
    if (line.includes(MARKER)) {
      if (!/^M104\b/.test(code) || !Number.isInteger(p.T) || p.T < 0 || p.T > 31 || p.S === undefined) throw Error('Invalid scheduled heating command.');
      if (key(p.T,p) === active) pending = true;
    }
    if (/^G[0123]\b/.test(code) && p.E !== undefined) {
      const delta = relativeE ? p.E : p.E - e;
      if (pending && delta > 0) throw Error('A scheduled preheat would interfere with a tool still extruding.');
      e = relativeE ? e + p.E : p.E;
    }
    if (/^M104\b/.test(code) && p.T !== undefined) {
      const previous = targets.get(key(p.T,p));
      // A repeated target does not interrupt heating. A changed target invalidates
      // the previous schedule, even if an unmarked command later restores it.
      targets.set(key(p.T,p), {temp:p.S, scheduled:line.includes(MARKER) ||
        (previous?.scheduled === true && previous.temp === p.S)});
    }
    if (i > body && /^M109\b/.test(code) && p.T !== undefined && p.S > 0) {
      const state = targets.get(key(p.T,p));
      if (!state?.scheduled || state.temp !== p.S) throw Error(`Preheat missing or cancelled before T${p.T} temperature wait.`);
      checked++;
    }
  }
  return checked;
}
function processUpload(content, options) {
  const settings = normalizeOptions(options);
  if (!settings.enabled) return {content, report:{status:'disabled', switches:0}};
  if (content.includes(MARKER)) {
    const checked = verifyPreheats(content);
    return {content, report:{status:'already_processed', switches:checked}};
  }
  // Other slicers/profiles keep their existing behavior. Never add a second scheduler to Orca.
  if (!isBambuU1(content)) return {content, report:{status:'other_slicer', switches:0}};
  if (!content.includes('; cooldown previous extruder')) {
    if (/^M109\s+.*\bT\d+/m.test(content.slice(content.indexOf('; MACHINE_START_GCODE_END'))))
      throw Error('Bambu tool changes do not match the supported U1 profile.');
    return {content, report:{status:'no_tool_changes', switches:0}};
  }
  if (/^M104\b.*; preheat T/m.test(content)) throw Error('Another advance-heating scheduler is already present.');
  const result = addPreheat(content, settings.leadSeconds);
  if (verifyPreheats(result.content) !== result.report.switches) throw Error('Preheat validation count mismatch.');
  result.report.status = 'processed';
  return result;
}
function addPreheat(content, lead = 30, toolMap = null) {
  const key = (tool, p = {}) => toolMap && p.A !== 0 ? (toolMap.get(tool) ?? tool) : tool;
  if (!Number.isFinite(lead) || lead < 5 || lead > 120) throw Error('Lead must be 5–120 seconds.');
  if (content.includes(MARKER)) throw Error('File already processed.');
  const lines = content.split(/\r?\n/);
  const body = lines.findIndex(l => l.trim() === '; MACHINE_START_GCODE_END');
  if (body < 0) throw Error('Expected Bambu U1 startup boundary was not found; no output written.');
  for (const line of lines) {
    const code = line.split(';')[0].trim();
    if (/^T\d+\b/.test(code) && (!/^T\d+$/.test(code) || Number(code.slice(1)) > 31)) throw Error('Invalid logical tool ID (supported slots: 1–32).');
  }
  // Logical project slots can be sparse (e.g. T1/T3/T5/T7). Firmware's
  // SET_PRINT_EXTRUDER_MAP maps these IDs, including M104/M109, to heads.
  // Keep logical IDs intact so manual head assignments remain authoritative.
  const times = [], switches = [], cooldown = new Map();
  let t = 0, feed = 0, speed = 1, savedSpeed = 1, absolute = true, relativeE = false, active = null, pauseFloor = body + 1;
  let pos = {}, inserts = new Map(), removed = 0;
  const rows = [];
  for (let i = 0; i < lines.length; i++) {
    times[i] = t;
    const code = lines[i].split(';')[0].trim();
    const cmd = code.match(/^([GMT]\d+)\b/)?.[1];
    const p = {};
    for (const m of code.matchAll(/([A-Z])\s*(-?(?:\d+(?:\.\d*)?|\.\d+))/g)) p[m[1]] = Number(m[2]);
    if (/^T\d+$/.test(code)) active = key(Number(code.slice(1)));
    if (i > body && isPause(code)) pauseFloor = i + 1;
    if (cmd === 'G20') throw Error('Inch units are unsupported.');
    // Conservatively count arcs as zero time, but retain their endpoint/feed state.
    if (cmd === 'G2' || cmd === 'G3') {
      if (p.F !== undefined) feed = p.F;
      for (const k of ['X','Y','Z','E']) if (p[k] !== undefined) {
        const relative = k === 'E' ? relativeE : !absolute;
        pos[k] = relative ? (pos[k] === undefined ? undefined : pos[k] + p[k]) : p[k];
      }
    }
    if (cmd === 'G90') absolute = true;
    if (cmd === 'G91') absolute = false;
    if (cmd === 'M82') relativeE = false;
    if (cmd === 'M83') relativeE = true;
    if (cmd === 'M220') {
      if (/\bB\b/.test(code)) savedSpeed = speed;
      if (/\bR\b/.test(code)) speed = savedSpeed;
      if (p.S !== undefined) { if (p.S <= 0) throw Error('Invalid speed multiplier.'); speed = p.S / 100; }
    }
    if (cmd === 'G92') for (const k of ['X','Y','Z','E']) if (p[k] !== undefined) pos[k] = p[k];
    if (cmd === 'G0' || cmd === 'G1') {
      if (p.F !== undefined) feed = p.F;
      let squared = 0, known = true, hasXYZ = false, eDistance = 0;
      for (const k of ['X','Y','Z','E']) if (p[k] !== undefined) {
        const relative = k === 'E' ? relativeE : !absolute;
        const delta = relative ? p[k] : pos[k] === undefined ? 0 : p[k] - pos[k];
        if (k !== 'E') { hasXYZ = true; squared += delta * delta; if (!relative && pos[k] === undefined) known = false; }
        else eDistance = Math.abs(delta);
        pos[k] = relative ? (pos[k] === undefined ? undefined : pos[k] + p[k]) : p[k];
      }
      // Nominal-speed duration is a lower bound: ignoring acceleration tends to preheat earlier.
      if (i > body && feed > 0 && speed > 0) t += (hasXYZ ? known ? Math.sqrt(squared) : 0 : eDistance) / (feed * speed / 60);
    }
    if (i > body && cmd === 'G4') t += (p.S || 0) + (p.P || 0) / 1000;
    if (i > body && cmd === 'M104' && p.T !== undefined && /cooldown/.test(lines[i])) cooldown.set(key(p.T,p), i);
    if (i > body && cmd === 'M109' && p.T !== undefined && p.S > 0) {
      if (!Number.isInteger(p.T) || p.T < 0 || p.T > 31) throw Error('Invalid U1 tool ID.');
      // An alias of the active physical head must not change temperature while
      // the preceding logical color is still printing. Heat at its wait only.
      const floor = toolMap && key(p.T,p) === active ? i : Math.max(pauseFloor, (cooldown.get(key(p.T,p)) ?? body) + 1);
      switches.push({line:i, tool:p.T, temperature:p.S, floor});
    }
    if (/^(SM_|MOVE_TO_|ROUGHLY_|FINELY_|T\d+\b|G28\b)/.test(code)) pos = {};
  }
  if (!switches.length) throw Error('No explicit tool-change temperature waits found.');
  if (lines.some(l => /^M104\b.*; preheat T/.test(l))) throw Error('Existing Orca preheating found; use original Bambu file.');
  for (const s of switches) {
    let at = s.line;
    while (at > s.floor && times[s.line] - times[at] < lead) at--;
    const available = times[s.line] - times[at];
    const command = `M104 S${s.temperature} T${s.tool} ; U1_ADVANCE_PREHEAT lead=${lead}s available_motion=${available.toFixed(1)}s`;
    if (!inserts.has(at)) inserts.set(at, []);
    inserts.get(at).push(command);
    rows.push({tool:s.tool, originalWaitLine:s.line+1, originalInsertionLine:at+1, nominalLeadSeconds:Number(available.toFixed(1)), limitedByRecentUse:available < lead});
  }
  const result = [];
  for (let i=0;i<lines.length;i++) {
    if (inserts.has(i)) result.push(...inserts.get(i));
    if (/^M104\b.*;Wipe tower reheat before wipe\s*$/.test(lines[i])) { removed++; continue; }
    result.push(lines[i]);
  }
  return {content:result.join('\r\n'), report:{leadSeconds:lead, switches:rows.length, removedLegacyReheats:removed, notes:'Motion times exclude acceleration and unknown macro duration. Startup unchanged. M109 checks preserved. Short reuse intervals may provide less than requested lead.', rows}};
}
module.exports = {addPreheat, processUpload, normalizeOptions, verifyPreheats, countPauses, isBambuU1};
