#!/usr/bin/env python3
"""App Store Connect: audit the live listing, then push the repo's copy.

Auth uses the key already on this machine:
  ~/.appstoreconnect/issuer_id
  ~/.appstoreconnect/private_keys/AuthKey_<KEY_ID>.p8
Set ASC_KEY_ID to override the key id. The key is never printed.

Usage:
  python3 tool/asc.py audit                  read-only diff: repo vs live
  python3 tool/asc.py push                   show what would change
  python3 tool/asc.py push --apply           write metadata to App Store Connect
  python3 tool/asc.py push --apply --screenshots
  python3 tool/asc.py screenshots            plan the screenshot upload, locale by locale
  python3 tool/asc.py screenshots --apply    upload only what is missing, resumable
  python3 tool/asc.py screenshots --apply --replace-changed
                                             also swap cards whose bytes changed
  python3 tool/asc.py cpp --apply            create the 8 custom product pages
  python3 tool/asc.py ppo --apply            create the product page experiment
  python3 tool/asc.py events --apply         create the 4 in-app events
  python3 tool/asc.py submit --apply         attach the newest valid build and submit for review
  python3 tool/asc.py cancel --apply         pull a submission back so the build can be replaced

Re-running is safe: every write looks up what exists first. Deletes happen only
with `--repair-stuck` (screenshot records Apple never took bytes for) or
`--reset-display` (every record in one display set, including ones Apple already
holds, because a gap in the middle of a deck cannot be fixed by appending). Both
then re-upload what they removed in the same run.

Submitting releases on approval (`releaseType AFTER_APPROVAL`), the app's
existing setting, so no release date has to be nursed afterwards. `cancel` is
the escape hatch: a submitted version's build cannot be swapped, so replacing a
build means cancel, swap, submit again.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path

import jwt
import requests

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / 'tool'))
sys.path.insert(0, str(ROOT / 'store'))

import locales  # noqa: E402
import listing_data  # noqa: E402

BUNDLE = 'in.talkies.talkies'
API = 'https://api.appstoreconnect.apple.com'
KEYDIR = Path(os.path.expanduser('~/.appstoreconnect'))
STATE = ROOT / 'store' / 'asc_state.json'

# Apple's enum for a 6.9-inch iPhone (1320 x 2868). Older listings used the
# 6.5-inch enum; both are accepted.
IPHONE_69 = 'APP_IPHONE_67'
IPAD_13 = 'APP_IPAD_PRO_3GEN_129'
# The English listing also carries a 6.5-inch (1242 x 2688) set, uploaded before
# the 6.9-inch one existed. It is served to older devices, so it has to stay in
# step with the deck rather than keep whatever was there on day one.
IPHONE_65 = 'APP_IPHONE_65'


# Apple's locale enum is narrower than Xcode's language IDs. Thirteen of the
# repo's 50 codes need a region suffix before App Store Connect accepts them;
# everything else passes through unchanged. Verified against the live API:
# 'ar', 'bn', 'gu', 'kn', 'ml', 'mr', 'nl', 'or', 'pa', 'sl', 'ta', 'te' and
# 'ur' are all rejected with ENTITY_ERROR.ATTRIBUTE.INVALID until suffixed.
APPLE_LOCALE = {
    'ar': 'ar-SA', 'bn': 'bn-BD', 'gu': 'gu-IN', 'kn': 'kn-IN', 'ml': 'ml-IN',
    'mr': 'mr-IN', 'nl': 'nl-NL', 'or': 'or-IN', 'pa': 'pa-IN', 'sl': 'sl-SI',
    'ta': 'ta-IN', 'te': 'te-IN', 'ur': 'ur-PK',
}


def apple_locale(code: str) -> str:
    return APPLE_LOCALE.get(code, code)


class ASC:
    def __init__(self, key_id: str | None = None, issuer: str | None = None):
        self.key_id = key_id or os.environ.get('ASC_KEY_ID') or self._detect_key()
        self.issuer = issuer or (KEYDIR / 'issuer_id').read_text().strip()
        self.key = (KEYDIR / 'private_keys' / f'AuthKey_{self.key_id}.p8').read_text()
        self.session = requests.Session()
        self._auth()

    @staticmethod
    def _detect_key() -> str:
        keys = sorted((KEYDIR / 'private_keys').glob('AuthKey_*.p8'))
        if not keys:
            raise SystemExit('no AuthKey_*.p8 in ~/.appstoreconnect/private_keys')
        return keys[0].stem.replace('AuthKey_', '')

    def _auth(self) -> None:
        now = int(time.time())
        token = jwt.encode(
            {'iss': self.issuer, 'iat': now, 'exp': now + 900, 'aud': 'appstoreconnect-v1'},
            self.key,
            algorithm='ES256',
            headers={'kid': self.key_id, 'typ': 'JWT'},
        )
        self.session.headers.update({'Authorization': f'Bearer {token}'})

    def request(self, method: str, path: str, **kwargs):
        url = path if path.startswith('http') else API + path
        for attempt in range(4):
            r = self.session.request(method, url, timeout=120, **kwargs)
            if r.status_code == 429:
                time.sleep(int(r.headers.get('Retry-After', '5')))
                continue
            if r.status_code >= 400:
                text = r.text[:600]
                raise SystemExit(f'{method} {path} -> {r.status_code}\n{text}')
            if r.status_code == 204 or not r.content:
                return None
            return r.json()
        raise SystemExit(f'{method} {path} -> rate limited')

    def get(self, path: str, **params):
        return self.request('GET', path, params=params or None)

    def post(self, path: str, payload: dict):
        return self.request('POST', path, json=payload)

    def patch(self, path: str, payload: dict):
        return self.request('PATCH', path, json=payload)

    def all(self, path: str, **params) -> list[dict]:
        out: list[dict] = []
        data = self.get(path, limit=200, **params)
        while data:
            out += data.get('data', [])
            nxt = data.get('links', {}).get('next')
            if not nxt:
                break
            data = self.get(nxt)
        return out

    def app_id(self) -> str:
        data = self.get('/v1/apps', **{'filter[bundleId]': BUNDLE})
        if not data.get('data'):
            raise SystemExit(f'no app with bundle id {BUNDLE}')
        return data['data'][0]['id']


# ---------------------------------------------------------------------------
# Reading the live app


def app_info_all(api: ASC, app: str) -> list[dict]:
    """Every appInfo record with its own localizations.

    A released app carries one appInfo per state (READY_FOR_DISTRIBUTION plus a
    PREPARE_FOR_SUBMISSION copy once a new version exists). Only the
    PREPARE_FOR_SUBMISSION record accepts writes; the released one 409s.
    """
    out = []
    for info in api.all(f'/v1/apps/{app}/appInfos'):
        locs = {
            x['attributes']['locale']: x
            for x in api.all(f'/v1/appInfos/{info["id"]}/appInfoLocalizations')
        }
        out.append({'id': info['id'], 'state': info['attributes'].get('state'), 'locales': locs})
    return out


def app_info(api: ASC, app: str) -> dict:
    """The record we may write to, falling back to the live one.

    A released app keeps its own appInfo (READY_FOR_DISTRIBUTION) next to the
    one belonging to the version in flight. That in-flight record changes state
    as the version moves: PREPARE_FOR_SUBMISSION, then WAITING_FOR_REVIEW, then
    IN_REVIEW. Looking only for PREPARE_FOR_SUBMISSION meant that once a version
    was submitted, every write went to the released record, which rejects them,
    and the plan claimed 50 app-info localizations were missing.
    """
    rows = app_info_all(api, app)
    in_flight = [r for r in rows if r['state'] != 'READY_FOR_DISTRIBUTION']
    for row in in_flight:
        if row['state'] == 'PREPARE_FOR_SUBMISSION':
            return row
    if in_flight:
        return in_flight[0]
    return rows[0]


def versions(api: ASC, app: str) -> list[dict]:
    return api.all(f'/v1/apps/{app}/appStoreVersions', **{'filter[platform]': 'IOS'})


def version_state(v: dict) -> str | None:
    """The version's state, whichever field the record reports it in.

    `appStoreState` is the older field and is what most records carry; newer ones
    also carry `appVersionState`, whose vocabulary is narrower (it has no
    REJECTED, for instance). appInfos reports plain `state`.
    """
    a = v['attributes']
    return a.get('appStoreState') or a.get('appVersionState') or a.get('state')


def current_version(api: ASC, app: str) -> dict | None:
    """The editable version when one exists, else the newest live version."""
    vs = versions(api, app)
    for v in vs:
        if version_state(v) == 'PREPARE_FOR_SUBMISSION':
            return v
    return vs[0] if vs else None


def version_locales(api: ASC, version: str) -> dict[str, dict]:
    rows = api.all(f'/v1/appStoreVersions/{version}/appStoreVersionLocalizations')
    return {x['attributes']['locale']: x for x in rows}


def screenshot_sets(api: ASC, loc_id: str) -> dict[str, dict]:
    rows = api.all(f'/v1/appStoreVersionLocalizations/{loc_id}/appScreenshotSets')
    return {x['attributes']['screenshotDisplayType']: x for x in rows}


def pubspec_version() -> str:
    """The marketing version in pubspec.yaml, so a new release names itself.

    Raises rather than guessing. A silent fallback to 1.0.0 would let `push
    --apply` create an App Store version numbered 1.0.0, and a version record
    cannot be deleted through the API, so the mistake would be permanent.
    """
    m = re.search(r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)', (ROOT / 'pubspec.yaml').read_text(), re.M)
    if not m:
        raise SystemExit('no marketing version in pubspec.yaml (expected `version: 1.2.3+4`)')
    return m.group(1)


def editable_version(api: ASC, app: str, version_string: str | None = None, create: bool = False) -> dict | None:
    """The version we may edit, and optionally create one when none is editable.

    Creating is opt-in. A version record cannot be deleted through the API, so a
    command that only wants to read metadata must never leave one behind: this
    used to POST on every call, which meant a read-only command on a submitted
    app either failed with a confusing duplicate error or, after a version bump,
    quietly created a stray draft.
    """
    for v in versions(api, app):
        if version_state(v) == 'PREPARE_FOR_SUBMISSION':
            return v
    if not create:
        return None
    want = version_string or pubspec_version()
    # A version with this number already exists but is past preparing (it may be
    # waiting for review, or in review). Correct that one: its metadata is still
    # writable, and POSTing the same number again is rejected as a duplicate.
    # A released version is different: its localizations are read-only, so
    # returning it would fail halfway through a push. Say so instead.
    for v in versions(api, app):
        if v['attributes'].get('versionString') != want:
            continue
        state = version_state(v)
        # States where the version is out of our hands: approved and released, or
        # approved and waiting for its release date. `READY_FOR_SALE` is the live
        # one, `READY_FOR_DISTRIBUTION` the gap before an AFTER_APPROVAL release,
        # and older records report the same thing through `appStoreState` only.
        # Localizations are read-only in all of them, so returning the record
        # would fail halfway through a push.
        if state in ('READY_FOR_SALE', 'READY_FOR_DISTRIBUTION', 'REMOVED_FROM_SALE', 'DEVELOPER_REMOVED_FROM_SALE'):
            raise SystemExit(
                f'{want} is already released ({state}), and a released version cannot be edited. '
                'Bump `version:` in pubspec.yaml to start the next release.')
        return v
    return api.post('/v1/appStoreVersions', {
        'data': {
            'type': 'appStoreVersions',
            'attributes': {
                'versionString': want,
                'platform': 'IOS',
                'releaseType': 'AFTER_APPROVAL',
            },
            'relationships': {'app': {'data': {'type': 'apps', 'id': app}}},
        }
    })['data']


def repo_listings() -> dict[str, dict]:
    """Repo metadata keyed by the locale App Store Connect actually stores."""
    return {
        apple_locale(c): listing_data.load(c)
        for c in locales.store_codes()
        if listing_data.path(c).exists()
    }


# ---------------------------------------------------------------------------
# Metadata


def metadata_diff(api: ASC, app: str) -> dict:
    info = app_info(api, app)
    vs = current_version(api, app)
    live = version_locales(api, vs['id']) if vs else {}
    return {'info': info, 'live_version_locales': live, 'repo': repo_listings(), 'versions': versions(api, app)}


def cmd_audit(api: ASC, args) -> int:
    app = api.app_id()
    d = metadata_diff(api, app)
    info, live = d['info'], d['live_version_locales']
    repo = d['repo']
    print(f'app {app}  info state {info["state"]}')
    print(f'versions: ' + ', '.join(f'{v["attributes"].get("versionString")}({version_state(v)})' for v in d['versions']))
    print('appInfo records: ' + ', '.join(f'{r["state"]} {len(r["locales"])} locales' for r in app_info_all(api, app)))
    print(f'live metadata locales: {len(info["locales"])} info, {len(live)} version')
    print(f'repo locales: {len(repo)}  ({len(APPLE_LOCALE)} use an Apple region suffix)')
    missing = sorted(set(repo) - set(info['locales']))
    missing_v = sorted(set(repo) - set(live))
    print(f'  info missing: {len(missing)}  {", ".join(missing[:12])}')
    print(f'  version missing: {len(missing_v)}  {", ".join(missing_v[:12])}')
    changed = []
    for code, data in repo.items():
        row = info['locales'].get(code)
        if row and (row['attributes'].get('name') != data['name'] or row['attributes'].get('subtitle') != data['subtitle']):
            changed.append(f'{code}.name/subtitle')
        v = live.get(code)
        if v and v['attributes'].get('description') != data['description']:
            changed.append(f'{code}.description')
    print(f'  text differs: {len(changed)}  {", ".join(changed[:8])}')
    if live:
        first = live.get('en-US') or next(iter(live.values()))
        sets = screenshot_sets(api, first['id'])
        print(f'  screenshot sets on {first["attributes"]["locale"]}: {", ".join(sets) or "none"}')
    print(f'  custom product pages: {len(api.all(f"/v1/apps/{app}/appCustomProductPages"))}')
    print(f'  product page experiments: {len(api.all(f"/v1/apps/{app}/appStoreVersionExperimentsV2"))}')
    print(f'  in-app events: {len(api.all(f"/v1/apps/{app}/appEvents"))}')
    return 0


def cmd_push(api: ASC, args) -> int:
    app = api.app_id()
    # `create=True`: pushing metadata is the one command that may open a new
    # version, and only when it is really writing.
    version = editable_version(api, app, create=True) if args.apply else current_version(api, app)
    # Resolve the appInfo and the version's locales *after* the editable version
    # exists: creating a version spawns a new PREPARE_FOR_SUBMISSION appInfo,
    # and the released one rejects writes.
    info = app_info(api, app)
    live = version_locales(api, version['id']) if version else {}
    repo = repo_listings()
    print(f'version {version["attributes"].get("versionString") if version else "-"}  '
          f'state {version_state(version) if version else "-"}  '
          f'info {info["state"]}')

    plans: list[str] = []
    for code, data in sorted(repo.items()):
        cur = info['locales'].get(code)
        if cur is None:
            plans.append(f'+ app info {code}')
        elif (cur['attributes'].get('name'), cur['attributes'].get('subtitle')) != (data['name'], data['subtitle']):
            plans.append(f'~ app info {code}')
        v = live.get(code)
        if v is None:
            plans.append(f'+ version {code}')
        elif v['attributes'].get('description') != data['description'] or v['attributes'].get('keywords') != data['keywords']:
            plans.append(f'~ version {code}')
    for p in plans:
        print('  ' + p)
    print(f'{len(plans)} change(s)')
    if not args.apply:
        print('dry run: pass --apply to write')
        return 0

    for code, data in sorted(repo.items()):
        cur = info['locales'].get(code)
        attrs = {
            'name': data['name'],
            'subtitle': data['subtitle'],
            'privacyPolicyUrl': listing_data.URLS['privacyPolicyUrl'],
        }
        if cur is None:
            api.post('/v1/appInfoLocalizations', {
                'data': {
                    'type': 'appInfoLocalizations',
                    'attributes': {'locale': code, **attrs},
                    'relationships': {'appInfo': {'data': {'type': 'appInfos', 'id': info['id']}}},
                }
            })
        elif cur['attributes'].get('name') != data['name'] or cur['attributes'].get('subtitle') != data['subtitle']:
            api.patch(f'/v1/appInfoLocalizations/{cur["id"]}', {
                'data': {'type': 'appInfoLocalizations', 'id': cur['id'], 'attributes': attrs}
            })

        v = version_locales(api, version['id']).get(code)
        vattrs = {
            'description': data['description'],
            'keywords': data['keywords'],
            'promotionalText': data['promotionalText'],
            'whatsNew': data['whatsNew'],
            'supportUrl': listing_data.URLS['supportUrl'],
            'marketingUrl': listing_data.URLS['marketingUrl'],
        }
        if v is None:
            v = api.post('/v1/appStoreVersionLocalizations', {
                'data': {
                    'type': 'appStoreVersionLocalizations',
                    'attributes': {'locale': code, **vattrs},
                    'relationships': {'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}}},
                }
            })['data']
        else:
            api.patch(f'/v1/appStoreVersionLocalizations/{v["id"]}', {
                'data': {'type': 'appStoreVersionLocalizations', 'id': v['id'], 'attributes': vattrs}
            })
        if args.screenshots:
            # Screenshot folders are named with the storefront code, not Apple's.
            upload_local_screenshots(api, v['id'], store_code(code))
    print('metadata written. Submit for review in App Store Connect when ready.')
    return 0


# ---------------------------------------------------------------------------
# Screenshots


def put_bytes(operations: list[dict], blob: bytes) -> None:
    for op in operations:
        offset = int(op.get('offset', 0))
        length = int(op.get('length', 0))
        headers = {h['name']: h['value'] for h in op.get('requestHeaders', [])}
        r = requests.request(op['method'], op['url'], headers=headers, data=blob[offset:offset + length], timeout=300)
        if r.status_code >= 400:
            raise SystemExit(f'screenshot upload failed: {r.status_code} {r.text[:200]}')


# Apple locale -> the code the repo names its storefront folders with. The two
# differ for the 13 codes in APPLE_LOCALE (`ta-IN` -> `ta`), and only there:
# every other folder on disk is named exactly like the Apple locale (`de-DE`,
# `zh-Hans`). store/appstore-localized/README.md documents the same rule.
STORE_CODE = {apple: store for store, apple in APPLE_LOCALE.items()}


def store_code(apple: str) -> str:
    """The folder name for an App Store Connect locale."""
    return STORE_CODE.get(apple, apple)


def screenshot_dirs(code: str) -> list[tuple[str, str, Path]]:
    """(display label, display type, directory) for one storefront code."""
    if code.startswith('en'):
        base = ROOT / 'store' / 'appstore'
    else:
        base = ROOT / 'store' / 'appstore-localized' / code
    dirs = [('iphone-6.9', IPHONE_69, base / 'iphone-6.9'), ('ipad-13', IPAD_13, base / 'ipad-13')]
    # Only en-US ever had a 6.5-inch set: it was uploaded before the 6.9-inch one
    # existed. The other English storefronts were added later without it, so
    # looking for one there would create a set Apple never asked for.
    if code == 'en-US' and (base / 'iphone-6.5').is_dir():
        dirs.insert(0, ('iphone-6.5', IPHONE_65, base / 'iphone-6.5'))
    return dirs


def screenshot_files(code: str) -> list[tuple[str, list[Path]]]:
    """Display type and files for one locale, in the order the deck reads.

    English uses the shipped `store/appstore` sets. Other locales use
    `store/appstore-localized/<code>/iphone-6.9` and `.../ipad-13`, written by
    tool/store_frames.py after a localized capture run. `<code>` is the
    storefront code (store_code()), not the ARB app code.
    """
    return [(display, sorted(d.glob('*.png'))) for _label, display, d in screenshot_dirs(code)]


def md5_file(path: Path) -> str:
    h = hashlib.md5()
    with open(path, 'rb') as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b''):
            h.update(chunk)
    return h.hexdigest()


def live_screenshots(api: ASC, set_id: str) -> list[dict]:
    """Screenshots in one set, with the fields the plan needs.

    The list endpoint omits `sourceFileChecksum` unless it is asked for, and a
    missing field is not the same as a missing upload: reading the default
    sparse response made every finished screenshot look unfinished. Ask for
    the fields explicitly, then re-read any record that still comes back
    without a checksum so the plan never guesses.
    """
    rows = api.all(
        f'/v1/appScreenshotSets/{set_id}/appScreenshots',
        **{'fields[appScreenshots]': 'fileName,fileSize,sourceFileChecksum,assetDeliveryState'},
    )
    for i, row in enumerate(rows):
        if row['attributes'].get('sourceFileChecksum') is None:
            full = api.get(f'/v1/appScreenshots/{row["id"]}', **{
                'fields[appScreenshots]': 'fileName,fileSize,sourceFileChecksum,assetDeliveryState',
            })
            rows[i] = full['data']
    return rows


def screenshot_plan(files: list[Path], existing: list[dict]) -> dict:
    """What to upload for one display type, given what Apple already holds.

    Pure: no writes. Never asks for a delete. `upload` keeps filename order so a
    resumed run appends where the last one stopped, and no upload is attempted
    when anything about the existing set is off, because a gap in the middle of
    a deck cannot be fixed by appending.
    """
    res = {'upload': [], 'skip': 0, 'fail': [], 'note': [], 'held': 0, 'changed': []}
    if not files:
        res['note'].append('no files on disk')
        return res
    want = [f.name for f in files]
    by_name: dict[str, list[dict]] = {}
    for x in existing:
        a = x['attributes']
        state = a.get('assetDeliveryState') or {}
        by_name.setdefault(a.get('fileName'), []).append(
            {'checksum': a.get('sourceFileChecksum'), 'state': state.get('state'), 'errors': state.get('errors') or []}
        )
    have = [x['attributes'].get('fileName') for x in existing]
    if existing and have != want[:len(have)]:
        res['fail'].append('live order is not the disk order: ' + ', '.join(str(n) for n in have))
    for f in files:
        recs = by_name.get(f.name) or []
        if not recs:
            res['upload'].append(f)
            continue
        if len(recs) > 1:
            res['fail'].append(f'{f.name}: {len(recs)} live records share this file name')
            continue
        rec = recs[0]
        if rec['state'] == 'FAILED':
            detail = '; '.join(f'{e.get("code")}: {e.get("description")}' for e in rec['errors']) or 'no detail'
            res['fail'].append(f'{f.name}: Apple FAILED ({detail})')
        elif not rec['checksum']:
            res['fail'].append(f'{f.name}: live record has no checksum, the upload never finished. '
                               'Re-run with --repair-stuck to delete the empty record and upload it again.')
        elif rec['checksum'] != md5_file(f):
            # Not a failure to report and stop on: the bytes on disk are newer
            # than the record. `changed` carries it for --replace-changed.
            res['changed'].append(f)
        elif rec['state'] not in (None, 'COMPLETE'):
            res['fail'].append(f'{f.name}: live state {rec["state"]}')
        else:
            res['skip'] += 1
    if res['fail'] and res['upload']:
        res['held'] = len(res['upload'])
        res['note'].append(f'held {res["held"]} upload(s) so the deck stays a clean prefix')
        res['upload'] = []
    return res


def upload_one(api: ASC, set_id: str, path: Path) -> None:
    """Reserve, PUT the bytes, then finalize. One file, all three steps."""
    blob = path.read_bytes()
    created = api.post('/v1/appScreenshots', {
        'data': {
            'type': 'appScreenshots',
            'attributes': {'fileName': path.name, 'fileSize': len(blob)},
            'relationships': {'appScreenshotSet': {'data': {'type': 'appScreenshotSets', 'id': set_id}}},
        }
    })['data']
    put_bytes(created['attributes']['uploadOperations'], blob)
    payload = {
        'data': {
            'type': 'appScreenshots',
            'id': created['id'],
            'attributes': {'uploaded': True, 'sourceFileChecksum': hashlib.md5(blob).hexdigest()},
        }
    }
    # The finalize PATCH is the only step whose failure leaves an orphan record
    # behind (no checksum, no way to re-issue upload operations), so retry it
    # before giving up.
    for attempt in range(3):
        try:
            api.patch(f'/v1/appScreenshots/{created["id"]}', payload)
            return
        except BaseException:
            if attempt == 2:
                raise
            time.sleep(2 + 3 * attempt)


def reset_display(api: ASC, loc_id: str, code: str, display: str) -> list[str]:
    """Delete every screenshot in one display set so it can be rebuilt in order.

    Apple appends a new screenshot to the end of a set, so a single replaced file
    in the middle leaves the deck out of order. Rebuilding the set is the only
    way back. The caller re-uploads every file immediately.
    """
    row = screenshot_sets(api, loc_id).get(display)
    if row is None:
        return []
    gone: list[str] = []
    for shot in live_screenshots(api, row['id']):
        api.request('DELETE', f'/v1/appScreenshots/{shot["id"]}')
        gone.append(str(shot['attributes'].get('fileName')))
    return gone


def repair_stuck(api: ASC, loc_id: str, code: str) -> list[str]:
    """Remove screenshot records that no upload can ever finish.

    A record that is AWAITING_UPLOAD with no checksum and no upload operations
    is a reservation Apple will not reissue. It blocks the ordered deck, so it
    is deleted and re-created. Only that exact state is touched: anything with
    bytes, a checksum or a COMPLETE asset is left alone, and the delete is
    scoped to this locale's own sets.
    """
    removed: list[str] = []
    for display, files in screenshot_files(code):
        row = screenshot_sets(api, loc_id).get(display)
        if row is None:
            continue
        for shot in live_screenshots(api, row['id']):
            a = shot['attributes']
            state = (a.get('assetDeliveryState') or {}).get('state')
            if a.get('sourceFileChecksum') or state != 'AWAITING_UPLOAD':
                continue
            if a.get('assetToken') or a.get('uploadOperations'):
                continue
            api.request('DELETE', f'/v1/appScreenshots/{shot["id"]}')
            removed.append(f'{display}/{a.get("fileName")} ({shot["id"]})')
    return removed


class RebuildIncomplete(RuntimeError):
    """A deck was left short because its tail could not be put back.

    Deliberately not a `SystemExit`: `sync_locale` catches `BaseException` around
    each upload so one bad card does not stop the rest, and that also swallowed the
    old `SystemExit`. A half-empty deck has to stop the whole run, because every
    later set the command touches makes the mess bigger, so this is raised where
    `sync_locale` re-raises it and left to propagate.
    """


def replace_changed(api: ASC, set_id: str, files: list[Path], changed: list[Path]) -> list[str]:
    """Replace cards whose disk bytes no longer match the live record.

    Apple appends a new screenshot, so deleting one card in the middle and
    re-adding it would move it to the end and scramble the deck. The tail from
    the first changed card is therefore deleted as a block and re-uploaded in
    order: everything before it is untouched, and the appends land where they
    belong.

    The delete has to come first: a set holds at most 10 cards per size, and
    uploading the replacements before removing the old ones would briefly hold
    more than that. The cost is a window where the tail is short, so a failure
    here is reported with the exact cards now missing and the command to fix it,
    and `apply` never submits a version on its own. Re-running is what repairs
    it: the plan sees the missing cards as uploads.
    """
    if not changed:
        return []
    names = [f.name for f in files]
    first = min(names.index(f.name) for f in changed)
    tail = files[first:]
    removed: list[str] = []
    for shot in live_screenshots(api, set_id):
        name = shot['attributes'].get('fileName')
        if name in names and names.index(name) >= first:
            api.request('DELETE', f'/v1/appScreenshots/{shot["id"]}')
            removed.append(f'{name} ({shot["id"]})')
    done: list[str] = []
    try:
        for f in tail:
            upload_one(api, set_id, f)
            done.append(f.name)
    except BaseException as exc:
        missing = [f.name for f in tail if f.name not in done]
        raise RebuildIncomplete(
            f'the tail of this deck is now incomplete: {len(missing)} card(s) missing '
            f'({", ".join(missing[:4])}{"..." if len(missing) > 4 else ""}). '
            f'The first {len(done)} went back. Nothing was submitted: run the same command '
            f'again to upload the rest, and do not submit this version until the plan reports '
            f'0 changed and 0 to upload. Cause: {exc}') from exc
    # Prove the deck is whole and in order rather than trusting the uploads.
    live = [s['attributes'].get('fileName') for s in live_screenshots(api, set_id)]
    expected = names
    if live != expected:
        raise RebuildIncomplete(
            f'the deck does not match disk after the rebuild: Apple holds {live}, disk has '
            f'{expected}. Re-run with --replace-changed once the cause is fixed; do not submit '
            f'this version while they disagree.')
    return removed


def sync_locale(api: ASC, loc_id: str, code: str, apply: bool, replace: bool = False) -> dict:

    """Upload only what one locale is missing. Never deletes a set or a file.

    With `replace`, a card whose checksum differs is replaced as well, by
    rebuilding the tail of its deck (see `replace_changed`). Off by default so
    an ordinary run cannot move a screenshot Apple already holds.
    """
    out = {'code': code, 'rows': {}, 'uploaded': 0, 'skipped': 0, 'fail': [], 'notes': []}
    wanted = screenshot_files(code)
    if not any(files for _, files in wanted):
        out['notes'].append('no source files on disk')
        return out
    sets = screenshot_sets(api, loc_id)
    for display, files in wanted:
        row = sets.get(display)
        existing = live_screenshots(api, row['id']) if row else []
        plan = screenshot_plan(files, existing)
        created = False
        if row is None and plan['upload']:
            if apply:
                row = api.post('/v1/appScreenshotSets', {
                    'data': {
                        'type': 'appScreenshotSets',
                        'attributes': {'screenshotDisplayType': display},
                        'relationships': {'appStoreVersionLocalization': {
                            'data': {'type': 'appStoreVersionLocalizations', 'id': loc_id}}},
                    }
                })['data']
                created = True
            else:
                created = True
        done = 0
        swapped = 0
        # Replacing deletes live records and re-sends the tail, so it is only safe
        # on a clean deck. A FAILED card or a live order that disagrees with disk
        # means the set needs a person, not a rebuild: fall through to the held
        # path, which uploads nothing and reports the failures.
        tail = 0
        if replace and plan['changed']:
            names = [f.name for f in files]
            tail = len(files) - min(names.index(f.name) for f in plan['changed'])
        if apply and row is not None and replace and plan['changed'] and not plan['fail']:
            try:
                gone = replace_changed(api, row['id'], files, plan['changed'])
                swapped = len(gone)
                done = tail
                out['notes'].append(f'{display}: replaced {swapped}, re-uploaded {done}')
            except RebuildIncomplete:
                # Propagate: the tail of this deck is short, and carrying on to the
                # next set would leave more decks short instead of stopping at one.
                raise
            except BaseException as exc:
                out['fail'].append(f'{display}: replace failed: {exc}')
        elif apply and row is not None:
            for f in plan['upload']:
                try:
                    upload_one(api, row['id'], f)
                    done += 1
                except BaseException as exc:  # SystemExit from request(), plus HTTP errors
                    out['fail'].append(f'{display}/{f.name}: {exc}')
                    break
        else:
            # The dry run has to report the same work `--apply` would do: a
            # replace rebuilds the whole tail, not just the changed cards.
            done = len(plan['upload']) + tail
        out['uploaded'] += done
        out['skipped'] += plan['skip']
        out['fail'] += [f'{display}/{m}' for m in plan['fail']]
        out['notes'] += plan['note']
        out['rows'][display] = {'upload': done, 'skip': plan['skip'],
                                 'fail': len(plan['fail']), 'created': created,
                                 'changed': len(plan['changed']),
                                 'pending': len(plan['upload']) - done if apply else len(plan['upload'])}
    return out


def upload_local_screenshots(api: ASC, loc_id: str, code: str) -> None:
    """Kept for `push --screenshots`: now resumable instead of duplicating."""
    out = sync_locale(api, loc_id, code, apply=True)
    print(f'  screenshots {code}: {out["uploaded"]} uploaded, {out["skipped"]} already there'
          + (f', {len(out["fail"])} failed' if out['fail'] else ''))
    for m in out['fail']:
        print(f'    {m}')


def cmd_screenshots(api: ASC, args) -> int:
    app = api.app_id()
    # Never create a version here: this command touches screenshots only.
    version = current_version(api, app)
    if version is None:
        print('no App Store version found')
        return 1
    state = version_state(version)
    print(f'version {version["attributes"].get("versionString")}  state {state}  id {version["id"]}')
    if state != 'PREPARE_FOR_SUBMISSION' and args.apply:
        print('that version is not editable; screenshots can only be added to PREPARE_FOR_SUBMISSION')
        return 1
    live = version_locales(api, version['id'])
    print(f'{len(live)} localizations on the version')

    only = {store_code(x) for x in args.locales.split(',')} if args.locales else None
    never = {store_code(x) for x in args.exclude.split(',')} if args.exclude else set()
    targets = []
    for apple_loc in sorted(live):
        code = store_code(apple_loc)
        if only is not None and code not in only:
            continue
        if code in never:
            continue
        targets.append((apple_loc, code, live[apple_loc]['id']))

    print(f'{"locale":10} {"dir":12} {"iphone-6.5":22} {"iphone-6.9":22} {"ipad-13":22} result')
    columns = (('iphone-6.5', IPHONE_65), ('iphone-6.9', IPHONE_69), ('ipad-13', IPAD_13))
    results: list[tuple[str, str, dict]] = []
    aborts: list[str] = []
    import threading
    lock = threading.Lock()

    def work(item):
        apple_loc, code, loc_id = item
        worker = api if args.jobs <= 1 else ASC()
        try:
            if args.repair_stuck and args.apply:
                gone = repair_stuck(worker, loc_id, code)
                for g in gone:
                    print(f'    removed stuck record {code} {g}')
            if args.reset_display and args.apply:
                gone = reset_display(worker, loc_id, code, args.reset_display)
                print(f'    reset {code} {args.reset_display}: removed {len(gone)}')
            res = sync_locale(worker, loc_id, code, apply=args.apply, replace=args.replace_changed)
        except RebuildIncomplete as exc:
            # A deck is short. Stop here rather than shorting more of them.
            aborts.append(str(exc))
            res = {'code': code, 'rows': {}, 'uploaded': 0, 'skipped': 0,
                   'fail': [f'deck left incomplete: {exc}'], 'notes': []}
        except BaseException as exc:
            res = {'code': code, 'rows': {}, 'uploaded': 0, 'skipped': 0,
                   'fail': [f'locale failed: {exc}'], 'notes': []}
        with lock:
            results.append((apple_loc, code, res))
            rows = res['rows']
            cells = []
            # Every locale prints the same three columns, `-` where it has no
            # such set. Printing only the sets a locale has put each locale's
            # numbers under another locale's headings.
            for _label, display in columns:
                r = rows.get(display)
                if r is None:
                    cells.append(f'{"-":22}')
                else:
                    cell = ('+' + str(r['upload']) + ' =' + str(r['skip'])
                            + (' c' + str(r.get('changed', 0)) if r.get('changed') else '')
                            + ' x' + str(r['fail']))
                    cells.append(f'{cell:22}')
            status = 'failed' if res['fail'] else ('upload' if res['uploaded'] else 'skip')
            if res['notes'] and not rows:
                status += ' (' + res['notes'][0] + ')'
            print(f'{apple_loc:10} {code:12} {" ".join(cells)} {status}')
            for m in res['fail']:
                print(f'    FAIL {m}')
            for m in res['notes']:
                print(f'    note {m}')

    if args.jobs > 1:
        from concurrent.futures import ThreadPoolExecutor
        with ThreadPoolExecutor(max_workers=args.jobs) as pool:
            list(pool.map(work, targets))
    else:
        for item in targets:
            # One deck is already short. Uploading the rest cannot repair it, and
            # every extra set touched is another chance to leave a second one short.
            if aborts:
                print(f'    stopping: {len(targets) - len(results)} locale(s) not touched')
                break
            work(item)

    if aborts:
        print('\nA deck was left incomplete, so the run stopped. Nothing was submitted.')
        for a in aborts:
            print(f'  {a}')
        return 1

    up = sum(r['uploaded'] for _, _, r in results)
    sk = sum(r['skipped'] for _, _, r in results)
    changed = sum(rw.get('changed', 0) for _, _, r in results for rw in r['rows'].values())
    bad = [r for _, _, r in results if r['fail']]
    print(f'\n{len(results)} locales: {up} {"uploaded" if args.apply else "to upload"}, '
          f'{sk} already present, {changed} changed on disk, {len(bad)} with failures')
    if not args.apply:
        if changed and not args.replace_changed:
            print(f'{changed} card(s) differ from what Apple holds; '
                  'pass --replace-changed to swap them (rebuilds that deck\'s tail)')
        print('dry run: pass --apply to upload')
    elif bad:
        print('re-run to resume; completed locales are skipped by checksum')
    return 1 if bad else 0


# ---------------------------------------------------------------------------
# Custom product pages


def cpp_plan() -> list[dict]:
    base = listing_data.load('en-US')
    return [
        {'name': 'Bollywood', 'locale': 'en-US', 'promo': 'Every Bollywood release, from FDFS to the third watch. One ticket for every viewing.'},
        {'name': 'Tamil cinema', 'locale': 'ta', 'promo': 'தமிழ் சினிமாவின் ஒவ்வொரு பார்வையும் ஒரு டிக்கெட்.',
         'promo_en': 'Tamil cinema, stamped. Every viewing becomes a ticket.'},
        {'name': 'Telugu cinema', 'locale': 'te', 'promo': 'తెలుగు సినిమా ప్రతి వీక్షణం ఒక టికెట్.',
         'promo_en': 'Telugu cinema, stamped. Every viewing becomes a ticket.'},
        {'name': 'FDFS', 'locale': 'en-US', 'promo': 'First day, first show. Stamp every FDFS you have ever queued for.'},
        {'name': 'Year in films', 'locale': 'en-US', 'promo': 'Your year in films: watch time, money spent, top directors, every FDFS.'},
        {'name': 'Letterboxd import', 'locale': 'en-US', 'promo': 'Bring your Letterboxd diary across in one CSV import. Nothing is lost.'},
        {'name': 'Movie night', 'locale': 'en-US', 'promo': 'Swipe on films with your crew, then vote on the time. Movie night, decided.'},
        {'name': 'Global', 'locale': 'en-US', 'promo': 'A film diary for every language you watch in. Free, offline, no account.'},
    ]


def cmd_cpp(api: ASC, args) -> int:
    app = api.app_id()
    existing = {x['attributes'].get('name'): x for x in api.all(f'/v1/apps/{app}/appCustomProductPages')}
    plan = cpp_plan()
    print(f'{len(plan)} custom product pages, {len(existing)} already on the app')
    for item in plan:
        print(f'  {item["name"]:16} {item["locale"]:6} {item["promo"][:60]}')
    if not args.apply:
        print('dry run: pass --apply to create')
        return 0
    for item in plan:
        page = existing.get(item['name'])
        if page is None:
            # Apple refuses a page without at least one version, so the first
            # version and its localization are created inline through
            # client-side placeholder ids. That inline localization must be the
            # app's primary language: a non-primary locale here 409s with
            # ENTITY_ERROR.RELATIONSHIP.REQUIRED, because Apple drops the
            # localization and then the version has none. Any other locale goes
            # on afterwards as its own POST.
            page = api.post('/v1/appCustomProductPages', {
                'data': {
                    'type': 'appCustomProductPages',
                    'attributes': {'name': item['name']},
                    'relationships': {
                        'app': {'data': {'type': 'apps', 'id': app}},
                        'appCustomProductPageVersions': {'data': [
                            {'type': 'appCustomProductPageVersions', 'id': '${version-1}'}
                        ]},
                    },
                },
                'included': [
                    {
                        'type': 'appCustomProductPageVersions',
                        'id': '${version-1}',
                        'relationships': {'appCustomProductPageLocalizations': {'data': [
                            {'type': 'appCustomProductPageLocalizations', 'id': '${loc-1}'}
                        ]}},
                    },
                    {
                        'type': 'appCustomProductPageLocalizations',
                        'id': '${loc-1}',
                        'attributes': {'locale': 'en-US',
                                       'promotionalText': item.get('promo_en', item['promo'])},
                    },
                ],
            })['data']
        versions = api.all(f'/v1/appCustomProductPages/{page["id"]}/appCustomProductPageVersions')
        if versions:
            version = versions[0]
        else:
            version = api.post('/v1/appCustomProductPageVersions', {
                'data': {
                    'type': 'appCustomProductPageVersions',
                    'relationships': {'appCustomProductPage': {
                        'data': {'type': 'appCustomProductPages', 'id': page['id']}}},
                }
            })['data']
        locs = api.all(f'/v1/appCustomProductPageVersions/{version["id"]}/appCustomProductPageLocalizations')
        want = apple_locale(item['locale'])
        if not any(x['attributes'].get('locale') == want for x in locs):
            api.post('/v1/appCustomProductPageLocalizations', {
                'data': {
                    'type': 'appCustomProductPageLocalizations',
                    'attributes': {'locale': want, 'promotionalText': item['promo']},
                    'relationships': {'appCustomProductPageVersion': {
                        'data': {'type': 'appCustomProductPageVersions', 'id': version['id']}}},
                }
            })
        print(f'  {item["name"]}: ready, add screenshots and submit in App Store Connect')
    return 0


# ---------------------------------------------------------------------------
# Product page optimization


def cmd_ppo(api: ASC, args) -> int:
    app = api.app_id()
    # Read the version, never create one: this command only reports, and a
    # version record cannot be deleted through the API, so a stray create is
    # permanent clutter on the app.
    version = current_version(api, app)
    existing = api.all(f'/v1/apps/{app}/appStoreVersionExperimentsV2')
    name = 'Screenshots and preview'
    print(f'experiment "{name}" with 3 treatments, {len(existing)} already on the app')
    treatments = [
        ('Control', 'The current screenshots'),
        ('Preview video', 'A 30 second portrait preview on the first screenshot'),
        ('Alternate icon', 'Another app icon with six screenshots'),
    ]
    for t, why in treatments:
        print(f'  {t:16} {why}')
    if not args.apply:
        print('dry run: pass --apply to create')
        return 0
    exp = next((x for x in existing if x['attributes'].get('name') == name), None)
    if exp is None:
        # Product page optimization can only be created against a version that
        # is READY_FOR_DISTRIBUTION. There is no V2 create endpoint: both
        # /v2/appStoreVersionExperimentsV2 and /v1/appStoreVersionExperimentsV2
        # answer 404, and the V2 resource only lists. So the state gate below
        # cannot be worked around from the API.
        if version is None or version_state(version) != 'READY_FOR_DISTRIBUTION':
            print(f'blocked: App Store version is {version_state(version) if version else "missing"}, '
                  'product page optimization needs READY_FOR_DISTRIBUTION.')
            print('Nothing was written. Re-run this after the version ships, or create it in '
                  'App Store Connect > Product Page Optimization.')
            return 0
        exp = api.post('/v1/appStoreVersionExperiments', {
            'data': {
                'type': 'appStoreVersionExperiments',
                'attributes': {'name': name, 'trafficProportion': 100},
                'relationships': {
                    'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}},
                },
            }
        })['data']
    made = api.all(f'/v1/appStoreVersionExperimentsV2/{exp["id"]}/appStoreVersionExperimentTreatmentsV2')
    for t, _why in treatments:
        if not any(x['attributes'].get('name') == t for x in made):
            api.post('/v1/appStoreVersionExperimentTreatments', {
                'data': {
                    'type': 'appStoreVersionExperimentTreatments',
                    'attributes': {'name': t},
                    'relationships': {'appStoreVersionExperiment': {
                        'data': {'type': 'appStoreVersionExperiments', 'id': exp['id']}}},
                }
            })
    print('experiment ready. Add the treatment screenshots and start it in App Store Connect.')
    return 0


# ---------------------------------------------------------------------------
# In-app events


def event_plan() -> list[dict]:
    """AppEvent `badge` and `purpose` take fixed enums; both are set here.

    badge:  LIVE_EVENT, PREMIERE, CHALLENGE, COMPETITION, NEW_SEASON,
            MAJOR_UPDATE, SPECIAL_EVENT
    purpose: APPROPRIATE_FOR_ALL_USERS, ATTRACT_NEW_USERS,
             KEEP_ACTIVE_USERS_INFORMED, BRING_BACK_LAPSED_USERS
    Dates live in territorySchedules and stay a human edit.
    """
    return [
        {'name': 'Your year in films', 'badge': 'SPECIAL_EVENT', 'purpose': 'KEEP_ACTIVE_USERS_INFORMED',
         'title': 'Your 2026 in films', 'text': 'Your year, counted in stubs.',
         'long': 'How many films, how many hours, how much on tickets. See your whole year as one ticket stub.'},
        {'name': 'FDFS Friday', 'badge': 'CHALLENGE', 'purpose': 'KEEP_ACTIVE_USERS_INFORMED',
         'title': 'FDFS Friday', 'text': 'First day, first show. Stamp it.',
         'long': 'Queue for the first day, first show, then stamp the ticket in Talkies.'},
        {'name': '100 films', 'badge': 'CHALLENGE', 'purpose': 'BRING_BACK_LAPSED_USERS',
         'title': '100 films this year', 'text': 'A hundred stubs. Keep going.',
         'long': 'Count every film you watch this year. A hundred stubs and counting.'},
        {'name': 'Movie night', 'badge': 'LIVE_EVENT', 'purpose': 'ATTRACT_NEW_USERS',
         'title': 'Movie night planner', 'text': 'Swipe, vote, settle it tonight.',
         'long': 'Swipe on films with your crew, vote on a time, and settle movie night tonight.'},
    ]


def cmd_events(api: ASC, args) -> int:
    app = api.app_id()
    existing = {x['attributes'].get('referenceName'): x for x in api.all(f'/v1/apps/{app}/appEvents')}
    plan = event_plan()
    print(f'{len(plan)} in-app events, {len(existing)} already on the app')
    for e in plan:
        print(f'  {e["title"]:28} {e["badge"]}')
    if not args.apply:
        print('dry run: pass --apply to create the event shell; add dates and art in App Store Connect')
        return 0
    for e in plan:
        event = existing.get(e['name'])
        attrs = {'primaryLocale': 'en-US', 'badge': e['badge'], 'purpose': e['purpose'], 'priority': 'NORMAL'}
        if event is None:
            event = api.post('/v1/appEvents', {
                'data': {
                    'type': 'appEvents',
                    'attributes': {'referenceName': e['name'], **attrs},
                    'relationships': {'app': {'data': {'type': 'apps', 'id': app}}},
                }
            })['data']
            print(f'  {e["name"]}: created')
        else:
            event = api.patch(f'/v1/appEvents/{event["id"]}', {
                'data': {'type': 'appEvents', 'id': event['id'], 'attributes': attrs}
            })['data']
            print(f'  {e["name"]}: attributes set')
        locs = api.all(f'/v1/appEvents/{event["id"]}/localizations')
        if not any(x['attributes'].get('locale') == 'en-US' for x in locs):
            api.post('/v1/appEventLocalizations', {
                'data': {
                    'type': 'appEventLocalizations',
                    'attributes': {
                        'locale': 'en-US',
                        'name': e['title'],
                        'shortDescription': e['text'],
                        'longDescription': e['long'],
                    },
                    'relationships': {'appEvent': {'data': {'type': 'appEvents', 'id': event['id']}}},
                }
            })
            print(f'  {e["name"]}: en-US text')
    print('add the event dates, the artwork and the review submission in App Store Connect.')
    return 0


def cmd_submit(api: ASC, args) -> int:
    """Attach the newest processed build and send the version to App Review.

    Two steps, in order, because Apple rejects them out of order: the version
    must point at a build, and every locale, screenshot set and age rating must
    already be filled. The build is chosen by newest upload, not by what the
    version points at, so a fresh upload is picked up without being named.
    """
    app = api.app_id()
    version = current_version(api, app)
    if version is None:
        print('no editable version')
        return 1
    state = version_state(version)
    name = version['attributes'].get('versionString')
    print(f'version {name}  state {state}  id {version["id"]}')
    # DEVELOPER_REJECTED is what `cancel --apply` leaves behind: the version is
    # ours again, its build can be swapped, and it can be submitted afresh. That
    # is the documented way to replace a build, so it has to be allowed here.
    if state not in ('PREPARE_FOR_SUBMISSION', 'DEVELOPER_REJECTED'):
        print('that version is not editable, nothing to submit')
        return 1

    # Already submitted or in review: say so instead of opening a second submission.
    subs = api.all(f'/v1/apps/{app}/reviewSubmissions', **{'filter[platform]': 'IOS'})
    for s in subs:
        st = s['attributes'].get('state')
        if st in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES'):
            print(f'a review submission already exists in state {st}: {s["id"]}')
            return 1

    builds = [b for b in api.all('/v1/builds', **{'filter[app]': app})
              if b['attributes'].get('processingState') == 'VALID' and not b['attributes'].get('expired')]
    if not builds:
        print('no processed build is available; upload an IPA and wait for it to finish processing')
        return 1
    build = max(builds, key=lambda b: b['attributes'].get('uploadedDate') or '')
    print(f'build {build["attributes"].get("version")} uploaded {build["attributes"].get("uploadedDate")}')

    if not args.apply:
        print('dry run: would attach that build and submit for review with '
              f'releaseType {version["attributes"].get("releaseType")}')
        return 0

    api.patch(f'/v1/appStoreVersions/{version["id"]}', {
        'data': {'type': 'appStoreVersions', 'id': version['id'], 'attributes': {'releaseType': 'AFTER_APPROVAL'}},
    })
    print('releaseType AFTER_APPROVAL (releases on its own once approved)')
    api.patch(f'/v1/appStoreVersions/{version["id"]}/relationships/build', {
        'data': {'type': 'builds', 'id': build['id']},
    })
    print('build attached')

    sub = api.post('/v1/reviewSubmissions', {
        'data': {'type': 'reviewSubmissions', 'attributes': {'platform': 'IOS'},
                 'relationships': {'app': {'data': {'type': 'apps', 'id': app}}}}
    })['data']
    api.post('/v1/reviewSubmissionItems', {
        'data': {'type': 'reviewSubmissionItems',
                 'relationships': {
                     'reviewSubmission': {'data': {'type': 'reviewSubmissions', 'id': sub['id']}},
                     'appStoreVersion': {'data': {'type': 'appStoreVersions', 'id': version['id']}},
                 }}
    })
    done = api.patch(f'/v1/reviewSubmissions/{sub["id"]}', {
        'data': {'type': 'reviewSubmissions', 'id': sub['id'], 'attributes': {'submitted': True}},
    })['data']
    print(f'submitted for review: {done["attributes"].get("state")}  id {sub["id"]}')
    return 0


def cmd_cancel(api: ASC, args) -> int:
    """Pull a submission back so the version is editable again.

    Needed to replace a build after submitting. A version's build relationship
    cannot be changed while the version is WAITING_FOR_REVIEW, and the API
    refuses DELETE on reviewSubmissions ("Allowed operations are: CREATE,
    GET_COLLECTION, GET_INSTANCE, UPDATE"). Cancelling is therefore an update.
    It moves the version to DEVELOPER_REJECTED, from which the build can be
    swapped and the version submitted again.
    """
    app = api.app_id()
    live = [s for s in api.all(f'/v1/apps/{app}/reviewSubmissions', **{'filter[platform]': 'IOS'})
            if s['attributes'].get('state') in ('WAITING_FOR_REVIEW', 'IN_REVIEW', 'UNRESOLVED_ISSUES')]
    if not live:
        print('no submission is waiting for review')
        return 0
    for s in live:
        print(f'cancelling {s["id"]} ({s["attributes"].get("state")})')
        if not args.apply:
            continue
        r = api.patch(f'/v1/reviewSubmissions/{s["id"]}', {'data': {
            'type': 'reviewSubmissions', 'id': s['id'], 'attributes': {'canceled': True}}})
        print('  ->', r['data']['attributes'].get('state'))
    if not args.apply:
        print('dry run: pass --apply to cancel')
    return 0


def main() -> int:
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument('command', choices=['audit', 'push', 'screenshots', 'cpp', 'ppo', 'events', 'submit', 'cancel'])
    p.add_argument('--apply', action='store_true', help='write to App Store Connect')
    p.add_argument('--screenshots', action='store_true', help='upload localized screenshots during push')
    p.add_argument('--locales', help='screenshots: comma-separated subset (Apple or folder codes)')
    p.add_argument('--exclude', help='screenshots: comma-separated locales to leave alone')
    p.add_argument('--jobs', type=int, default=1, help='screenshots: locales to work on at once')
    p.add_argument('--repair-stuck', action='store_true',
                   help='screenshots: delete AWAITING_UPLOAD records with no bytes, then upload them again')
    p.add_argument('--reset-display', metavar='DISPLAY_TYPE',
                   help='screenshots: delete one display set and rebuild it in order (APP_IPAD_PRO_3GEN_129)')
    p.add_argument('--replace-changed', action='store_true',
                   help='screenshots: replace cards whose bytes changed since upload, '
                        'rebuilding the tail of that deck so the order holds')
    args = p.parse_args()
    api = ASC()
    return {'audit': cmd_audit, 'push': cmd_push, 'screenshots': cmd_screenshots,
            'cpp': cmd_cpp, 'ppo': cmd_ppo, 'events': cmd_events, 'submit': cmd_submit,
            'cancel': cmd_cancel}[args.command](api, args)


if __name__ == '__main__':
    sys.exit(main())
