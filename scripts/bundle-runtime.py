#!/usr/bin/env python3
"""Bundle the installed llama.cpp runtime and its non-system dylibs; no Homebrew at run time."""
import pathlib, shutil, subprocess, sys
app = pathlib.Path(sys.argv[1])
helpers = app / 'Contents/Helpers'
frameworks = app / 'Contents/Frameworks'
frameworks.mkdir(parents=True, exist_ok=True)
source = shutil.which('llama-server')
if not source:
    sys.exit('llama-server is required to package local inference. Install llama.cpp, then rebuild.')
seen = {}
def out(*args): return subprocess.check_output(args, text=True)
def rpaths(path):
    lines = out('otool', '-l', str(path)).splitlines()
    return [lines[i+2].strip().split('path ',1)[-1].split(' (offset',1)[0] for i,l in enumerate(lines) if l.strip() == 'cmd LC_RPATH']
def resolve(dep, parent):
    if dep.startswith('@rpath/'):
        for root in rpaths(parent) + ['/opt/homebrew/opt/llama.cpp/lib', '/usr/local/opt/llama.cpp/lib']:
            candidate = pathlib.Path(root.replace('@loader_path', str(parent.parent)).replace('@executable_path', str(pathlib.Path(source).resolve().parent))) / dep[7:]
            if candidate.exists(): return candidate.resolve()
        raise RuntimeError(f'Cannot resolve {dep} from {parent}')
    return pathlib.Path(dep.replace('@loader_path', str(parent.parent))).resolve()
def bundle(path, target):
    path = path.resolve()
    if path in seen: return seen[path]
    seen[path] = target
    shutil.copy2(path, target)
    target.chmod(0o755)
    dependencies = [line.strip().split(' (compatibility',1)[0] for line in out('otool','-L',str(path)).splitlines()[1:]]
    for dep in dependencies:
        if dep.startswith(('/usr/lib/', '/System/')): continue
        resolved = resolve(dep, path)
        if resolved == path: continue
        dest = bundle(resolved, frameworks / resolved.name)
        replacement = '@executable_path/../Frameworks/' + dest.name
        subprocess.run(['install_name_tool','-change',dep,replacement,str(target)],check=True)
    if target.suffix == '.dylib':
        subprocess.run(['install_name_tool','-id','@executable_path/../Frameworks/'+target.name,str(target)],check=True)
    subprocess.run(['codesign','--force','--sign','-',str(target)],check=True,stdout=subprocess.DEVNULL)
    return target
bundle(pathlib.Path(source), helpers / 'llama-server')
licenses = app / 'Contents/Resources/RuntimeLicenses'
licenses.mkdir(exist_ok=True)
for package in ['llama.cpp','ggml','openssl@3']:
    prefix = pathlib.Path('/opt/homebrew/opt') / package
    if not prefix.exists(): prefix = pathlib.Path('/usr/local/opt') / package
    for name in ['LICENSE','LICENSE.txt','LICENSE.md']:
        if (prefix/name).exists(): shutil.copy2(prefix/name, licenses/(package.replace('@','-')+'-'+name))
print(f'Bundled llama.cpp and {len(seen)-1} libraries')
