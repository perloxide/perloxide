#!/usr/bin/env python3
"""Build an exhaustive outcome catalog from the saved, isolated Perl runs."""
import json
import re
from pathlib import Path


def read(version):
    rows = []
    for prefix in ('reentry-', 'reentry-tied-warning-'):
        data = [json.loads(line) for line in Path(f'{prefix}{version}.jsonl').read_text().splitlines()]
        rows.extend(data[1:])
    return rows


def key(row):
    return tuple(row[k] for k in ('mode', 'input', 'action', 'op'))


def observable(row):
    # This comparison deliberately excludes B representation details. The raw
    # files preserve them. No assertion of identical internal SV layouts.
    out = {k: row.get(k) for k in ('ok', 'result', 'error', 'child_status', 'stderr')}
    out['observed'] = {k: row.get('observed', {}).get(k) for k in ('text', 'next', 'error')}
    out['events'] = [{k: e[k] for k in ('event', 'message') if k in e}
                     for e in row.get('events', [])]
    s = json.dumps(out, sort_keys=True)
    for h in re.findall(r'0x([0-9a-fA-F]+)', row.get('observed', {}).get('text') or ''):
        s = s.replace(str(int(h, 16)), '<address>').replace('0x' + h, '<address>')
    return json.loads(s)


all_rows = {v: read(v) for v in ('5.38.2', '5.44.0')}
result = {'versions': {}}
for version, rows in all_rows.items():
    baseline = {(r['mode'], r['input'], r['op']): r for r in rows if r['action'] == 'none'}
    changed = []
    exceptions = []
    signals = []
    for r in rows:
        if 'child_status' in r:
            signals.append({'case': key(r), 'wait_status': r['child_status']})
        elif not r['ok']:
            exceptions.append({'case': key(r), 'error': r['error']})
        else:
            b = baseline[r['mode'], r['input'], r['op']]
            if r['result'] != b['result']:
                changed.append({'case': key(r), 'baseline': b['result'], 'result': r['result']})
    result['versions'][version] = {
        'cases': len(rows), 'successful': sum(r.get('ok', 0) for r in rows),
        'changed_return_count': len(changed), 'changed_returns': changed,
        'exception_count': len(exceptions), 'exceptions': exceptions,
        'signal_count': len(signals), 'signals': signals,
    }

a = {key(r): r for r in all_rows['5.38.2']}
b = {key(r): r for r in all_rows['5.44.0']}
assert a.keys() == b.keys()
diffs = [{'case': k, '5.38.2': observable(a[k]), '5.44.0': observable(b[k])}
         for k in a if observable(a[k]) != observable(b[k])]
result['cross_version_observable_differences'] = diffs
Path('matrix_findings.json').write_text(json.dumps(result, indent=2, sort_keys=True) + '\n')
print(json.dumps({v: {k: n for k, n in d.items() if not isinstance(n, list)}
                  for v, d in result['versions'].items()}, indent=2))
print('Cross-version differences in compared observable fields:', len(diffs))
