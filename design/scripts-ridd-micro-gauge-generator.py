#!/usr/bin/env python3
"""Generate design/ridd-micro-gauge-explorations.html from the round-2 doc's tokens."""
import re

SRC = 'design/ridd-feedback-explorations.html'
OUT = 'design/ridd-micro-gauge-explorations.html'
raw = open(SRC).read()

# --- pull the real logo SVGs out of the previous doc ---
m = re.search(r'<svg[^>]*>(?:(?!</svg>).)*?<title>Claude</title>.*?</svg>', raw, re.S)
CLAUDE_SVG = m.group(0)
i = raw.find('prov-name codex')
seg = raw[max(0, i - 4000):i]
CODEX_SVG = seg[seg.rfind('<svg'):].rsplit('</span>', 1)[0]

def prov_head(name='Claude'):
    if name == 'Claude':
        return ('<div class="prov-head"><span class="logo-box">' + CLAUDE_SVG +
                '</span><span class="prov-name claude">Claude</span></div>')
    return ('<div class="prov-head"><span class="logo-box">' + CODEX_SVG +
            '</span><span class="prov-name codex">Codex</span></div>')

WINDOWS = [('5-hour', 'Resets in 3h 11m', 72, 'h', ''),
           ('Weekly', 'Resets in 3d 23h', 38, 'l', ''),
           ('Weekly (Fable)', 'Resets in 3d 23h', 12, 'c', ' crit')]

def gauge(kind, pct, sev):
    """One micro-gauge element in a given form/recipe."""
    if kind == 'chip':
        return f'<span class="micro"><span class="mfill sev-{sev}" style="width:{pct}%"></span></span>'
    if kind == 'well':
        return f'<span class="micro well"><span class="mfill glass sev-{sev}" style="width:{pct}%"></span></span>'
    if kind == 'arc':
        # semicircle r=8 from (2,10) to (18,10); length = pi*8 = 25.13
        dash = round(25.13 * pct / 100, 2)
        return (f'<svg class="g-arc" width="20" height="12" viewBox="0 0 20 12">'
                f'<path d="M2 10 A8 8 0 0 1 18 10" fill="none" stroke="rgba(255,255,255,0.14)" stroke-width="3" stroke-linecap="round"/>'
                f'<path d="M2 10 A8 8 0 0 1 18 10" fill="none" class="arcfill sev-{sev}" stroke-width="3" stroke-linecap="round" stroke-dasharray="{dash} 25.13"/></svg>')
    if kind == 'ring':
        dash = round(37.7 * pct / 100, 2)
        return (f'<svg class="g-ring" width="15" height="15" viewBox="0 0 16 16">'
                f'<circle cx="8" cy="8" r="6" fill="none" stroke="rgba(255,255,255,0.13)" stroke-width="2.5"/>'
                f'<circle cx="8" cy="8" r="6" fill="none" class="arcfill sev-{sev}" stroke-width="2.5" stroke-linecap="round" '
                f'stroke-dasharray="{dash} 37.7" transform="rotate(-90 8 8)"/></svg>')
    if kind == 'ticks':
        n_on = round(pct / 20)  # 5 ticks
        segs = ''.join(
            f'<span class="gt {"tick-on sev-" + sev if j < n_on else ""}{" tickcap" if j == n_on - 1 else ""}"></span>'
            for j in range(5))
        return f'<span class="g-ticks">{segs}</span>'
    if kind == 'vert':
        return (f'<span class="g-vert"><span class="gv-fill sev-{sev}" style="height:{pct}%"></span></span>')
    # ---- recipe variants on the chip form ----
    if kind == 'glasscap':
        return (f'<span class="micro glasschip"><span class="mfill glass" style="width:{pct}%">'
                f'<span class="mcap sev-{sev}"></span></span></span>')
    if kind == 'event':
        cls = 'glass' if sev == 'h' else f'sev-{sev}'
        return f'<span class="micro"><span class="mfill {cls}" style="width:{pct}%"></span></span>'
    if kind == 'inkonly':
        return f'<span class="micro"><span class="mfill glass" style="width:{pct}%"></span></span>'
    if kind == 'ramp':
        return f'<span class="micro"><span class="mfill ramp-{sev}" style="width:{pct}%"></span></span>'
    if kind == 'proud':
        return (f'<span class="micro proudtrack"><span class="mfill glass" style="width:{pct}%">'
                f'<span class="proudcap sev-{sev}"></span></span></span>')
    if kind == 'lit':
        return (f'<span class="micro glasschip"><span class="mfill glass" style="width:{pct}%">'
                f'<span class="mcap lit sev-{sev}"></span></span></span>')
    if kind == 'dome':
        return (f'<span class="micro dome"><span class="mfill {"glass" if sev == "h" else "sev-" + sev}" style="width:{pct}%"></span></span>')
    raise ValueError(kind)

def meter_row(kind, label, reset, pct, sev, crit, pos='p1', term='left'):
    g = gauge(kind, pct, sev)
    if kind == 'inkonly' and sev == 'l':
        crit = ' inkonly-l'  # the recipe's whole point: severity ink on the numeral
    num = f'<span class="m-pct{crit}">{pct}%</span><span class="m-term">{term}</span>'
    if term == 'used':
        num = f'<span class="m-pct{crit}">{100 - pct}%</span><span class="m-term">used</span>'
    lab = f'<span class="m-label">{label}</span><span class="m-reset">· {reset}</span>'
    if pos == 'p1':   # gauge docked left of numeral (baseline)
        inner = f'{lab}<span class="m-spacer"></span>{g}{num}'
    elif pos == 'p2':  # numeral first, gauge trails at the far edge
        inner = f'{lab}<span class="m-spacer"></span>{num}{g}'
    elif pos == 'p3':  # gauge leads the row
        inner = f'{g}{lab}<span class="m-spacer"></span>{num}'
    elif pos == 'p4':  # gauge under the numeral cluster
        inner = (f'{lab}<span class="m-spacer"></span>'
                 f'<span class="numstack">{num}<span class="micro under"><span class="mfill sev-{sev}" style="width:{pct}%"></span></span></span>')
    return f'<div class="meter"><div class="meter-top">{inner}</div></div>'

def card(kind, pos='p1', term='left', extra_cls=''):
    rows = '\n            '.join(
        meter_row(kind, *w, pos=pos, term=term) for w in WINDOWS)
    return (f'<div class="stage"><div class="card v-micro {extra_cls}">\n          '
            f'{prov_head()}\n          <div class="meters">\n            {rows}\n          </div>\n        </div></div>')

def option(letter, title, sub, body, note, tag=None, ref=False):
    tag_html = f'<span class="ridd-tag{" mine" if tag == "mine" else ""}">{tag if tag != "mine" else "My read"}</span>' if tag else ''
    if tag and tag.startswith('!'):
        tag_html = f'<span class="ridd-tag">{tag[1:]}</span>'
    return f'''      <div class="option{' reference' if ref else ''}">
        <div class="option-head">
          <span class="option-letter">{letter}</span>
          <div><div class="option-title">{title}</div><div class="option-sub">{sub}</div></div>
          {tag_html}
        </div>
        {body}
        <p class="option-note">{note}</p>
      </div>'''

# ---------- full-scale popover ----------
def acct_block(name, plan, email, meters, kind):
    rows = '\n        '.join(meter_row(kind, *m) for m in meters)
    return f'''<div class="acct-block">
        <div class="idline"><span class="id-name">{name}</span><span class="plan-pill">{plan}</span><span class="acct-email">{email}</span></div>
        {rows}
      </div>'''

def popover(healthy=False):
    if not healthy:
        cl_personal = [('Weekly', 'Resets in 3d 23h', 38, 'l', ''), ('5-hour', 'Resets in 3h 11m', 72, 'h', '')]
        cl_work = [('Weekly', 'Resets in 3d 23h', 12, 'c', ' crit'), ('5-hour', 'Resets in 4h 02m', 29, 'l', '')]
        cx = [('Weekly', 'Resets in 5d 4h', 64, 'h', ''), ('5-hour', 'Resets in 1h 40m', 91, 'h', '')]
    else:
        cl_personal = [('Weekly', 'Resets in 3d 23h', 81, 'h', ''), ('5-hour', 'Resets in 3h 11m', 72, 'h', '')]
        cl_work = [('Weekly', 'Resets in 3d 23h', 66, 'h', ''), ('5-hour', 'Resets in 4h 02m', 88, 'h', '')]
        cx = [('Weekly', 'Resets in 5d 4h', 64, 'h', ''), ('5-hour', 'Resets in 1h 40m', 91, 'h', '')]
    kind = 'event'
    return f'''<div class="popover-full">
      <div class="pop-head"><span class="pop-title">Usage</span><span class="pop-updated">Updated 2 min ago</span><span class="pop-gear">⚙︎</span></div>
      <div class="card v-micro pop-card">
        {prov_head('Claude')}
        {acct_block('Personal', 'Max', 'personal@example.com', cl_personal, kind)}
        <div class="chunk-gap"></div>
        {acct_block('Work', 'Pro', 'work@example.com', cl_work, kind)}
      </div>
      <div class="card v-micro pop-card">
        {prov_head('Codex')}
        {acct_block('Personal', 'Plus', 'personal@example.com', cx, kind)}
      </div>
      <div class="pop-foot"><span>Check now</span><span>Settings</span></div>
    </div>'''

# ---------- squint-question hover mock ----------
hover_mock = f'''<div class="stage"><div class="card v-micro">
          {prov_head()}
          <div class="meters">
            {meter_row('event', '5-hour', 'Resets in 3h 11m', 72, 'h', '')}
            <div class="meter hovered">
              <div class="meter-top"><span class="m-label">Weekly</span><span class="m-reset">· Resets in 3d 23h</span><span class="m-spacer"></span><span class="m-pct">38%</span><span class="m-term">left</span></div>
              <div class="track hover-track"><div class="fill glassfill" style="width:38%"><span class="capline sev-l"></span></div></div>
            </div>
            {meter_row('event', 'Weekly (Fable)', 'Resets in 3d 23h', 12, 'c', ' crit')}
          </div>
        </div></div>'''

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Headroom · Micro-gauge explorations</title>
<style>
  :root {{
    /* Real tokens from BrandColorValues.swift (dark scheme) */
    --page-bg: #0a0b0e;
    --popover-bg: #1d1f23;
    --tile-top: #25272d;
    --tile-bottom: #191b21;
    --ring: rgba(255,255,255,0.065);
    --track: rgba(255,255,255,0.14);
    --hairline: rgba(255,255,255,0.10);
    --text-primary: #f2f2f7;
    --text-secondary: rgba(235,235,245,0.66);
    --text-tertiary: rgba(235,235,245,0.56);
    --healthy: #33c759;
    --low: #ff9e0a;
    --critical: #ff5749;
    --critical-text: #ff6659;
    --claude-accent: #e88f69;
    --codex-accent: #96a1ff;
    --pill-bg: rgba(255,255,255,0.09);
  }}
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    background: var(--page-bg); color: var(--text-primary);
    -webkit-font-smoothing: antialiased; line-height: 1.5;
  }}
  .page {{ max-width: 1120px; margin: 0 auto; padding: 64px 32px 120px; }}

  header.masthead {{ margin-bottom: 20px; }}
  .eyebrow {{ font-size: 12px; font-weight: 700; letter-spacing: 1.4px; text-transform: uppercase; color: var(--text-tertiary); margin-bottom: 10px; }}
  h1 {{ font-size: 32px; font-weight: 700; letter-spacing: -0.5px; margin-bottom: 8px; }}
  .lede {{ font-size: 15px; color: var(--text-secondary); max-width: 660px; }}

  .quotes {{ display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 36px 0 12px; }}
  .quote {{ background: linear-gradient(180deg, var(--tile-top), var(--tile-bottom)); box-shadow: inset 0 0 0 1px var(--ring), 0 8px 24px rgba(0,0,0,0.35); border-radius: 14px; padding: 22px 24px; }}
  .quote .who {{ font-size: 11px; font-weight: 700; letter-spacing: 0.8px; text-transform: uppercase; color: var(--text-tertiary); margin-bottom: 10px; }}
  .quote p {{ font-size: 14px; color: var(--text-secondary); }}
  .quote p em {{ color: var(--text-primary); font-style: normal; font-weight: 600; }}
  .transcript-note {{ font-size: 12px; color: var(--text-tertiary); margin-bottom: 56px; }}

  section {{ margin-bottom: 88px; }}
  .section-head {{ max-width: 720px; margin-bottom: 28px; }}
  .section-kicker {{ font-size: 12px; font-weight: 700; letter-spacing: 1.2px; text-transform: uppercase; margin-bottom: 8px; }}
  .k-form {{ color: var(--healthy); }}
  .k-fill {{ color: var(--claude-accent); }}
  .k-pos {{ color: var(--codex-accent); }}
  .k-tact {{ color: var(--low); }}
  h2 {{ font-size: 24px; font-weight: 700; letter-spacing: -0.3px; margin-bottom: 8px; }}
  .section-head p {{ font-size: 14px; color: var(--text-secondary); }}

  .grid {{ display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }}
  .grid > * {{ min-width: 0; }}
  @media (max-width: 900px) {{ .grid, .quotes, .decisions, .shots2 {{ grid-template-columns: 1fr; }} }}

  .option {{ background: rgba(255,255,255,0.025); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.05); border-radius: 18px; padding: 24px; display: flex; flex-direction: column; gap: 16px; }}
  .option.reference {{ background: rgba(255,255,255,0.012); }}
  .option-head {{ display: flex; align-items: baseline; gap: 10px; }}
  .option-letter {{ font-size: 12px; font-weight: 700; min-width: 22px; height: 22px; border-radius: 7px; display: inline-flex; align-items: center; justify-content: center; background: rgba(255,255,255,0.10); color: var(--text-primary); flex-shrink: 0; transform: translateY(4px); }}
  .option-title {{ font-size: 16px; font-weight: 650; }}
  .option-sub {{ font-size: 13px; color: var(--text-secondary); }}
  .option-note {{ font-size: 12.5px; color: var(--text-tertiary); }}
  .option-note strong {{ color: var(--text-secondary); font-weight: 600; }}
  .ridd-tag {{ display: inline-block; font-size: 10.5px; font-weight: 600; letter-spacing: 0.3px; padding: 2px 8px; border-radius: 99px; background: rgba(232,143,105,0.14); color: var(--claude-accent); margin-left: auto; flex-shrink: 0; transform: translateY(2px); white-space: nowrap; }}
  .ridd-tag.mine {{ background: rgba(150,161,255,0.13); color: var(--codex-accent); }}

  /* settled-frame decision list */
  .decisions {{ display: grid; grid-template-columns: 1fr 1fr; gap: 12px 24px; margin-top: 4px; }}
  .decision {{ display: flex; gap: 12px; align-items: baseline; background: rgba(255,255,255,0.02); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.045); border-radius: 12px; padding: 14px 18px; }}
  .decision .d-mark {{ font-size: 12px; font-weight: 700; flex-shrink: 0; width: 38px; }}
  .d-keep {{ color: var(--healthy); }}
  .d-kill {{ color: var(--critical-text); }}
  .decision p {{ font-size: 13px; color: var(--text-secondary); }}
  .decision p .ts {{ font-size: 11px; color: var(--text-tertiary); font-variant-numeric: tabular-nums; white-space: nowrap; }}
  .decision p strong {{ color: var(--text-primary); font-weight: 600; }}

  /* ---------- popover / card chassis ---------- */
  .stage {{ background: var(--popover-bg); border-radius: 16px; padding: 22px; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.04); display: flex; flex-direction: column; align-items: center; gap: 14px; }}
  .card {{ width: 344px; max-width: 100%; background: linear-gradient(180deg, var(--tile-top), var(--tile-bottom)); box-shadow: inset 0 0 0 1px var(--ring), 0 6px 18px rgba(0,0,0,0.38); border-radius: 10px; padding: 13px; }}

  .prov-head {{ display: flex; align-items: center; gap: 6px; margin-bottom: 10px; }}
  .logo-box {{ width: 21px; height: 21px; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; }}
  .logo-box svg {{ width: 17.6px; height: 17.6px; }}
  .prov-name {{ font-size: 16px; font-weight: 600; letter-spacing: -0.2px; }}
  .prov-name.claude {{ color: var(--claude-accent); }}
  .prov-name.codex {{ color: var(--codex-accent); }}

  /* identity row — the settled frame: sentence case 600, plan chip, bare email */
  .idline {{ display: flex; align-items: baseline; gap: 6px; margin-bottom: 7px; min-width: 0; }}
  .idline .id-name {{ font-size: 12.5px; font-weight: 600; color: var(--text-primary); }}
  .plan-pill {{ font-size: 9.5px; font-weight: 500; color: var(--text-tertiary); background: var(--pill-bg); border-radius: 99px; padding: 1px 6px; }}
  .acct-email {{ font-size: 10px; color: var(--text-tertiary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }}

  /* meter row */
  .meters {{ display: flex; flex-direction: column; gap: 9px; }}
  .v-micro .meters {{ gap: 12px; }}
  .meter-top {{ display: flex; align-items: center; gap: 6px; min-width: 0; }}
  .m-label {{ font-size: 13px; font-weight: 500; color: var(--text-secondary); white-space: nowrap; }}
  .m-reset {{ font-size: 11px; color: var(--text-tertiary); font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }}
  .m-spacer {{ flex: 1; }}
  .m-pct {{ font-size: 18px; font-weight: 600; font-variant-numeric: tabular-nums; }}
  .m-pct.crit {{ color: var(--critical-text); }}
  .m-term {{ font-size: 11px; color: var(--text-tertiary); }}
  .meter {{ display: flex; flex-direction: column; gap: 5px; }}

  /* ---------- the micro-gauge family ---------- */
  .micro {{ width: 32px; height: 5px; border-radius: 99px; background: var(--track); position: relative; overflow: hidden; flex-shrink: 0; align-self: center; }}
  .micro .mfill {{ position: absolute; top: 0; bottom: 0; left: 0; border-radius: 99px; min-width: 3px; }}
  .mfill.sev-h {{ background: rgba(51,199,89,0.85); }}
  .mfill.sev-l {{ background: rgba(255,158,10,0.85); }}
  .mfill.sev-c {{ background: rgba(255,87,73,0.95); }}

  /* M2: machined well at micro scale */
  .micro.well {{ height: 6px; border-radius: 3.5px; background: #0f1114; overflow: visible;
    box-shadow: inset 0 1px 2px rgba(0,0,0,0.65), inset 0 -0.5px 0 rgba(255,255,255,0.05), 0 0.5px 0 rgba(255,255,255,0.045); }}
  .micro.well .mfill {{ top: 1px; bottom: 1px; left: 1px; border-radius: 2.5px; box-shadow: inset 0 0.5px 0 rgba(255,255,255,0.28); }}
  .micro.well .mfill.sev-h {{ background: linear-gradient(180deg, rgba(51,199,89,0.80), rgba(51,199,89,0.48)); }}
  .micro.well .mfill.sev-l {{ background: linear-gradient(180deg, rgba(255,158,10,0.80), rgba(255,158,10,0.48)); }}
  .micro.well .mfill.sev-c {{ background: linear-gradient(180deg, rgba(255,87,73,0.88), rgba(255,87,73,0.55)); }}

  /* M3/M4: arc + ring strokes */
  .g-arc, .g-ring {{ flex-shrink: 0; align-self: center; }}
  .g-arc {{ margin-bottom: -2px; }}
  .arcfill.sev-h {{ stroke: rgba(51,199,89,0.9); }}
  .arcfill.sev-l {{ stroke: rgba(255,158,10,0.9); }}
  .arcfill.sev-c {{ stroke: rgba(255,87,73,0.95); }}

  /* M5: tick strip */
  .g-ticks {{ display: inline-flex; gap: 2px; align-self: center; flex-shrink: 0; }}
  .gt {{ width: 6px; height: 5px; border-radius: 1.5px; background: rgba(255,255,255,0.09); }}
  .gt.tick-on.sev-h {{ background: rgba(51,199,89,0.45); }}
  .gt.tick-on.sev-l {{ background: rgba(255,158,10,0.45); }}
  .gt.tick-on.sev-c {{ background: rgba(255,87,73,0.55); }}
  .gt.tick-on.tickcap.sev-h {{ background: var(--healthy); }}
  .gt.tick-on.tickcap.sev-l {{ background: var(--low); }}
  .gt.tick-on.tickcap.sev-c {{ background: var(--critical); }}

  /* M6: vertical tube */
  .g-vert {{ width: 5px; height: 16px; border-radius: 99px; background: var(--track); position: relative; overflow: hidden; flex-shrink: 0; align-self: center; }}
  .gv-fill {{ position: absolute; left: 0; right: 0; bottom: 0; border-radius: 99px; min-height: 3px; }}
  .gv-fill.sev-h {{ background: rgba(51,199,89,0.85); }}
  .gv-fill.sev-l {{ background: rgba(255,158,10,0.85); }}
  .gv-fill.sev-c {{ background: rgba(255,87,73,0.95); }}

  /* ---------- fill recipes on the chip ---------- */
  .mfill.glass {{ background: linear-gradient(180deg, rgba(255,255,255,0.22), rgba(255,255,255,0.11)); box-shadow: inset 0 0.5px 0 rgba(255,255,255,0.25); }}
  .micro.glasschip {{ overflow: visible; }}
  .micro.glasschip .mfill {{ overflow: visible; }}
  .mcap {{ position: absolute; right: -0.5px; top: -0.5px; bottom: -0.5px; width: 2.5px; border-radius: 2px; }}
  .mcap.sev-h {{ background: var(--healthy); }}
  .mcap.sev-l {{ background: var(--low); }}
  .mcap.sev-c {{ background: var(--critical); }}
  .mcap.lit.sev-h {{ box-shadow: 0 0 6px 1px rgba(51,199,89,0.55); }}
  .mcap.lit.sev-l {{ box-shadow: 0 0 6px 1px rgba(255,158,10,0.55); }}
  .mcap.lit.sev-c {{ box-shadow: 0 0 6px 1px rgba(255,87,73,0.60); }}
  .mfill.ramp-h {{ background: linear-gradient(90deg, rgba(235,235,245,0.18), var(--healthy)); }}
  .mfill.ramp-l {{ background: linear-gradient(90deg, rgba(235,235,245,0.18), var(--low)); }}
  .mfill.ramp-c {{ background: linear-gradient(90deg, rgba(235,235,245,0.22), var(--critical)); }}
  .m-pct.inkonly-l {{ color: var(--low); }}

  /* ---------- position variants ---------- */
  .numstack {{ display: inline-flex; flex-direction: column; align-items: flex-end; gap: 3px; }}
  .numstack .micro.under {{ width: 44px; height: 2.5px; align-self: stretch; }}

  /* ---------- tactility ---------- */
  .micro.proudtrack {{ overflow: visible; height: 4px; background: rgba(255,255,255,0.10); }}
  .micro.proudtrack .mfill {{ overflow: visible; }}
  .proudcap {{ position: absolute; right: -1px; top: 50%; transform: translateY(-50%); width: 3px; height: 9px; border-radius: 2px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.55), 0 0 0 0.5px rgba(255,255,255,0.12) inset; }}
  .proudcap.sev-h {{ background: var(--healthy); }}
  .proudcap.sev-l {{ background: var(--low); }}
  .proudcap.sev-c {{ background: var(--critical); }}
  .micro.dome {{ height: 6px; box-shadow: inset 0 -1px 2px rgba(0,0,0,0.4), inset 0 1px 1px rgba(255,255,255,0.14), 0 1px 2px rgba(0,0,0,0.35); }}
  .micro.dome .mfill {{ box-shadow: inset 0 1px 1px rgba(255,255,255,0.30); }}

  /* ---------- squint-question hover mock ---------- */
  .meter.hovered {{ background: rgba(255,255,255,0.045); margin: -5px -7px; padding: 5px 7px; border-radius: 8px; }}
  .track {{ height: 8px; border-radius: 99px; background: var(--track); position: relative; overflow: visible; }}
  .fill {{ position: absolute; inset: 0 auto 0 0; border-radius: 99px; min-width: 8px; }}
  .fill.glassfill {{ background: linear-gradient(180deg, rgba(255,255,255,0.18), rgba(255,255,255,0.09)); box-shadow: inset 0 0.5px 0 rgba(255,255,255,0.22); }}
  .capline {{ position: absolute; right: 0; top: 0; bottom: 0; width: 3.5px; border-radius: 99px; }}
  .capline.sev-l {{ background: var(--low); }}

  /* ---------- full-scale popover ---------- */
  .shots2 {{ display: grid; grid-template-columns: 1fr 1fr; gap: 24px; align-items: start; }}
  .pop-wrap {{ display: flex; flex-direction: column; gap: 12px; }}
  .pop-wrap figcaption {{ font-size: 12px; color: var(--text-tertiary); padding: 0 6px; }}
  .popover-full {{ width: 388px; max-width: 100%; margin: 0 auto; background: var(--popover-bg); border-radius: 18px; padding: 22px; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.05), 0 24px 60px rgba(0,0,0,0.5); display: flex; flex-direction: column; gap: 14px; }}
  .pop-head {{ display: flex; align-items: center; padding: 2px 2px 4px; }}
  .pop-title {{ font-size: 22px; font-weight: 700; letter-spacing: -0.3px; }}
  .pop-updated {{ margin-left: auto; font-size: 12px; color: var(--text-tertiary); }}
  .pop-gear {{ margin-left: 12px; color: var(--text-secondary); font-size: 15px; }}
  .pop-foot {{ display: flex; justify-content: space-between; padding: 4px 2px 0; }}
  .pop-foot span {{ font-size: 13px; font-weight: 600; color: var(--text-secondary); }}
  .pop-card {{ width: 100%; }}
  .acct-block {{ display: flex; flex-direction: column; gap: 9px; }}
  .chunk-gap {{ height: 14px; }}

  .verdict {{ margin-top: 40px; padding: 26px 30px; border-radius: 16px; background: linear-gradient(180deg, var(--tile-top), var(--tile-bottom)); box-shadow: inset 0 0 0 1px var(--ring), 0 10px 30px rgba(0,0,0,0.35); max-width: 820px; }}
  .verdict h3 {{ font-size: 15px; font-weight: 700; margin-bottom: 10px; }}
  .verdict p, .verdict li {{ font-size: 13.5px; color: var(--text-secondary); }}
  .verdict ul {{ padding-left: 18px; display: flex; flex-direction: column; gap: 6px; margin-top: 6px; }}
</style>
<body>
<div class="page">

  <header class="masthead">
    <div class="eyebrow">Headroom · design feedback · round 3 · Aug 2026</div>
    <h1>The micro-gauge, explored</h1>
    <p class="lede">Ridd's video review of round 2 landed on one clear winner and one clear instruction: <strong style="color:var(--text-primary)">the micro-gauge is the concept</strong>, and <strong style="color:var(--text-primary)">the next round should sweep every variable around it</strong>. This document is that sweep — four axes (form, fill, position, tactility), then the winner at real multi-account scale. Everything else from the video is treated as settled and locked into the frame.</p>
  </header>

  <div class="quotes">
    <div class="quote">
      <div class="who">The verdict · 01:57–03:27</div>
      <p>"Man, maybe this micro gauge is my favorite actually. <em>It's so much easier to parse.</em> … I like the full logo and the micro gauge. I think that's my favorite concept so far — it's just so much easier to read the text labels <em>when they're not competing with a bar</em>. Like I actually only need that much space to see where we're at progress-wise. I don't need the full bar."</p>
    </div>
    <div class="quote">
      <div class="who">The ask · 06:17–06:34</div>
      <p>"There's only one concept of that though, so I would almost do another round — I'd push on this micro gauge and see… <em>what are all the variables that you could tweak around the micro gauge concept?</em> That's probably what I would do next."</p>
    </div>
  </div>
  <p class="transcript-note">Verbatim from the Supercut transcript of his screen recording (Aug 14) — he was scrolling the round-2 exploration doc while talking.</p>

  <!-- ============ SETTLED FRAME ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker" style="color:var(--text-tertiary)">Locked before we start</div>
      <h2>The settled frame</h2>
      <p>Decisions the video already made. Every mockup below inherits all of these, so the only thing varying in each grid is the gauge itself.</p>
    </div>
    <div class="decisions">
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>Full logo + provider name</strong> as the header — his favorite combo pairs it with the micro-gauge. <span class="ts">03:22</span></p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>The plan chip.</strong> "I like the chip. I think this is well done." <span class="ts">05:38</span></p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>Sentence-case labels.</strong> "You basically can't do caps case anymore — it just looks like AI." Retires L2 small caps, last round's pick. <span class="ts">05:32</span></p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>Personal/Work chunked by gap, no hairline.</strong> "You're basically getting that for free… just a little bit of an extra gap so it's clear they're chunked." <span class="ts">05:06–05:13</span></p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>Brighter label text on glass fills</strong> — "this label text should be white… a little more color contrast." <span class="ts">04:20–04:35</span></p></div>
      <div class="decision"><span class="d-mark d-kill">KILL</span><p><strong>The icon before the email address.</strong> "I don't know what this icon is… I would probably get rid of that." <span class="ts">05:42</span></p></div>
      <div class="decision"><span class="d-mark d-kill">KILL</span><p><strong>Red→green gradients everywhere.</strong> "You kind of get lost." Slim bars already accomplish the quieting. <span class="ts">01:28</span></p></div>
      <div class="decision"><span class="d-mark d-kill">KILL</span><p><strong>The glow and the literal knob.</strong> Glow is "a little bit out there"; the knob is "cool… I don't know if that's necessary though." Parked, not deleted. <span class="ts">01:50 · 04:11</span></p></div>
    </div>
  </section>

  <!-- ============ AXIS 1: FORM ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-form">Axis 1</div>
      <h2>Form — what shape is the gauge?</h2>
      <p>Same three windows in every mockup (72% healthy · 38% low · 12% critical). The constraint that made the original work: the gauge stays small enough that the label never competes with it. Every form here fits inside a 20pt-tall row.</p>
    </div>
    <div class="grid">
{option('·', 'Chip bar', 'The round-2 original — 32×5pt capsule docked at the numeral', card('chip'), 'The reference. Everything below is judged against this: length reads at a glance, severity color is a whisper at this size, row height unchanged.', ref=True)}
{option('M1', 'Machined chip', "The instrument well from round 2's winning family, at micro scale", card('well'), "The chip wearing the recessed-well body — carved into the tile, lit fill inside. Bridges this round to the quiet-instrument direction the full-size bars landed on, so popover and gauge stay one material language. <strong>Watch:</strong> at 6pt tall the inner shadow is nearly subliminal; it must survive a real retina render, not just this mock.")}
{option('M2', 'Arc', 'A semicircular sweep beside the numeral — speedometer grammar', card('arc'), 'The most "gauge" of the gauges. The arc reads as an instrument instantly, and the empty sweep gives low values real drama. Costs more optical height than the chip and its center whitespace does nothing.')}
{option('M3', 'Ring', 'A closed dial — progress-ring grammar at 15pt', card('ring'), "Familiar from watchOS and menu-bar apps — which is the argument against it: it reads “activity ring,” not “fuel remaining.” Angular position is also harder to compare across rows than aligned lengths. Included to be disprovable.")}
{option('M4', 'Tick strip', 'Five quanta — console ticks at micro scale', card('ticks'), "Quantized to fifths, with the last lit tick at full saturation (the reading edge survives). Loses precision on purpose — 38% and 45% look identical. That might be honest (you act on fifths, not percents) or might fight the numeral beside it.")}
{option('M5', 'Vertical tube', 'A 16pt standing column — fuel-gauge grammar', card('vert'), 'The only form that breaks the horizontal reading line, which is both its charm and its cost: a column of these makes a tiny skyline, but each one adds ~6pt of row height and the eye must switch scanning direction to compare.')}
    </div>
  </section>

  <!-- ============ AXIS 2: FILL ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-fill">Axis 2</div>
      <h2>Fill — what carries the severity?</h2>
      <p>All on the chip form so only the recipe changes. This is the same "does healthy get a hue?" question the full-size bars asked last round, re-asked at 32pt — where the answer might differ, because 32pt of green is already a whisper.</p>
    </div>
    <div class="grid">
{option('·', 'Solid severity', 'The round-2 original — full-saturation fill in all three states', card('chip'), "The reference. Ridd reacted to exactly this and didn't flag the color — at this size the solid fill may simply be fine.", ref=True)}
{option('R1', 'Grey glass, lit cap', "Frosted fill, all color compressed into the cap", card('glasscap'), 'Round 2’s recommended full-size recipe (S) shrunk onto the chip: the length is glass, the 2.5pt cap wears the severity. His gray-glass interest points here — "the gray glass could be fun… you’d have to dial in the details." <strong>Watch:</strong> at 32pt the cap is genuinely small; the severity signal may need the numeral ink as backup.', tag="His gray-glass thread")}
{option('R2', 'Color as event', 'Healthy is glass; only amber and red earn pigment', card('event'), 'The loudness-budget logic: on a healthy day the gauges are colorless machinery and the popover goes fully calm; the moment a window degrades, its gauge is the only colored thing on the surface. The strongest scan-hierarchy of the five.', tag='mine')}
{option('R3', 'Ink only', 'Gauge stays pure glass; severity lives in the numeral', card('inkonly'), "The gauge gives length, the numeral gives judgment (the 38% wears amber ink, the 12% keeps its critical red). Cleanest separation of duties — but severity now depends entirely on reading the number, which half-defeats the at-a-glance promise.")}
{option('R4', 'Hue ramp', 'Neutral at the tail, resolving to severity color at the reading edge', card('ramp'), "His round-1 gradient ask, compressed. At 32pt the ramp run is so short it mostly reads as a slightly-soft solid — which suggests the gradient idea has already done its job at this scale and can retire.")}
    </div>
  </section>

  <!-- ============ AXIS 3: POSITION ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-pos">Axis 3</div>
      <h2>Position — where does it dock?</h2>
      <p>The chip again, moving around the row. The original docked it immediately left of the numeral, making one right-aligned reading cluster: gauge → number → unit. Also here: the "12% left" framing he paused on.</p>
    </div>
    <div class="grid">
{option('·', 'Before the numeral', 'The round-2 original — one reading cluster at the right edge', card('chip'), "The reference. Gauge and numeral form a single fixation target: glance at the right edge, get both length and value. This is most of why it parses so fast.", ref=True)}
{option('P1', 'After the unit', 'Numeral first, gauge trailing at the row edge', card('chip', pos='p2'), "Ragged left edge of the numeral column — percentages of different widths no longer right-align, so the scan down the column stutters. The gauge does gain a perfectly aligned rail at the row edge. Likely worse; cheap to disprove.")}
{option('P2', 'Leading the row', 'Gauge before the label — a status rail on the left', card('chip', pos='p3'), "Turns the gauge column into the first thing the eye meets — a severity rail, like diff gutters in an editor. Interesting for the all-healthy monochrome case (a calm grey rail), but it re-introduces exactly what Ridd praised removing: something visual competing with the labels.")}
{option('P3', 'Under the numeral', 'A 2.5pt underline beneath the value cluster', card('chip', pos='p4'), 'The gauge as underline — typographic rather than instrumental. Quietest of the four and the row stays text-only until you look closely. Adds ~5pt of row height, and the tiny offset bar can read as decoration rather than data.')}
{option('F1', '“12% left”', 'Remaining framing — the number is fuel', card('event'), '"Having the 12% left is interesting… I guess that’s how it works right now" — he noticed the framing and didn’t reject it. Remaining matches the mental model of the menu-bar number and the gauge itself (both show what’s left in the tank).', tag='!He paused on this')}
{option('F2', '“88% used”', 'Consumption framing — the number is spend', card('event', term='used'), "The alternative reading. Spend framing matches invoices and the API cost view, but it inverts the gauge (a nearly-empty chip beside a large number) and every surface in Headroom today says “left.” Included so the choice is explicit, not accidental.")}
    </div>
  </section>

  <!-- ============ AXIS 4: TACTILITY ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-tact">Axis 4</div>
      <h2>Tactility — “like you could almost touch it”</h2>
      <p>His round-1 thread, applied to the winner: "it could be fun if the line had a shadow to it and was slightly bigger than the actual bar container, where it kind of felt like you could almost touch it… a little bit of tactility could be fun" (01:13–01:24). Three doses, quiet to loud. All static — light and depth, no motion.</p>
    </div>
    <div class="grid">
{option('T1', 'Proud cap', 'The reading edge stands off the track with a real drop shadow', card('proud'), 'The literal version of his ask: the severity cap is a 9pt pin sitting proud of a 4pt glass track, with the shadow doing the "you could touch it" work. The one physical element per row lands exactly where the eye reads the value.', tag="!His tactility ask")}
{option('T2', 'Lit cap', 'The glass-cap recipe with a soft static bloom at the edge', card('lit'), "R1 with the cap lit from within — the bloom is a fixed few pixels, far below the full-bar glow he called “a little bit out there.” Depth from light rather than shadow, matching the elevation language of the round-2 instrument family. Static always; nothing breathes or pulses.")}
{option('T3', 'Domed chip', 'The whole gauge as a convex glass bead', card('dome'), "Tactility applied to the container instead of the indicator: highlight on top, shadow underneath, so the chip reads as a small physical object set into the row. The subtlest of the three and the most likely to vanish at 1× — needs a live retina check.")}
    </div>
  </section>

  <!-- ============ REAL SCALE ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker" style="color:var(--codex-accent)">The proof</div>
      <h2>At real scale</h2>
      <p>The micro-gauge's whole pitch is parseability, and that claim is only testable on the dense surface: two providers, multi-account, the settled frame applied. Both popovers use the color-as-event recipe (R2) — left is a degraded day, right is the same surface with everything healthy.</p>
    </div>
    <div class="shots2">
      <figure class="pop-wrap">
        {popover(healthy=False)}
        <figcaption>A degraded day: Work's weekly window is the only red thing on the surface, Personal's amber ranks second. The scan order is severity order.</figcaption>
      </figure>
      <figure class="pop-wrap">
        {popover(healthy=True)}
        <figcaption>All healthy: the gauges go full glass and the popover is monochrome and calm — color is an event, not a state. If green-means-good wins instead, run the same A/B flip as round 2's build test.</figcaption>
      </figure>
    </div>
  </section>

  <!-- ============ THE SQUINT QUESTION ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker" style="color:var(--low)">One pushback</div>
      <h2>The squint question</h2>
      <p>"I actually only need that much space" is true while reading a mockup at arm's length. But the full-width bar had one real virtue the chip gives up: a length you can read from across the room, without focusing. Before committing, one variant tests whether hover should buy that back.</p>
    </div>
    <div class="grid">
{option('Q1', 'Full bar on hover', 'The row under the pointer reveals the full-width track', hover_mock, "The middle row is shown hovered: the micro-gauge yields to the full glass bar with the amber cap while the pointer rests there, then collapses back. Detail on demand — the resting state keeps Ridd's clean text rows, the hover state keeps the squint read. If this earns its keep, it's also the natural home for tooltip-grade detail (exact reset time, absolute quota).")}
      <div class="option reference">
        <div class="option-head">
          <span class="option-letter">·</span>
          <div><div class="option-title">Or: accept the trade</div><div class="option-sub">The numeral is the squint read</div></div>
        </div>
        <p class="option-note" style="font-size:13px; color:var(--text-secondary)">The counter-argument: an 18pt semibold numeral <em>is</em> readable from across the room — arguably more so than a bar length. If the numbers carry the distant read and the gauges carry the shape, hover-reveal is machinery without a job. Decide this on the live surface, not in this document: put the chip build on the menu bar for two days and notice whether you ever miss the long bars.</p>
      </div>
    </div>

    <div class="verdict">
      <h3>Where this lands</h3>
      <p><strong style="color:var(--text-primary)">Build the chip, vary only the fill.</strong> Form is the least-open question — the chip (or M1, its machined twin) preserved everything Ridd praised, and the exotic forms each give up either alignment, precision, or row height. The genuinely open axis is fill: R2 (color as event) against the reference solid, flipped live like round 2's build test. Keep position as-is — the right-edge reading cluster is most of the concept's speed.</p>
      <ul>
        <li><strong style="color:var(--text-primary)">Build order:</strong> chip + R2 into the real popover behind the demo fixtures, side-by-side with solid-fill. Then the all-healthy day decides "does healthy get a hue" with evidence.</li>
        <li><strong style="color:var(--text-primary)">Tactility is seasoning, not structure:</strong> T1 (proud cap) is the cheapest faithful version of his ask — try it only after the fill question settles, so two variables never move at once.</li>
        <li>The settled frame (sentence case, chip pill, no email icon, gap-chunked accounts, no dividers) can ship independently of the gauge decision — none of it is blocked on this round.</li>
        <li>Everything here is dark-first again. The glass fills and lit caps need the same light-mode pass and live glass-card check as the round-2 family before any of it is called done.</li>
        <li>The severity ramp stays load-bearing (UI-01): whatever recipe wins must keep green→amber→red semantics and propagate to the widget meters through the shared tokens. The micro-gauge is already the widget compact meter's close cousin — this round may quietly unify them.</li>
        <li>Keep "left" framing (F1) unless a real argument for "used" appears; today every Headroom surface says left, and he didn't object.</li>
      </ul>
    </div>
  </section>

  <footer style="color:var(--text-tertiary); font-size:12px;">
    Built from Ridd's Supercut video review (Aug 14, 7m) of the round-2 exploration doc · mockups use Headroom's real dark-scheme tokens from <code>BrandColorValues.swift</code> · timestamps reference the <a href="https://supercut.ai/share/dive/nmOGI4p8H9qWEuPrbk5Tjl" style="color:var(--text-secondary)">shared recording</a>
  </footer>
</div>
</body>
</html>
'''

open(OUT, 'w').write(html)
print('wrote', OUT, len(html), 'bytes')
