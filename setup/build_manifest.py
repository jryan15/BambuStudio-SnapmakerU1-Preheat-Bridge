from pathlib import Path
import hashlib,json
r=Path(__file__).resolve().parents[1]
def digest(p):return hashlib.sha256(p.read_bytes()).hexdigest()
files=[];bridge=[]
for folder in ['Snapmaker','bridge-node','bridge/web']:
 for p in sorted((r/folder).rglob('*')):
  if not p.is_file() or any(x in p.parts for x in ['node_modules','.git','test']):continue
  rel=p.relative_to(r).as_posix()
  if folder=='bridge-node' and p.name in ['build.js']:continue
  files.append(dict(path=rel,sha256=digest(p)))
  if folder!='Snapmaker':
   dst=p.relative_to(r/'bridge-node').as_posix() if folder=='bridge-node' else 'web/'+p.relative_to(r/'bridge/web').as_posix()
   bridge.append(dict(path=rel,destination=dst,sha256=digest(p)))
for name in ['Snapmaker.json','tools/nozzle-profiles/provenance.json','setup/setup-watchdog.ps1']:
 files.append(dict(path=name,sha256=digest(r/name)))
bridge.append(dict(path='setup/setup-watchdog.ps1',destination='setup-watchdog.ps1',sha256=digest(r/'setup/setup-watchdog.ps1')))
(r/'setup/payload.json').write_text(json.dumps(dict(version='5.48.0-u1.4-test.8',bridgeVersion='5.48.0-u1.4-test.7',files=files,bridge=bridge),indent=2)+'\n')
print(len(files),'payload files')
