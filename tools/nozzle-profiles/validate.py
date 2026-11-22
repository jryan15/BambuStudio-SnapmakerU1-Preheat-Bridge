import pathlib,json,subprocess
r=pathlib.Path(__file__).resolve().parents[2];v=r/'Snapmaker'
def read(p):return json.loads(p.read_text(encoding='utf-8-sig'))
def resolved(t,n,seen=()):
 assert n not in seen
 d=read(v/t/(n+'.json'));out=resolved(t,d['inherits'],seen+(n,)) if d.get('inherits') else {};out.update(d);return out
manifest=read(r/'Snapmaker.json');profiles=read(r/'tools/nozzle-profiles/provenance.json')['profiles'];names=set();ids=set()
for typ in ['machine','process','filament']:
 for e in manifest[typ+'_list']:
  d=read(v/e['sub_path']);assert d['name']==e['name'];resolved(typ,d['name'])
for e in profiles:
 d=read(v/e['kind']/(e['name']+'.json'));assert d['name'] not in names;names.add(d['name']);assert d['setting_id'] not in ids;ids.add(d['setting_id'])
 x=resolved(e['kind'],d['name'])
 if e['kind']=='machine':
  baseline=resolved('machine','Snapmaker U1 (0.4 nozzle)')
  for k in baseline:
   if 'gcode' in k:assert x[k]==baseline[k],(d['name'],k)
  assert x['gcode_flavor']=='klipper';assert x['printable_area']==baseline['printable_area']
  p=resolved('process',x['default_print_profile']);assert d['name'] in p['compatible_printers']
  for f in x['default_filament_profile']:assert d['name'] in resolved('filament',f)['compatible_printers']
 if e['kind']=='process':
  m=resolved('machine',x['compatible_printers'][0]);diam=float(m['nozzle_diameter'][0])
  assert float(m['min_layer_height'][0])<=float(x['layer_height'])<=float(m['max_layer_height'][0])
  assert float(x['initial_layer_print_height'])<=float(m['max_layer_height'][0])
  for k in ['line_width','outer_wall_line_width','inner_wall_line_width','initial_layer_line_width','sparse_infill_line_width','top_surface_line_width']:
   assert 0.8*diam<=float(x[k])<=1.6*diam,(d['name'],k,x[k])
 if e['kind']=='filament':
  assert float(x['filament_max_volumetric_speed'][0])>0
  parent=resolved('filament',d['inherits'])
  for k in parent:
   if 'gcode' in k:assert x[k]==parent[k]
# Existing executable presets and all bridge files retain exactly their committed bytes.
for f in subprocess.check_output(['git','-C',str(r),'ls-tree','-r','--name-only','cee46a2d7fa416790d79f5fc77425fe273f90b04','Snapmaker']).decode().splitlines():
 if f=='Snapmaker/machine/Snapmaker U1.json':continue
 assert (r/f).read_bytes()==subprocess.check_output(['git','-C',str(r),'show','cee46a2d7fa416790d79f5fc77425fe273f90b04:'+f]),f
print(f'PASS: {len(profiles)} added presets; inheritance, registry, unique IDs, defaults, nozzle widths/heights, material limits, unchanged G-code and original presets.')
