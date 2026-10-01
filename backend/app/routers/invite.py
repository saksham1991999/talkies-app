"""GET /j/{code}: the page an invite link opens.

It names no group and makes no database call. It shows the code, a link that
opens the app, and the store links. Chat apps do not turn `talkies://` into a
link, so this https page is the thing people tap.
"""

from html import escape

from fastapi import APIRouter, Request
from fastapi.responses import HTMLResponse

from app.errors import NotFound
from app.logic.validate import INVITE_RE

router = APIRouter(tags=["invite"])

APP_STORE = "https://apps.apple.com/app/id6817738462"
PLAY_STORE = "https://play.google.com/store/apps/details?id=in.talkies.talkies"
OG_IMAGE = "https://saksham1991999.github.io/talkies-app/img/og.png"

_HEADERS = {
    "X-Robots-Tag": "noindex",
    "Referrer-Policy": "no-referrer",
    "X-Content-Type-Options": "nosniff",
    "Cache-Control": "public, max-age=3600",
    "Content-Security-Policy": (
        "default-src 'none'; style-src 'unsafe-inline' https://api.fontshare.com; "
        "font-src https:; img-src data:; base-uri 'none'; form-action 'none'; "
        "frame-ancestors 'none'"
    ),
}

_CSS = """
:root{--wall:#e3e6d8;--paper:#f2cbc1;--ink:#2a1316;--soft:#5f4a46;--sindoor:#b0342b}
@media (prefers-color-scheme:dark){
:root{--wall:#170d0e;--paper:#2e1316;--ink:#f1e5dd;--soft:#b9a49b;--sindoor:#e26e60}}
*{box-sizing:border-box}
html{background:var(--wall)}
body{margin:0;min-height:100vh;min-height:100svh;display:flex;flex-direction:column;
padding:24px;background:var(--wall);color:var(--ink);
font:17px/1.55 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
.page{flex:1;width:100%;max-width:560px;margin:0 auto;display:flex;flex-direction:column}
.display{font-family:"Tanker","Arial Narrow",system-ui,sans-serif;font-weight:400}
.brand{margin:0;font-size:30px;line-height:1;letter-spacing:.06em;color:var(--sindoor)}
main{flex:1;display:flex;flex-direction:column;justify-content:center;padding:32px 0}
.ticket{background:var(--paper);border-radius:6px}
.head{padding:28px 28px 26px}
h1{margin:0 0 10px;font-size:clamp(40px,11vw,60px);line-height:1;letter-spacing:.03em}
.lead{margin:0;font-size:18px}
.perf{position:relative;height:0;margin:0 22px;border-top:4px dotted var(--sindoor)}
.perf::before,.perf::after{content:"";position:absolute;top:-16px;width:28px;height:28px;
border-radius:50%;background:var(--wall)}
.perf::before{left:-36px}
.perf::after{right:-36px}
.foot{padding:22px 28px 28px}
.code{margin:0;display:flex;flex-wrap:wrap;gap:0 .32em;font-size:clamp(48px,15vw,104px);
line-height:1.05;letter-spacing:.05em;color:var(--sindoor);user-select:all}
.code span{white-space:nowrap}
.open{display:block;margin-top:22px;padding:16px 24px;border-radius:4px;background:var(--ink);
color:var(--wall);font-size:18px;font-weight:700;line-height:1.2;text-align:center;text-decoration:none}
.open:hover{background:var(--sindoor)}
a:focus-visible{outline:3px solid var(--sindoor);outline-offset:3px}
.note{margin:22px 0 0;color:var(--soft);font-size:15px}
.note a{color:var(--ink);text-underline-offset:3px}
.note a:hover{color:var(--sindoor)}
""".strip()


def render(code: str, base_url: str = "") -> str:
    """The page for a valid code. `code` must match INVITE_RE: it is not escaped as markup."""
    link = f"talkies://join?code={code}"
    url = f"{base_url.rstrip('/')}/j/{code}" if base_url else ""
    og_url = f'<meta property="og:url" content="{escape(url)}">' if url else ""
    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="color-scheme" content="light dark">
<meta name="theme-color" content="#e3e6d8" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="#170d0e" media="(prefers-color-scheme: dark)">
<meta name="robots" content="noindex">
<meta name="referrer" content="no-referrer">
<meta name="apple-itunes-app" content="app-id=6817738462, app-argument={link}">
<title>Join a group on Talkies</title>
<meta property="og:title" content="Join a group on Talkies">
<meta property="og:description" content="Open Talkies and enter the code {code}.">
<meta property="og:image" content="{OG_IMAGE}">
{og_url}
<link rel="icon" href="data:,">
<link rel="stylesheet" href="https://api.fontshare.com/v2/css?f[]=tanker@400&amp;display=swap">
<style>{_CSS}</style>
</head>
<body>
<div class="page">
<p class="brand display">TALKIES</p>
<main>
<article class="ticket">
<div class="head">
<h1 class="display">ADMIT ONE</h1>
<p class="lead">A friend invited you to a group on Talkies.</p>
</div>
<div class="perf" aria-hidden="true"></div>
<div class="foot" role="group" aria-label="Group code">
<p class="code display" translate="no"><span>{code[:4]}</span> <span>{code[4:]}</span></p>
<a class="open" href="{link}">Open in Talkies</a>
</div>
</article>
<p class="note">If the button does nothing, open Talkies, go to Together, tap Join with code,
and enter the code.</p>
<p class="note">No app yet? <a href="{APP_STORE}">App Store</a> or
<a href="{PLAY_STORE}">Google Play</a>.</p>
</main>
</div>
</body>
</html>
"""


@router.get("/j/{code}", response_class=HTMLResponse, include_in_schema=False)
async def invite_page(code: str, request: Request):
    if not INVITE_RE.fullmatch(code):
        raise NotFound()
    base = request.app.state.settings.public_base_url
    return HTMLResponse(render(code, base), headers=_HEADERS)
