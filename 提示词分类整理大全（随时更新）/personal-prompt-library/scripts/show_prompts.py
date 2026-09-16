"""Print current Chinese prompts, resolving old IDs; --original reads archived text."""
import hashlib,json,sys
from pathlib import Path
root=Path(__file__).resolve().parents[1]
args=sys.argv[1:]
original=bool(args and args[0]=='--original')
if original:args=args[1:]
data=json.loads((root/('references/catalog.json' if original else 'references/catalog-zh.json')).read_text(encoding='utf-8'))
if not args or args==['--list']:
    print((root/('references/index.md' if original else 'references/index-zh.md')).read_text(encoding='utf-8'))
    raise SystemExit(0)
by_id={e['id']:e for e in data['entries']}
ids=list(dict.fromkeys(k if original else data['old_to_new'].get(k,k) for k in args))
unknown=[k for k in ids if k not in by_id]
if unknown:raise SystemExit('未知编号：'+', '.join(unknown))
for k in ids:
    e=by_id[k]
    if hashlib.sha256(e['text'].encode('utf-8')).hexdigest()!=e['sha256']:raise SystemExit('正文校验失败：'+k)
    print(f"### {k} {e['title']}\n\n````text\n{e['text']}\n````\n")
