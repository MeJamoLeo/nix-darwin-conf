#!/usr/bin/env python3
"""Generate web/inject.js from cached JSON — the Mac stand-in for dashboard.py's
WebKit injection (x1nano). Reads the same ~/.cache/cp-dashboard/ files."""

import argparse
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.expanduser('~/.cache/cp-dashboard')
WATCHLIST = os.path.join(ROOT, 'watchlist.json')


def load_json(path):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, json.JSONDecodeError) as e:
        print(f'[gen-inject] warn: {path}: {e}', file=sys.stderr)
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--user', default=None, help='watchlist user (default: first)')
    ap.add_argument('--width', type=int, default=2560)
    ap.add_argument('--height', type=int, default=1440)
    ap.add_argument('--output', default=os.path.join(ROOT, 'web', 'inject.js'))
    args = ap.parse_args()

    user = args.user
    if not user:
        wl = load_json(WATCHLIST) or []
        if not wl:
            sys.exit('[gen-inject] error: no watchlist.json and no --user')
        user = wl[0]

    stats = load_json(os.path.join(CACHE, f'stats_{user}.json'))
    if stats is None:
        sys.exit(f'[gen-inject] error: stats_{user}.json missing — run fetch first')
    novi = load_json(os.path.join(CACHE, 'novisteps.json'))
    cookie_expired = bool(novi.get('cookie_expired', False)) if novi else False

    # 直近提出（HUD の LAST SUB 反応領域用）。stats には無いので submissions から注入。
    subs = load_json(os.path.join(CACHE, f'submissions_{user}.json')) or []
    recent = sorted(subs, key=lambda s: s.get('epoch_second', 0))[-5:]
    recent = [
        {
            'epoch': s.get('epoch_second'),
            'problem_id': s.get('problem_id'),
            'result': s.get('result'),
            'point': s.get('point'),
        }
        for s in recent
    ]

    lines = [
        f'window.__NOVI_DATA = {json.dumps(novi)};',
        f'window.__NOVI_COOKIE_EXPIRED = {json.dumps(cookie_expired)};',
        f'window.__VP = {{w:{args.width}, h:{args.height}}};',
        f'window.__RECENT_SUBS = {json.dumps(recent)};',
        f'window.__CP_DATA = {json.dumps(stats)};',
        'hydrate();',
    ]
    tmp = args.output + '.tmp'
    with open(tmp, 'w') as f:
        f.write('\n'.join(lines) + '\n')
    os.replace(tmp, args.output)
    print(f'[gen-inject] wrote {args.output} (user={user}, vp={args.width}x{args.height})')


if __name__ == '__main__':
    main()
