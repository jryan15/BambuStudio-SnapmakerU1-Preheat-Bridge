// Shared by the Device page and server. Project slots are logical IDs;
// printer labels are suggestions only, never an exact-match requirement.
(function(root, factory) {
  if (typeof module === 'object' && module.exports) module.exports = factory();
  else root.U1FilamentMapping = factory();
})(typeof globalThis !== 'undefined' ? globalThis : this, function() {
  function array(value) {
    return Array.isArray(value) ? value : typeof value === 'string' ? value.split(';') : value == null ? [] : [value];
  }
  function usedSlots(meta) {
    if (Array.isArray(meta.bridge_used_slots)) return meta.bridge_used_slots;
    var types = array(meta.filament_type), colors = array(meta.filament_colour);
    var used = array(meta.filament_used_mm).map(Number);
    var weights = array(meta.filament_weight).map(Number);
    var count = Math.max(types.length, colors.length, used.length, weights.length);
    var hasUsage = used.some(function(v) { return v > 0; });
    var hasWeight = weights.some(function(v) { return v > 0; });
    var slots = [];
    for (var i = 0; i < count; i++) {
      if (hasUsage ? used[i] > 0 : hasWeight ? weights[i] > 0 : false) slots.push(i);
    }
    return slots;
  }
  function suggest(slots, rank) {
    var map = [], assigned = {};
    slots.forEach(function(slot) {
      var candidates = [0, 1, 2, 3].filter(function(head) { return !assigned[head]; });
      if (!candidates.length) candidates = [0,1,2,3];
      candidates.sort(function(a, b) { return rank(slot, a) - rank(slot, b) || a - b; });
      map[slot] = candidates.length ? candidates[0] : null;
      if (map[slot] !== null) assigned[map[slot]] = true;
    });
    return map;
  }
  function sharedHeads(table) {
    var groups = {};
    table.forEach(function(row) { (groups[row[1]] || (groups[row[1]] = [])).push(row[0]); });
    return Object.keys(groups).filter(function(head) { return groups[head].length > 1; }).map(function(head) { return {head:Number(head),slots:groups[head]}; });
  }
  function validate(table, slots) {
    if (!Array.isArray(table) || !Array.isArray(slots) || !slots.length) throw Error('Filament usage is unavailable. Reload the confirmation screen.');
    if (table.length !== slots.length) throw Error('Assign every used project filament to a printer head.');
    var logical = new Set(), heads = new Set();
    table.forEach(function(row) {
      if (!Array.isArray(row) || row.length !== 2 || !Number.isInteger(row[0]) || row[0] < 0 || row[0] > 31 || !Number.isInteger(row[1]) || row[1] < 0 || row[1] > 3)
        throw Error('Invalid filament assignment.');
      if (!slots.includes(row[0]) || logical.has(row[0])) throw Error('Filament assignments do not match this plate.');
      logical.add(row[0]); heads.add(row[1]);
    });
    return table;
  }
  return { array: array, usedSlots: usedSlots, suggest: suggest, validate: validate, sharedHeads: sharedHeads };
});
