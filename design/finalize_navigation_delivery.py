"""Merge freshly exported Figma checks with the existing compact delivery metadata."""
from pathlib import Path
from collections import Counter
from datetime import datetime, timezone
import json

root = Path(__file__).resolve().parent / 'exports/compact-v7.5'
old = json.loads((root / 'verification.json').read_text(encoding='utf-8'))
live = json.loads((root / 'navigation-live-audit.json').read_text(encoding='utf-8'))
assert not live['backNavigationVerification']['errors']
assert not live['backNavigationVerification']['residualTextReturns']
assert not live['settingsUIVerification']['errors']
assert not live['overflow'] and not live['untranslatedDisplayCopy']
old.update(live)
now = datetime.now(timezone.utc).isoformat()
summary_path = root / 'prototype-compact-summary.json'
summary = json.loads(summary_path.read_text(encoding='utf-8'))
summary['verifiedAt'] = now
for platform in ('desktop', 'mobile', 'system'):
    proto = json.loads((root / ('navigation-prototype-' + platform + '.json')).read_text(encoding='utf-8'))
    assert not proto['truncated']
    actions, destinations, unresolved = Counter(), {}, []
    for connection in proto['connections']:
        for reaction in connection.get('reactions', []):
            for action in reaction.get('actions', []):
                actions[action.get('navigation', action['type'])] += 1
                if 'destinationId' in action:
                    dest = action.get('destination', {})
                    if dest.get('status') != 'resolved':
                        unresolved.append(connection['id'])
                    destinations[action['destinationId']] = {k: dest.get(k) for k in ('id', 'name', 'type')}
    assert not unresolved, (platform, unresolved)
    checked = {'nodesScanned': proto['nodesScanned'], 'connectedNodes': len(proto['connections']), 'truncated': False, 'actions': dict(actions), 'unresolved': []}
    old['bridgePrototypeVerification'][platform] = checked
    old['livePrototypeVerification'][platform] = {'nodesScanned': proto['nodesScanned'], 'connectedNodes': len(proto['connections']), 'reactions': sum(len(c['reactions']) for c in proto['connections']), 'unresolved': [], 'unscannedScreens': []}
    summary[platform] = dict(checked, destinations=list(destinations.values()))
old['livePrototypeVerification']['verifiedAt'] = now
summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
(root / 'verification.json').write_text(json.dumps(old, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
print(json.dumps({'backNavigation': live['backNavigationVerification'], 'prototypeUnresolved': 0}))
