#!/usr/bin/env python3
"""Summarize the exhaustive generated matrix without re-evaluating Perl SVs."""
import collections
import json
import re
import sys

def load(path):
    with open(path) as f:
        rows = [json.loads(line) for line in f]
    return rows[0]['metadata'], rows[1:]

def main(path):
    meta, rows = load(path)
    print(json.dumps(meta, sort_keys=True))
    print('cases:', len(rows))
    failures = [r for r in rows if 'harness_error' in r or 'child_status' in r]
    print('harness/process failures:', len(failures))
    for r in failures:
        print(json.dumps(r, sort_keys=True))
    baseline = {(r['mode'],r['input'],r['op']):r for r in rows if r['action']=='none'}
    groups = collections.defaultdict(list)
    errors = collections.defaultdict(list)
    for r in rows:
        if 'ok' not in r:
            continue
        key = (r['mode'],r['input'],r['op'])
        b = baseline[key]
        if not r['ok']:
            errors[(r['mode'],r['action'],r['op'],r['error'].split(' at ')[0])].append(r['input'])
        elif r['result'] != b.get('result'):
            groups[(r['mode'],r['action'],r['op'])].append((r['input'],b.get('result'),r['result']))
    print('\nRESULT DIFFERENCES FROM UNMUTATED SAME-OP BASELINE:')
    for k,v in sorted(groups.items()):
        print(k, v)
    print('\nEXCEPTIONS:')
    for k,v in sorted(errors.items()):
        print(k,v)
    print('\nWARN junk12 SUMMARY (all numeric ops):')
    for r in rows:
        if r['mode']=='warn' and r['input']=='junk12' and r['op'] in ('add','iv','nv'):
            print(r['action'],r['op'], 'result='+str(r.get('result')), 'post='+str(r.get('post')),
                  'obs='+str({k:v for k,v in r.get('observed',{}).items() if k in ('text','next','error')}))
    print('\nFETCH junk12 SUMMARY (add):')
    for r in rows:
        if r['mode']=='fetch' and r['input']=='junk12' and r['op']=='add':
            print(r['action'],r.get('result'),r.get('post'),
                  [e['event'] for e in r.get('events',[])],r.get('observed',{}).get('text'))
    print('\nOVERLOAD junk12 SUMMARY (concat):')
    for r in rows:
        if r['mode']=='overload' and r['input']=='junk12' and r['op']=='concat':
            print(r['action'],r.get('result'),r.get('post'),
                  [e['event'] for e in r.get('events',[])],r.get('observed',{}).get('text'))

if __name__ == '__main__':
    if sys.argv[1] == '--compare':
        am, aa = load(sys.argv[2]); bm, bb = load(sys.argv[3])
        def normalize(r):
            # Addresses differ between processes. Recover the decimal spelling
            # from the observed reference string rather than masking numbers.
            text = r.get('observed',{}).get('text') or ''
            addresses = re.findall(r'0x([0-9a-fA-F]+)',text)
            s = json.dumps(r,sort_keys=True)
            for h in addresses:
                s = s.replace(str(int(h,16)), '<address>')
                s = s.replace('0x'+h, '<address>')
            r=json.loads(s)
            def clean(x):
                if isinstance(x,dict):
                    return {k:clean(v) for k,v in x.items() if k!='nv_slot'}
                if isinstance(x,list): return [clean(v) for v in x]
                return x
            return clean(r)
        diffs=[]
        for a,b in zip(aa,bb):
            assert tuple(a[k] for k in ('mode','input','action','op'))==tuple(b[k] for k in ('mode','input','action','op'))
            if normalize(a)!=normalize(b):
                diffs.append({'case':[a[k] for k in ('mode','input','action','op')], 'a':normalize(a),'b':normalize(b)})
        print(json.dumps({'a':am,'b':bm,'rows_a':len(aa),'rows_b':len(bb),'differences':diffs},sort_keys=True,indent=2))
    else:
        main(sys.argv[1])
