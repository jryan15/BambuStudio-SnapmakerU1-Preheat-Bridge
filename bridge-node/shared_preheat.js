const {addPreheat,verifyPreheats,normalizeOptions,isBambuU1}=require('./advance_preheat');
const COOLDOWN_MARKER='; U1_SHARED_COOLDOWN ';
const SCHEDULE_MARKER='; U1_SHARED_SCHEDULE';
const markSchedule=content=>content.replace(/(^; (?:BambuStudio\b|U1 source slicer: Bambu Studio\b)[^\r\n]*)/m,'$1\r\n'+SCHEDULE_MARKER);
function cleanSharedCooldowns(content,toolMap) {
  const lines=content.split(/\r?\n/),key=tool=>toolMap.get(tool)??tool;
  let active=null,skipped=0;
  for(let i=0;i<lines.length;i++) {
    const code=lines[i].split(';')[0].trim(),selected=code.match(/^T(\d+)$/);
    if(selected) active=key(Number(selected[1]));
    const cooldown=code.match(/^M104 S70 T(\d+)$/);
    if(!cooldown || !/; cooldown previous extruder\s*$/.test(lines[i]) || key(Number(cooldown[1]))!==active) continue;
    // Recognize only the profile's temperature-wait / tool-select sequence.
    // Keep Z lifts, purge, extrusion and logical selection unchanged.
    for(let j=i+1;j<Math.min(i+32,lines.length);j++) {
      const next=lines[j].split(';')[0].trim();
      if(!next) continue;
      const wait=next.match(/^M109 S([\d.]+) T(\d+)$/);
      if(wait) {
        let k=j+1;
        while(k<lines.length && (!lines[k].split(';')[0].trim() || lines[k].split(';')[0].trim()==='M400')) k++;
        if(key(Number(wait[2]))===active && lines[k]?.split(';')[0].trim()==='T'+wait[2]) {
          lines[i]=COOLDOWN_MARKER+lines[i];skipped++;
        }
        break;
      }
      if(!/^(?:G9[01]|G[01](?:\s+[XYZF][-+\d.]+)*|M400)$/.test(next)) break;
    }
  }
  return {content:lines.join('\r\n'),skipped};
}
function restoreHeating(content){
  return content.split(/\r?\n/).filter(l=>l!==SCHEDULE_MARKER && !/^M104\b.*; U1_ADVANCE_PREHEAT\b/.test(l))
    .map(l=>l.startsWith(COOLDOWN_MARKER)?l.slice(COOLDOWN_MARKER.length):l).join('\r\n');
}
function prepareSharedPrint(content, table, options) {
  if (!isBambuU1(content)) throw Error('Shared-head preheating currently supports the Bambu U1 profile only.');
  const settings=normalizeOptions(options),toolMap=new Map(table);
  // Upload-time scheduling knows logical slots, not the user's final physical
  // assignments. Replace our schedule after those assignments are confirmed.
  const clean=restoreHeating(content);
  const optimized=cleanSharedCooldowns(clean,toolMap);
  if (!settings.enabled) return {content:markSchedule(optimized.content),report:{status:'shared_heating_disabled',switches:0,skippedCooldowns:optimized.skipped}};
  const result=addPreheat(optimized.content,settings.leadSeconds,toolMap);
  if (verifyPreheats(result.content,toolMap)!==result.report.switches) throw Error('Shared-head preheat validation failed.');
  result.report.status='shared_head_processed';
  result.report.skippedCooldowns=optimized.skipped;
  result.content=markSchedule(result.content);
  return result;
}
module.exports={prepareSharedPrint,cleanSharedCooldowns,restoreHeating};
