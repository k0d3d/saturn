"""Config for features that do not have a settings screen yet.

Stored in workspace.json so the live shell and offline scripts agree. Mirrors
Settings.js; unknown keys are dropped on write and defaults fill the rest.
"""
import math

DEFAULTS = {
    'llm': {
        'enabled': True,
        'model': 'opencode/deepseek-v4.1-flash-free',
        'hours': [9, 18],
        'batch': 20,
        'timeout': 120,
        'prompt': '',
    }
}


def fresh():
    return {'llm': dict(DEFAULTS['llm'], hours=list(DEFAULTS['llm']['hours']))}


def _int_in(value, low, high):
    return isinstance(value, int) and not isinstance(value, bool) and low <= value <= high


def normalise(raw):
    base = fresh()
    value = raw.get('llm') if isinstance(raw, dict) else None
    value = value if isinstance(value, dict) else {}
    hours = base['llm']['hours']
    if isinstance(value.get('hours'), list) and all(_int_in(hour, 0, 23) for hour in value['hours']):
        hours = list(dict.fromkeys(value['hours']))
    model = value.get('model')
    prompt = value.get('prompt')
    return {'llm': {
        'enabled': value.get('enabled') if isinstance(value.get('enabled'), bool) else base['llm']['enabled'],
        'model': model.strip()[:120] if isinstance(model, str) and model.strip() else base['llm']['model'],
        'hours': hours,
        'batch': value['batch'] if _int_in(value.get('batch'), 1, 100) else base['llm']['batch'],
        'timeout': value['timeout'] if _int_in(value.get('timeout'), 10, 600) else base['llm']['timeout'],
        'prompt': prompt[:2000] if isinstance(prompt, str) else base['llm']['prompt'],
    }}
