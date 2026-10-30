#!/usr/bin/env python3
"""Extract static SVG artwork from pinned, unpacked public npm packages. Never execute JS.
Usage: generate-icon-artwork.py LUCIDE_PACKAGE REACT_ICONS_PACKAGE OUTPUT
Sources: lucide-react@0.577.0 (ISC), react-icons@5.6.0/go (Octicons, MIT).
"""
import html, json, re, sys
from pathlib import Path
lucide, react, output = map(Path, sys.argv[1:])
def attrs(values):
    return ' '.join(f'{k}="{html.escape(str(v), quote=True)}"' for k,v in values.items() if k != 'key')
art = {}
by_file = {}
for path in (lucide/'dist/esm/icons').glob('*.js'):
    match = re.search(r'const __iconNode = ([\s\S]*?);\s*const (\w+) = createLucideIcon', path.read_text())
    if not match: continue
    raw = re.sub(r'([{,]\s*)([A-Za-z]\w*)\s*:', r'\1"\2":', match[1])
    raw = re.sub(r',\s*([}\]])', r'\1', raw)
    nodes = json.loads(raw)
    body = ''.join(f'<{tag} {attrs(values)}/>' for tag, values in nodes)
    art['lucide:'+match[2]] = '<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">'+body+'</svg>'
    by_file[path.name] = art['lucide:'+match[2]]
for names, filename in re.findall(r"export \{ ([^}]+) \} from './icons/([^']+)';", (lucide/'dist/esm/lucide-react.js').read_text()):
    if filename not in by_file: continue
    for name in re.findall(r'default as (\w+)', names):
        if not name.startswith('Lucide') and not name.endswith('Icon'):
            art['lucide:'+name] = by_file[filename]
def element(node):
    return '<'+node['tag']+' '+attrs(node['attr'])+'>'+''.join(element(c) for c in node.get('child',[]))+'</'+node['tag']+'>'
for name, raw in re.findall(r'export function (Go\w+) \(props\) \{\s*return GenIcon\((.*?)\)\(props\);', (react/'go/index.mjs').read_text()):
    node = json.loads(raw)
    node['attr'].update(xmlns='http://www.w3.org/2000/svg',width='24',height='24',fill='white')
    art['octicons:'+name] = element(node)
output.write_text(json.dumps(art, sort_keys=True, separators=(',',':'))+'\n')
print(f'{len(art)} public icon drawings written')
