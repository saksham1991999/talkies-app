#!/usr/bin/env python3
"""Build the offline film catalog bundled with Talkies.

Sources (no API keys):
  - Wikidata SPARQL: titles, dates, cast, crew, genres, languages, countries.
  - Wikipedia pageimages: poster thumbnail paths.

Output: assets/catalog/catalog.json (compact keys, see lib/data/catalog.dart).

Run: python3 tool/build_catalog.py   (about 15 minutes, resumable via .cache)
"""
import json
import os
import re
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import requests

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'tool', '.cache')
OUT = os.path.join(ROOT, 'assets', 'catalog', 'catalog.json')
# Wikimedia asks for contact details; the app store page is the default.
CONTACT = os.environ.get('TALKIES_CONTACT', 'https://play.google.com/store/apps/details?id=in.talkies.talkies')
UA = f'TalkiesCatalogBuilder/1.0 ({CONTACT}) offline movie diary builder'
SPARQL = 'https://query.wikidata.org/sparql'
S = requests.Session()
S.headers['User-Agent'] = UA

ENWIKI = '?a schema:about ?f; schema:isPartOf <https://en.wikipedia.org/>; schema:name ?w.'
LISTS = {
    'in_film': f'SELECT ?f ?s ?w WHERE {{ ?f wdt:P31 wd:Q11424; wdt:P495 wd:Q668; wikibase:sitelinks ?s. {ENWIKI} }}',
    'intl_film': f'SELECT ?f ?s ?w WHERE {{ ?f wdt:P31 wd:Q11424; wikibase:sitelinks ?s. FILTER(?s >= 30) FILTER NOT EXISTS {{ ?f wdt:P495 wd:Q668 }} {ENWIKI} }}',
    'in_series': f'SELECT ?f ?s ?w WHERE {{ VALUES ?t {{ wd:Q5398426 wd:Q1259759 wd:Q526877 wd:Q15416 }} ?f wdt:P31 ?t; wdt:P495 wd:Q668; wikibase:sitelinks ?s. {ENWIKI} }}',
    'intl_series': f'SELECT ?f ?s ?w WHERE {{ VALUES ?t {{ wd:Q5398426 wd:Q1259759 }} ?f wdt:P31 ?t; wikibase:sitelinks ?s. FILTER(?s >= 35) FILTER NOT EXISTS {{ ?f wdt:P495 wd:Q668 }} {ENWIKI} }}',
}

LANG = {
    'Q1568': 'hi', 'Q5885': 'ta', 'Q8097': 'te', 'Q36236': 'ml', 'Q33673': 'kn',
    'Q9610': 'bn', 'Q1571': 'mr', 'Q58635': 'pa', 'Q5137': 'gu', 'Q33810': 'or',
    'Q29401': 'as', 'Q1860': 'en', 'Q1617': 'ur', 'Q33268': 'bho', 'Q34251': 'tcy',
    'Q34239': 'kok', 'Q9176': 'ko', 'Q5287': 'ja', 'Q150': 'fr', 'Q1321': 'es',
    'Q188': 'de', 'Q652': 'it', 'Q7850': 'zh', 'Q727694': 'zh', 'Q9192': 'zh',
    'Q9186': 'yue', 'Q7737': 'ru', 'Q9168': 'fa', 'Q33823': 'ne', 'Q13267': 'si',
    'Q11059': 'sa', 'Q9217': 'th', 'Q256': 'tr', 'Q13955': 'ar', 'Q5146': 'pt',
    'Q9027': 'sv', 'Q9035': 'da', 'Q9043': 'no', 'Q7411': 'nl', 'Q809': 'pl',
    'Q1412': 'fi', 'Q9288': 'he', 'Q9056': 'cs', 'Q36510': 'mni', 'Q33728': 'raj',
    'Q33455': 'bgc', 'Q33454': 'mai', 'Q56475': 'ha',
}
NATIVE_LABEL_LANGS = ['hi', 'ta', 'te', 'ml', 'kn', 'bn', 'mr', 'pa', 'gu', 'ur', 'or', 'as', 'ko', 'ja', 'zh']

GENRES = [  # (key, regex on the English genre label); first match wins per label
    ('superhero', r'superhero'), ('mythology', r'mytholog|devotional|religious|hindu'),
    ('scifi', r'science fiction|sci-fi|cyberpunk|dystopian'), ('animation', r'anim'),
    ('documentary', r'documentar'), ('biography', r'biograph|biopic'),
    ('historical', r'histor|period|epic'), ('musical', r'musical|music|dance'),
    ('horror', r'horror|supernatural|slasher|zombie'), ('crime', r'crime|gangster|heist|mafia|noir'),
    ('mystery', r'myster|detective|whodunit'), ('thriller', r'thriller|suspense|psycholog'),
    ('action', r'action|martial|masala'), ('war', r'\bwar\b|military'), ('sports', r'sport'),
    ('romance', r'roman'), ('comedy', r'comed|satire|parody'), ('family', r'family|children'),
    ('fantasy', r'fantasy|fairy'), ('adventure', r'adventure|swashbuckler'), ('spy', r'spy|espionage'),
    ('political', r'politic'), ('legal', r'legal|courtroom'), ('coming_of_age', r'coming-of-age|teen'),
    ('drama', r'drama|social'), ('western', r'western'),
]
OTT = [
    ('netflix', r'netflix'), ('prime', r'amazon|prime video'), ('jiohotstar', r'hotstar|jiocinema|voot|disney\+'),
    ('sonyliv', r'sonyliv|sony liv'), ('zee5', r'zee5'), ('aha', r'^aha'), ('sunnxt', r'sun nxt'),
    ('mxplayer', r'mx player'), ('appletv', r'apple tv'), ('hoichoi', r'hoichoi'),
    ('erosnow', r'eros now'), ('altbalaji', r'alt ?balaji'), ('manoramamax', r'manorama ?max'),
]


def cached(name, fn):
    path = os.path.join(CACHE, name + '.json')
    if os.path.exists(path):
        with open(path) as f:
            return json.load(f)
    data = fn()
    with open(path, 'w') as f:
        json.dump(data, f)
    return data


def sparql(query):
    for attempt in range(8):
        try:
            r = S.post(SPARQL, data={'query': query}, headers={'Accept': 'application/sparql-results+json'}, timeout=90)
            if r.status_code == 200:
                return r.json()['results']['bindings']
            wait = int(r.headers.get('Retry-After', 0) or 0) or 2 ** attempt
            print(f'  sparql {r.status_code}, retry in {wait}s', file=sys.stderr)
        except (requests.RequestException, ValueError) as e:
            wait = 2 ** attempt
            print(f'  sparql error {e!r}, retry in {wait}s', file=sys.stderr)
        time.sleep(wait)
    raise RuntimeError('SPARQL failed: ' + query[:200])


def qid(uri):
    return uri.rsplit('/', 1)[-1]


def values(ids):
    return ' '.join('wd:' + i for i in ids)


def chunks(xs, n):
    return [xs[i:i + n] for i in range(0, len(xs), n)]


def fetch_details(batch_no, ids):
    def run():
        v = values(ids)
        props = sparql(f'''SELECT ?f ?p ?v WHERE {{ VALUES ?f {{ {v} }}
          VALUES ?p {{ wdt:P57 wdt:P161 wdt:P136 wdt:P364 wdt:P495 wdt:P750 wdt:P449 wdt:P2047 wdt:P2437 }}
          ?f ?p ?v. }}''')
        dates = sparql(f'''SELECT ?f ?t ?pr ?pl WHERE {{ VALUES ?f {{ {v} }}
          {{ ?f p:P577 ?st. ?st psv:P577 [ wikibase:timeValue ?t; wikibase:timePrecision ?pr ]. OPTIONAL {{ ?st pq:P291 ?pl }} }}
          UNION {{ ?f p:P580 ?st. ?st psv:P580 [ wikibase:timeValue ?t; wikibase:timePrecision ?pr ]. }} }}''')
        langs = ','.join(f'"{l}"' for l in ['en'] + NATIVE_LABEL_LANGS)
        labels = sparql(f'''SELECT ?f ?l WHERE {{ VALUES ?f {{ {v} }} ?f rdfs:label ?l. FILTER(LANG(?l) IN ({langs})) }}''')
        return {'props': props, 'dates': dates, 'labels': labels}
    return cached(f'details_{batch_no}', run)


def fetch_entities(batch_no, ids):
    def run():
        return sparql(f'''SELECT ?e ?l ?s ?iso WHERE {{ VALUES ?e {{ {values(ids)} }}
          OPTIONAL {{ ?e rdfs:label ?l. FILTER(LANG(?l) = "en") }}
          OPTIONAL {{ ?e wikibase:sitelinks ?s }} OPTIONAL {{ ?e wdt:P297 ?iso }} }}''')
    return cached(f'entities_{batch_no}', run)


ACTOR_OCC = 'wd:Q33999 wd:Q10800557 wd:Q10798782 wd:Q2405480 wd:Q2259451 wd:Q948329'


def fetch_actors(batch_no, ids):
    def run():
        rows = sparql(f'''SELECT DISTINCT ?e WHERE {{ VALUES ?e {{ {values(ids)} }} VALUES ?o {{ {ACTOR_OCC} }} ?e wdt:P106 ?o. }}''')
        return [qid(r['e']['value']) for r in rows]
    return cached(f'actors_{batch_no}', run)


def fetch_posters(batch_no, titles):
    def run():
        for attempt in range(6):
            try:
                r = S.get('https://en.wikipedia.org/w/api.php', params={
                    'action': 'query', 'prop': 'pageimages', 'piprop': 'thumbnail', 'pithumbsize': 330,
                    'pilicense': 'any', 'titles': '|'.join(titles), 'redirects': 1,
                    'format': 'json', 'formatversion': 2}, timeout=60)
                if r.status_code == 200:
                    q = r.json().get('query', {})
                    alias = {}
                    for n in q.get('normalized', []) + q.get('redirects', []):
                        alias[n['to']] = alias.get(n['from'], n['from'])
                    out = {}
                    for page in q.get('pages', []):
                        src = page.get('thumbnail', {}).get('source')
                        if src:
                            t = page['title']
                            out[alias.get(t, t)] = src
                    return out
            except (requests.RequestException, ValueError) as e:
                print(f'  wiki error {e!r}', file=sys.stderr)
            time.sleep(2 ** attempt)
        raise RuntimeError('pageimages failed')
    return cached(f'posters_{batch_no}', run)


def trim_date(t, precision):
    m = re.match(r'^\+?(-?\d{4})-(\d\d)-(\d\d)', t)
    if not m:
        return None
    y, mo, d = m.groups()
    if precision >= 11:
        return f'{y}-{mo}-{d}'
    if precision == 10:
        return f'{y}-{mo}'
    if precision == 9:
        return y
    return None


def classify(label, table):
    low = label.lower()
    for key, rx in table:
        if re.search(rx, low):
            return key
    return None


def main():
    os.makedirs(CACHE, exist_ok=True)
    os.makedirs(os.path.dirname(OUT), exist_ok=True)

    items = {}  # qid -> {kind, pop, wiki}
    for name, query in LISTS.items():
        rows = cached('list_' + name, lambda q=query: sparql(q))
        for r in rows:
            i = qid(r['f']['value'])
            items.setdefault(i, {'kind': 's' if 'series' in name else 'f',
                                 'pop': int(r['s']['value']), 'wiki': r['w']['value']})
        print(f'{name}: {len(rows)} rows, total {len(items)}')

    ids = sorted(items)
    batches = chunks(ids, 400)
    with ThreadPoolExecutor(4) as pool:
        details = list(pool.map(lambda a: fetch_details(*a), enumerate(batches)))
    print('details done')

    props, dates, labels = {}, {}, {}
    for d in details:
        for r in d['props']:
            f, p = qid(r['f']['value']), r['p']['value'].rsplit('/', 1)[-1]
            v = r['v']['value']
            props.setdefault(f, {}).setdefault(p, []).append(qid(v) if v.startswith('http') else v)
        for r in d['dates']:
            f = qid(r['f']['value'])
            dates.setdefault(f, []).append((r['t']['value'], int(r['pr']['value']),
                                            qid(r['pl']['value']) if 'pl' in r else None))
        for r in d['labels']:
            labels.setdefault(qid(r['f']['value']), {})[r['l']['xml:lang']] = r['l']['value']

    refs = set()
    for f, pm in props.items():
        for p in ('P57', 'P161', 'P136', 'P364', 'P495', 'P750', 'P449'):
            refs.update(x for x in pm.get(p, []) if re.match(r'^Q\d+$', x))
    refs = sorted(refs)
    print(f'resolving {len(refs)} entities')
    with ThreadPoolExecutor(4) as pool:
        ent_rows = list(pool.map(lambda a: fetch_entities(*a), enumerate(chunks(refs, 700))))
    ent = {}
    for rows in ent_rows:
        for r in rows:
            e = ent.setdefault(qid(r['e']['value']), {'l': None, 's': 0, 'iso': None})
            if 'l' in r:
                ent_l = r['l']['value']
                e['l'] = ent_l
            if 's' in r:
                e['s'] = int(r['s']['value'])
            if 'iso' in r:
                e['iso'] = r['iso']['value']

    cast_ids = sorted({x for pm in props.values() for x in pm.get('P161', []) if re.match(r'^Q\d+$', x)})
    with ThreadPoolExecutor(4) as pool:
        actor_lists = list(pool.map(lambda a: fetch_actors(*a), enumerate(chunks(cast_ids, 700))))
    actors = {a for lst in actor_lists for a in lst}
    print(f'actors: {len(actors)} of {len(cast_ids)} cast members')

    titles = sorted({v['wiki'] for v in items.values()})
    with ThreadPoolExecutor(3) as pool:
        poster_maps = list(pool.map(lambda a: fetch_posters(*a), enumerate(chunks(titles, 50))))
    posters = {}
    for m in poster_maps:
        posters.update(m)
    print(f'posters: {len(posters)}')

    prefix = 'https://upload.wikimedia.org/wikipedia/'
    out = []
    for f in ids:
        meta, pm, lab = items[f], props.get(f, {}), labels.get(f, {})
        wiki = meta['wiki']
        title = lab.get('en') or re.sub(r'\s*\([^)]*\)$', '', wiki)
        rec = {'id': f, 't': title}
        lang = []
        for x in pm.get('P364', []):
            code = LANG.get(x) or (ent.get(x, {}).get('l') or '').lower() or None
            if code and code not in lang:
                lang.append(code)
        for l in lang:
            nat = lab.get(l)
            if nat and nat != title and re.search(r'[^\x00-\x7F]', nat):
                rec['o'] = nat
                break
        ds = dates.get(f, [])
        india = [d for d in ds if d[2] == 'Q668']
        best = None
        for t, pr, _ in sorted(india or ds, key=lambda d: (d[0].lstrip('+'), -d[1])):
            best = trim_date(t, pr)
            if best:
                break
        if best:
            rec['d'] = best
            rec['y'] = int(best[:4])
        dur = [float(x) for x in pm.get('P2047', []) if re.match(r'^[\d.]+$', x)]
        if dur and meta['kind'] == 'f':
            rec['rt'] = round(max(dur))
        dirs = [ent[x]['l'] for x in pm.get('P57', []) if ent.get(x, {}).get('l')]
        if dirs:
            rec['dir'] = sorted(set(dirs), key=dirs.index)[:3]
        cast = sorted({x for x in pm.get('P161', []) if ent.get(x, {}).get('l')},
                      key=lambda x: (x not in actors, -ent[x]['s']))
        if cast:
            rec['cast'] = [ent[x]['l'] for x in cast[:6]]
        gs = []
        for x in pm.get('P136', []):
            g = classify(ent.get(x, {}).get('l') or '', GENRES)
            if g and g not in gs:
                gs.append(g)
        if gs:
            rec['g'] = gs[:4]
        if lang:
            rec['l'] = lang[:3]
        cs = []
        for x in pm.get('P495', []):
            iso = ent.get(x, {}).get('iso')
            if iso and iso not in cs:
                cs.append(iso)
        if cs:
            rec['c'] = cs[:4]
        otts = []
        for x in pm.get('P750', []) + pm.get('P449', []):
            o = classify(ent.get(x, {}).get('l') or '', OTT)
            if o and o not in otts:
                otts.append(o)
        if otts:
            rec['ott'] = otts
        seasons = [x for x in pm.get('P2437', []) if re.match(r'^\d+$', x)]
        if meta['kind'] == 's':
            rec['k'] = 's'
            if seasons:
                rec['sn'] = max(int(x) for x in seasons)
        p = posters.get(wiki)
        if p and p.startswith(prefix):
            rec['p'] = p[len(prefix):].split('?')[0]
        if wiki != title:
            rec['w'] = wiki
        rec['pop'] = meta['pop']
        out.append(rec)

    out.sort(key=lambda r: -r['pop'])
    with open(OUT, 'w', encoding='utf-8') as fh:
        json.dump({'built': time.strftime('%Y-%m-%d'), 'items': out}, fh,
                  ensure_ascii=False, separators=(',', ':'))
    print(f'wrote {len(out)} items, {os.path.getsize(OUT) / 1e6:.1f} MB -> {OUT}')


if __name__ == '__main__':
    main()
