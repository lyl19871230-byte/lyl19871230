"""Print exact stored prompt text by stable ID, or list the entire index."""
import hashlib
import json
import sys
from pathlib import Path
root = Path(__file__).resolve().parents[1]
data = json.loads((root / 'references/catalog.json').read_text(encoding='utf-8'))
by_id = {e['id']: e for e in data['entries']}
ids = sys.argv[1:]
if not ids or ids == ['--list']:
    print((root / 'references/index.md').read_text(encoding='utf-8'))
    raise SystemExit(0)
unknown = [key for key in ids if key not in by_id]
if unknown:
    raise SystemExit('未知编号：' + ', '.join(unknown))
for key in ids:
    e = by_id[key]
    if hashlib.sha256(e['text'].encode('utf-8')).hexdigest() != e['sha256']:
        raise SystemExit('原文校验失败：' + key)
    print(f"### {key} {e['title']}\n\n````text\n{e['text']}\n````\n")
