#!/usr/bin/env python3
"""Generate additive Bambu U1 presets from a pinned official Snapmaker checkout."""
import json, pathlib, subprocess, sys, re, shutil
repo=pathlib.Path(__file__).resolve().parents[2]
source=pathlib.Path(sys.argv[1]); vendor=repo/'Snapmaker'
def read(p): return json.loads(p.read_text(encoding='utf-8-sig'))
def write(p,d): p.write_text(json.dumps(d,indent=4,ensure_ascii=False)+'\n')
manifest=read(repo/'Snapmaker.json'); provenance={'source':'https://github.com/Snapmaker/snapmaker-profiles','commit':subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD']).decode().strip(),'profiles':[]}
def resolve(folder,name,seen=()):
 if name in seen: raise ValueError('Inheritance cycle')
 d=read(folder/(name+'.json')); parent=d.get('inherits'); out=resolve(folder,parent,seen+(name,)) if parent else {};out.update(d);return out
original='Snapmaker U1 (0.4 nozzle)'
base_machine=resolve(vendor/'machine',original)
metadata={'type','name','inherits','from','instantiation','setting_id','filament_id','version','description','renamed_from','compatible_printers','compatible_printers_condition','print_settings_id','filament_settings_id'}
known={t:set().union(*(read(p).keys() for p in (vendor/t).glob('*.json'))) for t in ['process','filament']}
known['process'].add('support_line_width')
def add(typ,d,source_name=None):
 p=vendor/typ/(d['name']+'.json'); assert not p.exists(),p;write(p,d)
 manifest[typ+'_list'].append({'name':d['name'],'sub_path':typ+'/'+p.name})
 provenance['profiles'].append({'name':d['name'],'source_profile':source_name,'kind':typ})
filaments={read(p)['name']:p for p in (vendor/'filament').glob('*.json') if read(p).get('instantiation')=='true'}
for size,default_height in [('0.2','0.10'),('0.6','0.30'),('0.8','0.40')]:
 machine=f'Snapmaker U1 ({size} nozzle)'
 official_machine=resolve(source/'Snapmaker/machine',machine)
 processes=[]
 for p in sorted((source/'Snapmaker/process').glob(f'*@Snapmaker U1 ({size} nozzle).json')):
  direct=read(p)
  if direct.get('instantiation')!='true': continue
  official=resolve(p.parent,direct['name'])
  height=float(official['layer_height']); low=float(official_machine['min_layer_height'][0]);high=float(official_machine['max_layer_height'][0])
  if not low<=height<=high: raise ValueError(p)
  name=direct['name']+' [Bridge test]'
  d={'type':'process','name':name,'inherits':'fdm_process_common','from':'system','instantiation':'true','setting_id':'GP_U1N_'+size.replace('.','')+'_'+str(len(processes)), 'compatible_printers':[machine]}
  for k,v in official.items():
   if k in known['process'] and k not in metadata and not k.endswith('gcode') and k not in ['standby_temperature_delta','enable_prime_tower','wipe_tower_no_sparse_layers','print_sequence']:
    d[k]=v
  d['enable_support']='0'
  add('process',d,direct['name']);processes.append(d)
 defaults=[d['name'] for d in processes if d['layer_height']==str(float(default_height)) and 'Strength' not in d['name']]
 assert defaults,(size,processes)
 d={'type':'machine','name':machine,'inherits':original,'from':'system','instantiation':'true','setting_id':'GM_U1N_'+size.replace('.',''),'printer_model':f'Snapmaker U1 - {size} mm','printer_variant':size,'nozzle_type':'hardened_steel','default_print_profile':defaults[0]}
 for k in ['nozzle_diameter','min_layer_height','max_layer_height','retraction_length','retraction_speed','deretraction_speed','retraction_minimum_travel']:
  values=official_machine[k];assert len(set(values))==1;d[k]=[values[0]]
 compatible=[]
 for old,p in sorted(filaments.items()):
  source_name=old+' '+size+' nozzle';sp=source/'Snapmaker/filament'/(source_name+'.json')
  if not sp.exists(): continue
  off=resolve(sp.parent,source_name);name=source_name+' [Bridge test]'
  f={'type':'filament','name':name,'inherits':old,'from':'system','instantiation':'true','setting_id':'GF_U1N_'+size.replace('.','')+'_'+str(len(compatible)), 'compatible_printers':[machine]}
  for k,v in off.items():
   if k in known['filament'] and k not in metadata and 'gcode' not in k: f[k]=v
  # Preserve bridge-specific startup/end snippets through inheritance.
  add('filament',f,source_name);compatible.append(name)
 default='Generic PLA @U1 '+size+' nozzle [Bridge test]'
 assert default in compatible
 d['default_filament_profile']=[default];add('machine',d,machine)
model=read(vendor/'machine/Snapmaker U1.json');model['nozzle_diameter']='0.4';write(vendor/'machine/Snapmaker U1.json',model)
for size in ['0.2','0.6','0.8']:
 name=f'Snapmaker U1 - {size} mm';d=dict(model,name=name,model_id='Snapmaker-U1-'+size.replace('.',''),nozzle_diameter=size,default_materials=f'Generic PLA @U1 {size} nozzle [Bridge test]');write(vendor/'machine'/(name+'.json'),d);manifest['machine_model_list'].append({'name':name,'sub_path':'machine/'+name+'.json'})
for size in ['0.2','0.6','0.8']: shutil.copyfile(vendor/'Snapmaker U1_cover.png',vendor/f'Snapmaker U1 - {size} mm_cover.png')
manifest['version']='03.14.00.01';write(repo/'Snapmaker.json',manifest)
write(repo/'tools/nozzle-profiles/provenance.json',provenance)
print('Generated',len(provenance['profiles']),'additive profiles')
