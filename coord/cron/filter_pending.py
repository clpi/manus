import json, sys
tasks_jsonl = sys.argv[1]
for line in open(tasks_jsonl):
    line = line.strip()
    if not line or not line.startswith('{'):
        continue
    try:
        t = json.loads(line)
    except Exception:
        continue
    if t.get('state') == 'pending':
        print(line)
