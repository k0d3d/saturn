"""Instant, deterministic tags from a task title.

Mirrors Tags.js so the shell and the offline API agree on the first pass. The
scheduled LLM pass in llm_tags.py refines these tags later.
"""
import re

STOPWORDS = set((
    "a an the and or but if then so to of in on at by for with from "
    "is are was were be been being do does did done have has had i me my we our "
    "you your he she it its they their this that these those will would can could "
    "should may might must not no yes please about into over under again more most "
    "some any all as just also up out off down new now today tomorrow yesterday "
    "next last week month year due mon tue wed thu fri sat sun monday tuesday "
    "wednesday thursday friday saturday sunday"
).split())
WORDS = re.compile(r'[^\W_]+', re.UNICODE)
MAX_TAGS = 8


def from_title(text):
    seen, tags = set(), []
    for raw in WORDS.findall(str(text or '').lower()):
        if len(raw) < 2 or raw.isdigit() or raw in STOPWORDS or raw in seen:
            continue
        seen.add(raw)
        tags.append(raw[:32])
        if len(tags) >= MAX_TAGS:
            break
    return tags


def clean(values):
    """Normalise tags proposed by the model, dropping stopwords and junk."""
    seen, tags = set(), []
    for item in values if isinstance(values, list) else []:
        if not isinstance(item, str):
            continue
        tag = item.strip().lstrip('#').lower()[:32]
        if len(tag) < 2 or tag.isdigit() or tag in STOPWORDS or tag in seen:
            continue
        seen.add(tag)
        tags.append(tag)
        if len(tags) >= 8:
            break
    return tags


def merge_tags(existing, title):
    """Keep curated tags while adding words from a renamed title."""
    seen, tags = set(), []
    all_tags = (existing if isinstance(existing, list) else []) + from_title(title)
    for item in all_tags:
        tag = str(item or '').strip().lower()[:32]
        if not tag or tag in seen:
            continue
        seen.add(tag)
        tags.append(tag)
        if len(tags) >= 12:
            break
    return tags
