#!/usr/bin/env python3
"""Generate design/ridd-round4-meter-style.html — round 4 (rev 5) of the Ridd feedback series.

Rev 5 renders the one full-width candidate retained by rev 4 at one, two, and five
same-provider accounts in both schemes. Rev 4 consolidated Kyle's choices, resolved D2
to accessible scheme-specific values, and recorded the full-width recommendation. Rev 3
settled labels at 90%, a bare countdown, baseline-aligned label/countdown and numeral/unit
clusters, flat fills, and an OKLCH-audited light palette. The hue ramp remains in the
running, including a stepped version for ticks, while arc/ring stay parked.
Logos come from the round-2 doc, same as the round-3 generator.
"""
import re

SRC = 'design/ridd-feedback-explorations.html'
OUT = 'design/ridd-round4-meter-style.html'
raw = open(SRC).read()

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

# label, countdown, pct, sev, crit-class
WINDOWS = [('5-hour', '3h 11m', 72, 'h', ''),
           ('Weekly', '3d 23h', 38, 'l', ''),
           ('Weekly (Fable)', '3d 23h', 12, 'c', ' crit')]

def _ticks(pct, sev, mode):
    """mode: solid | cap | event | ramp (stepped hue per lit tick)"""
    n_on = round(pct / 20)
    out = []
    for j in range(5):
        cls, style = 'gt', ''
        if j < n_on:
            if mode == 'ramp':
                cls += ' tick-on'
                if j == n_on - 1:
                    style = f' style="background: var(--sev-{sev})"'
                else:
                    mix = 45 + round(55 * j / max(n_on - 1, 1))
                    style = f' style="background: color-mix(in srgb, var(--sev-{sev}) {mix}%, var(--tick-neutral))"'
            elif mode == 'cap' or (mode == 'event' and sev == 'h'):
                cls += ' tick-on tick-glass'
                if j == n_on - 1:
                    cls += ' tickcap-glass' if (mode == 'event' and sev == 'h') else ''
                    if mode == 'cap':
                        cls = f'gt tick-on tickcap sev-{sev}'
            else:
                cls += f' tick-on sev-{sev}'
                if j == n_on - 1:
                    cls = f'gt tick-on tickcap sev-{sev}'
        out.append(f'<span class="{cls}"{style}></span>')
    return f'<span class="g-ticks">{"".join(out)}</span>'

def gauge(form, fill, pct, sev, dose=''):
    """form: chip|well|ticks|vert · fill: solid|cap|event|ramp · dose: ''|pf|pf1|wellpf"""
    if form == 'ticks':
        return _ticks(pct, sev, fill)
    if form == 'vert':
        cap = f'<span class="gv-cap sev-{sev}"></span>' if fill == 'cap' else ''
        if fill == 'solid':
            body = f'gv-fill sev-{sev}'
        elif fill == 'cap':
            body = 'gv-fill gv-glass'
        elif fill == 'event':
            body = 'gv-fill gv-glass' if sev == 'h' else f'gv-fill sev-{sev}'
        elif fill == 'ramp':
            body = f'gv-fill gv-ramp-{sev}'
        return f'<span class="g-vert"><span class="{body}" style="height:{pct}%">{cap}</span></span>'

    # chip + well share the capsule markup
    shell = 'micro'
    if form == 'well':
        shell += ' well'
    if dose == 'pf':
        shell += ' pf'
    if dose == 'pf1':
        shell += ' pf pf1'
    if dose == 'wellpf':
        shell = 'micro well wellpf'
    if fill == 'solid':
        body = f'mfill wsev-{sev}' if form == 'well' else f'mfill sev-{sev}'
    elif fill == 'cap':
        shell += ' glasschip'
        return (f'<span class="{shell}"><span class="mfill glass" style="width:{pct}%">'
                f'<span class="mcap sev-{sev}"></span></span></span>')
    elif fill == 'event':
        if sev == 'h':
            body = 'mfill glass'
        else:
            body = f'mfill wsev-{sev}' if form == 'well' else f'mfill sev-{sev}'
    elif fill == 'ramp':
        body = f'mfill ramp-{sev}'
    return f'<span class="{shell}"><span class="{body}" style="width:{pct}%"></span></span>'

def reset_html(countdown, mode):
    if mode == 'word':
        return f'<span class="m-reset">· Resets in {countdown}</span>'
    if mode == 'bare':
        return f'<span class="m-reset">{countdown}</span>'
    if mode == 'dim1':
        return f'<span class="m-reset dim1">{countdown}</span>'
    if mode == 'dim2':
        return f'<span class="m-reset dim2">{countdown}</span>'

def meter_text(label, countdown, pct, crit, term, reset_mode):
    # label+countdown and numeral+unit are baseline-aligned clusters; only the clusters
    # (and the gauge) are center-aligned in the row — mixed font sizes under flex `center`
    # were floating the 11px countdown above the 13px label's baseline
    num = (f'<span class="m-num"><span class="m-pct{crit}">{pct}%</span>'
           f'<span class="m-term">{term}</span></span>')
    lab = (f'<span class="m-lab"><span class="m-label">{label}</span>'
           f'{reset_html(countdown, reset_mode)}</span>')
    return lab, num

def meter_row(form, fill, label, countdown, pct, sev, crit, term='left', reset_mode='word', dose=''):
    g = gauge(form, fill, pct, sev, dose=dose)
    lab, num = meter_text(label, countdown, pct, crit, term, reset_mode)
    return (f'<div class="meter"><div class="meter-top">{lab}<span class="m-spacer"></span>{g}{num}</div></div>')

def card(form, fill, extra_cls='', reset_mode='word', dose=''):
    rows = '\n            '.join(
        meter_row(form, fill, *w, reset_mode=reset_mode, dose=dose) for w in WINDOWS)
    return (f'<div class="stage"><div class="card v-micro {extra_cls}">\n          '
            f'{prov_head()}\n          <div class="meters">\n            {rows}\n          </div>\n        </div></div>')

def option(letter, title, sub, body, note, tag=None, ref=False):
    tag_html = ''
    if tag == 'mine':
        tag_html = '<span class="ridd-tag mine">My read</span>'
    elif tag:
        tag_html = f'<span class="ridd-tag">{tag}</span>'
    return f'''      <div class="option{' reference' if ref else ''}">
        <div class="option-head">
          <span class="option-letter">{letter}</span>
          <div><div class="option-title">{title}</div><div class="option-sub">{sub}</div></div>
          {tag_html}
        </div>
        {body}
        <p class="option-note">{note}</p>
      </div>'''

# ---------- the style matrix (arc + ring parked in rev 2) ----------
FORMS = [('chip', 'Chip', 'round-2 original'),
         ('well', 'Machined', 'M1'),
         ('ticks', 'Ticks', 'M4'),
         ('vert', 'Tube', 'M5 · fill flattened')]
FILLS = [('solid', 'Solid'), ('cap', 'Glass + cap'), ('event', 'Color as event'), ('ramp', 'Hue ramp')]
WARN_COMBOS = {('ticks', 'ramp')}

def matrix():
    cells = ['<div></div>'] + [f'<div class="mx-head">{t}</div>' for _, t in FILLS]
    for form, title, sub in FORMS:
        cells.append(f'<div class="mx-form">{title}<span>{sub}</span></div>')
        for fill, _ in FILLS:
            warn = '<span class="warnmark">▲</span>' if (form, fill) in WARN_COMBOS else ''
            cells.append(f'<div class="cell">{warn}{gauge(form, fill, 72, "h")}{gauge(form, fill, 38, "l")}</div>')
    return '<div class="matrix">\n      ' + '\n      '.join(cells) + '\n    </div>'

# ---------- the settings-picker mock ----------
def swatch(inner, sel=False):
    return f'<span class="swatch{" sel" if sel else ""}">{inner}</span>'

def settings_mock():
    shapes = ''.join(swatch(gauge(f, 'event', 62, 'h'), sel=(f == 'chip')) for f, _, _ in FORMS)
    colors = ''.join(
        swatch(gauge('chip', fill, 62, 'h') + gauge('chip', fill, 38, 'l'), sel=(fill == 'event'))
        for fill, _ in FILLS)
    return f'''<div class="stage"><div class="settings-mock">
          <div class="sm-title">Meter style</div>
          <div class="sm-row"><span class="sm-label">Shape</span><div class="sm-swatches">{shapes}</div></div>
          <div class="sm-row"><span class="sm-label">Color</span><div class="sm-swatches">{colors}</div></div>
          <div class="sm-foot">Applies to every meter in the popover. Widgets follow.</div>
        </div></div>'''

# ---------- full-scale popover ----------
CLAUDE_ACCOUNTS = [
    ('Personal', 'Max', 'personal@example.com',
     [('Weekly', '3d 23h', 38, 'l', ''), ('5-hour', '3h 11m', 72, 'h', '')]),
    ('Work', 'Pro', 'work@example.com',
     [('Weekly', '3d 23h', 12, 'c', ' crit'), ('5-hour', '4h 02m', 29, 'l', '')]),
    ('Studio', 'Max', 'studio@example.com',
     [('Weekly', '5d 04h', 64, 'h', ''), ('5-hour', '1h 40m', 91, 'h', '')]),
    ('Client', 'Pro', 'client@example.com',
     [('Weekly', '2d 08h', 46, 'l', ''), ('5-hour', '2h 26m', 57, 'h', '')]),
    ('Lab', 'Max', 'lab@example.com',
     [('Weekly', '18h 12m', 8, 'c', ' crit'), ('5-hour', '3h 44m', 81, 'h', '')]),
]
CODEX_PERSONAL_METERS = [('Weekly', '5d 4h', 64, 'h', ''), ('5-hour', '1h 40m', 91, 'h', '')]

def acct_block(name, plan, email, meters, form, fill, reset_mode, dose=''):
    rows = '\n        '.join(meter_row(form, fill, *mw, reset_mode=reset_mode, dose=dose) for mw in meters)
    return f'''<div class="acct-block">
        <div class="idline"><span class="id-name">{name}</span><span class="plan-pill">{plan}</span><span class="acct-email">{email}</span></div>
        {rows}
      </div>'''

def popover(form, fill, reset_mode='dim1', dose=''):
    cl_personal, cl_work = CLAUDE_ACCOUNTS[:2]
    return f'''<div class="popover-full lb90">
      <div class="pop-head"><span class="pop-title">Usage</span><span class="pop-updated">Updated 2 min ago</span><span class="pop-gear">⚙︎</span></div>
      <div class="card v-micro pop-card">
        {prov_head('Claude')}
        {acct_block(*cl_personal, form, fill, reset_mode, dose)}
        <div class="chunk-gap"></div>
        {acct_block(*cl_work, form, fill, reset_mode, dose)}
      </div>
      <div class="card v-micro pop-card">
        {prov_head('Codex')}
        {acct_block('Personal', 'Plus', 'personal@example.com', CODEX_PERSONAL_METERS, form, fill, reset_mode)}
      </div>
      <div class="pop-foot"><span>Check now</span><span>Settings</span></div>
    </div>'''

# ---------- expanded-layout proof: K recessed instrument × T color-as-event ----------
def expanded_gauge(pct, sev):
    ticks = ''.join(f'<i class="full-tick" style="left:{mark}%"></i>' for mark in (25, 50, 75))
    fill_class = 'full-fill event-neutral' if sev == 'h' else f'full-fill event-{sev}'
    return (f'<span class="full-well">{ticks}'
            f'<span class="{fill_class}" style="width:{pct}%"></span></span>')

def expanded_meter_row(label, countdown, pct, sev, crit, term='left'):
    lab, num = meter_text(label, countdown, pct, crit, term, 'dim1')
    return (f'<div class="meter meter-expanded"><div class="meter-top">{lab}'
            f'<span class="m-spacer"></span>{num}</div>{expanded_gauge(pct, sev)}</div>')

def density_account(account, layout):
    name, plan, email, meters = account
    if layout == 'micro':
        rows = ''.join(meter_row('chip', 'event', *meter, reset_mode='dim1') for meter in meters)
    elif layout == 'expanded':
        rows = ''.join(expanded_meter_row(*meter) for meter in meters)
    else:
        raise ValueError(f'unknown density layout: {layout}')
    return f'''<div class="acct-block">
        <div class="idline"><span class="id-name">{name}</span><span class="plan-pill">{plan}</span><span class="acct-email">{email}</span></div>
        <div class="density-meters">{rows}</div>
      </div>'''

def density_popover(layout, count):
    if layout not in {'micro', 'expanded'}:
        raise ValueError(f'unknown density layout: {layout}')
    accounts = ''.join(density_account(account, layout) for account in CLAUDE_ACCOUNTS[:count])
    return f'''<div class="popover-full density-popover lb90" data-layout="{layout}" data-account-count="{count}">
      <div class="pop-head"><span class="pop-title">Usage</span><span class="pop-updated">Updated 2 min ago</span><span class="pop-gear">⚙︎</span></div>
      <div class="card v-micro pop-card density-pop-card">
        {prov_head('Claude')}
        {accounts}
      </div>
      <div class="pop-foot"><span>Check now</span><span>Settings</span></div>
    </div>'''

def density_row(count):
    noun = 'account' if count == 1 else 'accounts'
    return f'''<div class="density-row">
      <div class="density-count"><strong>{count}</strong><span>{noun}</span></div>
      <div class="density-cell">{density_popover('micro', count)}</div>
      <div class="density-cell">{density_popover('expanded', count)}</div>
    </div>'''

DENSITY_COUNTS = (1, 2, 5)

def density_theme_panel(title, extra_class, readout):
    rows = ''.join(density_row(count) for count in DENSITY_COUNTS)
    return f'''<div class="theme-proof{extra_class}">
      <h3>{title}</h3>
      <div class="density-scroller">
        <div class="density-board">
          <div class="density-head">
            <div></div>
            <div class="density-column-title"><strong>Current micro default</strong><span>Chip + color-as-event · one-line rows</span></div>
            <div class="density-column-title"><strong>K × T expanded candidate</strong><span>Recessed full-width instrument · two-line rows</span></div>
          </div>
          {rows}
        </div>
      </div>
      <p class="proof-read">{readout}</p>
    </div>'''

# ============================================================ CSS
# Scheme-varying values live in custom properties; `.light` re-declares them with the real
# light tokens from BrandColorValues.swift (containerBackground*, tileFill*, barTrack,
# secondary/tertiaryText, HeadroomSeverityColorValues light hues).
CSS = '''
  :root {
    --page-bg: #0a0b0e;

    /* dark tokens from BrandColorValues.swift */
    --popover-bg: #1d1f23;
    --tile-top: #25272d;
    --tile-bottom: #191b21;
    --ring: rgba(255,255,255,0.065);
    --track: rgba(255,255,255,0.14);
    --text-primary: #f2f2f7;
    --text-secondary: rgba(235,235,245,0.66);
    --text-tertiary: rgba(235,235,245,0.56);
    --sev-h: #33c759;
    --sev-l: #ff9e0a;
    --sev-c: #ff5749;
    --critical-text: #ff6659;
    --claude-accent: #e88f69;
    --codex-accent: #96a1ff;
    --pill-bg: rgba(255,255,255,0.09);

    --glass-a: rgba(255,255,255,0.22);
    --glass-b: rgba(255,255,255,0.11);
    --glass-rim: rgba(255,255,255,0.25);
    --tick-off: rgba(255,255,255,0.09);
    --tick-glass: rgba(255,255,255,0.26);
    --tick-glass-cap: rgba(255,255,255,0.52);
    --tick-neutral: #6a6c74;
    --ramp-neutral: rgba(235,235,245,0.18);

    --label-84: rgba(235,235,245,0.84);
    --label-90: rgba(235,235,245,0.90);
    --reset-dim1: rgba(235,235,245,0.53);
    --reset-dim2: rgba(235,235,245,0.40);

    --cell-bg: #1d1f23;
    --cell-ring: rgba(255,255,255,0.035);
  }
  .light {
    /* light tokens from BrandColorValues.swift */
    color: var(--text-primary);
    --popover-bg: #f1f3f6;            /* containerBackground light, flattened */
    --tile-top: #ffffff;              /* tileFillTop light */
    --tile-bottom: #fbfbfc;           /* tileFillBottom light */
    --ring: rgba(0,0,0,0.05);         /* tileRing light */
    --track: rgba(0,0,0,0.12);        /* barTrack light */
    --text-primary: #1d1f24;
    --text-secondary: rgba(61,61,66,0.84);   /* secondaryText light */
    --text-tertiary: rgba(61,61,66,0.74);    /* tertiaryText light */
    /* rev-3 audited light fills — hue held from the dark tokens (amber drifts 8.7°
       toward orange, inside the 10° threshold, because orange keeps more chroma there),
       each at its max lightness that still clears 3:1 vs the #e0e0e0 track composite,
       chroma at 92% of gamut max. Proposal for a light severityFill token set in
       BrandColorValues — the 4.5:1 *text* tokens (criticalText etc.) stay untouched. */
    --sev-h: #20913e;                 /* oklch(0.579 0.156 147.5) · 3.07:1 vs track */
    --sev-l: #bb6a1d;                 /* oklch(0.605 0.133 58.0)  · 3.06:1 vs track */
    --sev-c: #f42a24;                 /* oklch(0.623 0.235 28.4)  · 3.06:1 vs track */
    --critical-text: #d1241c;         /* criticalText light — unchanged, tuned for 4.5:1 */
    --claude-accent: #b2541c;         /* claude light accent */
    --codex-accent: #3340d6;          /* codex light accent */
    --pill-bg: rgba(0,0,0,0.06);

    /* light "glass" is a cool steel gradient, not black-alpha gray — flat gray at the
       track's own hue is what read as a disabled slider */
    --glass-a: #757c86;
    --glass-b: #666c75;
    --glass-rim: rgba(255,255,255,0.30);
    --tick-off: rgba(0,0,0,0.08);
    --tick-glass: #6b727b;
    --tick-glass-cap: #474e57;
    --tick-neutral: #b6bcc6;
    --ramp-neutral: #a6abb2;

    --label-84: rgba(29,31,36,0.86);
    --label-90: rgba(29,31,36,0.92);
    --reset-dim1: rgba(61,61,66,0.72);
    --reset-dim2: rgba(61,61,66,0.54);

    --cell-bg: #f1f3f6;
    --cell-ring: rgba(0,0,0,0.045);
  }
  * { margin: 0; padding: 0; box-sizing: border-box; }
  body {
    font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", "Helvetica Neue", sans-serif;
    background: var(--page-bg); color: var(--text-primary);
    -webkit-font-smoothing: antialiased; line-height: 1.5;
  }
  .page { max-width: 1120px; margin: 0 auto; padding: 64px 32px 120px; }

  header.masthead { margin-bottom: 20px; }
  .eyebrow { font-size: 12px; font-weight: 700; letter-spacing: 1.4px; text-transform: uppercase; color: var(--text-tertiary); margin-bottom: 10px; }
  h1 { font-size: 32px; font-weight: 700; letter-spacing: -0.5px; margin-bottom: 8px; }
  .lede { font-size: 15px; color: var(--text-secondary); max-width: 660px; }

  .quotes { display: grid; grid-template-columns: 1fr 1fr; gap: 16px; margin: 36px 0 12px; }
  .quote { background: linear-gradient(180deg, var(--tile-top), var(--tile-bottom)); box-shadow: inset 0 0 0 1px var(--ring), 0 8px 24px rgba(0,0,0,0.35); border-radius: 14px; padding: 22px 24px; }
  .quote .who { font-size: 11px; font-weight: 700; letter-spacing: 0.8px; text-transform: uppercase; color: var(--text-tertiary); margin-bottom: 10px; }
  .quote p { font-size: 14px; color: var(--text-secondary); }
  .quote p em { color: var(--text-primary); font-style: normal; font-weight: 600; }
  .transcript-note { font-size: 12px; color: var(--text-tertiary); margin-bottom: 56px; }

  section { margin-bottom: 88px; }
  .section-head { max-width: 720px; margin-bottom: 28px; }
  .section-kicker { font-size: 12px; font-weight: 700; letter-spacing: 1.2px; text-transform: uppercase; margin-bottom: 8px; }
  .k-style { color: var(--sev-h); }
  .k-tact { color: var(--sev-l); }
  .k-read { color: var(--claude-accent); }
  .k-reset { color: var(--codex-accent); }
  h2 { font-size: 24px; font-weight: 700; letter-spacing: -0.3px; margin-bottom: 8px; }
  .section-head p { font-size: 14px; color: var(--text-secondary); }

  .grid { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; }
  .grid > * { min-width: 0; }

  .option { background: rgba(255,255,255,0.025); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.05); border-radius: 18px; padding: 24px; display: flex; flex-direction: column; gap: 16px; }
  .option.reference { background: rgba(255,255,255,0.012); }
  .option-head { display: flex; align-items: baseline; gap: 10px; }
  .option-letter { font-size: 12px; font-weight: 700; min-width: 22px; height: 22px; border-radius: 7px; display: inline-flex; align-items: center; justify-content: center; background: rgba(255,255,255,0.10); color: var(--text-primary); flex-shrink: 0; transform: translateY(4px); padding: 0 5px; }
  .option-title { font-size: 16px; font-weight: 650; }
  .option-sub { font-size: 13px; color: var(--text-secondary); }
  .option-note { font-size: 12.5px; color: var(--text-tertiary); }
  .option-note strong { color: var(--text-secondary); font-weight: 600; }
  .ridd-tag { display: inline-block; font-size: 10.5px; font-weight: 600; letter-spacing: 0.3px; padding: 2px 8px; border-radius: 99px; background: rgba(232,143,105,0.14); color: var(--claude-accent); margin-left: auto; flex-shrink: 0; transform: translateY(2px); white-space: nowrap; }
  .ridd-tag.mine { background: rgba(150,161,255,0.13); color: var(--codex-accent); }

  /* decision list */
  .decisions { display: grid; grid-template-columns: 1fr 1fr; gap: 12px 24px; margin-top: 4px; }
  .decision { display: flex; gap: 12px; align-items: baseline; background: rgba(255,255,255,0.02); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.045); border-radius: 12px; padding: 14px 18px; }
  .decision .d-mark { font-size: 12px; font-weight: 700; flex-shrink: 0; width: 52px; }
  .d-keep { color: var(--sev-h); }
  .d-new { color: var(--codex-accent); }
  .d-fix { color: var(--sev-l); }
  .d-kill { color: var(--critical-text); }
  .d-defer { color: var(--text-tertiary); }
  .decision p { font-size: 13px; color: var(--text-secondary); }
  .decision p strong { color: var(--text-primary); font-weight: 600; }

  /* ---------- popover / card chassis ---------- */
  .stage { background: var(--popover-bg); border-radius: 16px; padding: 22px; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.04); display: flex; flex-direction: column; align-items: center; gap: 14px; }
  .card { width: 344px; max-width: 100%; background: linear-gradient(180deg, var(--tile-top), var(--tile-bottom)); box-shadow: inset 0 0 0 1px var(--ring), 0 6px 18px rgba(0,0,0,0.38); border-radius: 10px; padding: 13px; }
  .light .card { box-shadow: inset 0 0 0 1px var(--ring), 0 4px 14px rgba(0,0,0,0.08); }

  .prov-head { display: flex; align-items: center; gap: 6px; margin-bottom: 10px; }
  .logo-box { width: 21px; height: 21px; display: inline-flex; align-items: center; justify-content: center; flex-shrink: 0; }
  .logo-box svg { width: 17.6px; height: 17.6px; }
  .prov-name { font-size: 16px; font-weight: 600; letter-spacing: -0.2px; }
  .prov-name.claude { color: var(--claude-accent); }
  .prov-name.codex { color: var(--codex-accent); }

  .idline { display: flex; align-items: baseline; gap: 6px; margin-bottom: 7px; min-width: 0; }
  .idline .id-name { font-size: 12.5px; font-weight: 600; color: var(--text-primary); }
  .plan-pill { font-size: 9.5px; font-weight: 500; color: var(--text-tertiary); background: var(--pill-bg); border-radius: 99px; padding: 1px 6px; }
  .acct-email { font-size: 10px; color: var(--text-tertiary); overflow: hidden; text-overflow: ellipsis; white-space: nowrap; min-width: 0; }

  /* meter row */
  .meters { display: flex; flex-direction: column; gap: 9px; }
  .v-micro .meters { gap: 12px; }
  .meter-top { display: flex; align-items: center; gap: 6px; min-width: 0; }
  .m-lab { display: inline-flex; align-items: baseline; gap: 6px; min-width: 0; }
  .m-num { display: inline-flex; align-items: baseline; gap: 5px; }
  .m-label { font-size: 13px; font-weight: 500; color: var(--text-secondary); white-space: nowrap; }
  .m-reset { font-size: 11px; color: var(--text-tertiary); font-variant-numeric: tabular-nums; white-space: nowrap; overflow: hidden; text-overflow: ellipsis; min-width: 0; }
  .m-reset.dim1 { color: var(--reset-dim1); }
  .m-reset.dim2 { color: var(--reset-dim2); }
  .m-spacer { flex: 1; }
  .m-pct { font-size: 18px; font-weight: 600; font-variant-numeric: tabular-nums; }
  .m-pct.crit { color: var(--critical-text); }
  .m-term { font-size: 11px; color: var(--text-tertiary); }
  .meter { display: flex; flex-direction: column; gap: 5px; }

  /* label-brightness variants */
  .lb84 .m-label { color: var(--label-84); }
  .lb90 .m-label { color: var(--label-90); }
  .lb100 .m-label { color: var(--text-primary); }

  /* ---------- micro-gauge forms ---------- */
  .micro { width: 32px; height: 5px; border-radius: 99px; background: var(--track); position: relative; overflow: hidden; flex-shrink: 0; align-self: center; }
  .micro .mfill { position: absolute; top: 0; bottom: 0; left: 0; border-radius: 99px; min-width: 3px; }
  .mfill.sev-h { background: color-mix(in srgb, var(--sev-h) 85%, transparent); }
  .mfill.sev-l { background: color-mix(in srgb, var(--sev-l) 85%, transparent); }
  .mfill.sev-c { background: color-mix(in srgb, var(--sev-c) 95%, transparent); }

  /* machined well */
  .micro.well { height: 6px; border-radius: 3.5px; background: #0f1114; overflow: visible;
    box-shadow: inset 0 1px 2px rgba(0,0,0,0.65), inset 0 -0.5px 0 rgba(255,255,255,0.05), 0 0.5px 0 rgba(255,255,255,0.045); }
  .light .micro.well { background: #dfe2e7;
    box-shadow: inset 0 1px 2px rgba(0,0,0,0.20), inset 0 -0.5px 0 rgba(255,255,255,0.7), 0 0.5px 0 rgba(255,255,255,0.6); }
  .micro.well .mfill { top: 1px; bottom: 1px; left: 1px; border-radius: 2.5px; box-shadow: inset 0 0.5px 0 var(--glass-rim); }
  .mfill.wsev-h { background: linear-gradient(180deg, color-mix(in srgb, var(--sev-h) 80%, transparent), color-mix(in srgb, var(--sev-h) 48%, transparent)); }
  .mfill.wsev-l { background: linear-gradient(180deg, color-mix(in srgb, var(--sev-l) 80%, transparent), color-mix(in srgb, var(--sev-l) 48%, transparent)); }
  .mfill.wsev-c { background: linear-gradient(180deg, color-mix(in srgb, var(--sev-c) 88%, transparent), color-mix(in srgb, var(--sev-c) 55%, transparent)); }

  /* K × T expanded candidate: a continuous recessed instrument whose healthy state
     stays neutral; severity color enters only at amber and critical. */
  .meter-expanded { gap: 6px; }
  .full-well { width: 100%; height: 8px; border-radius: 4.5px; background: #0f1114; overflow: hidden; position: relative; display: block;
    box-shadow: inset 0 1px 2.5px rgba(0,0,0,0.65), inset 0 -0.5px 0 rgba(255,255,255,0.05), 0 0.5px 0 rgba(255,255,255,0.045); }
  .light .full-well { background: #dfe2e7;
    box-shadow: inset 0 1px 2px rgba(0,0,0,0.20), inset 0 -0.5px 0 rgba(255,255,255,0.72), 0 0.5px 0 rgba(255,255,255,0.62); }
  .full-fill { position: absolute; inset: 1px auto 1px 1px; min-width: 3px; border-radius: 3px; box-shadow: inset 0 0.5px 0 var(--glass-rim); }
  .full-fill.event-neutral { background: linear-gradient(180deg, var(--glass-a), var(--glass-b)); }
  .full-fill.event-l { background: linear-gradient(180deg, color-mix(in srgb, var(--sev-l) 62%, transparent), color-mix(in srgb, var(--sev-l) 34%, transparent)); }
  .full-fill.event-c { background: linear-gradient(180deg, color-mix(in srgb, var(--sev-c) 88%, transparent), color-mix(in srgb, var(--sev-c) 54%, transparent));
    box-shadow: inset 0 0.5px 0 var(--glass-rim), 5px 0 12px -4px color-mix(in srgb, var(--sev-c) 48%, transparent); }
  .light .full-fill.event-l { background: linear-gradient(180deg, var(--sev-l), color-mix(in srgb, var(--sev-l) 74%, white)); }
  .light .full-fill.event-c { background: linear-gradient(180deg, var(--sev-c), color-mix(in srgb, var(--sev-c) 74%, white)); }
  .full-tick { position: absolute; z-index: 2; top: 2px; bottom: 2px; width: 1px; background: rgba(255,255,255,0.07); pointer-events: none; }
  .light .full-tick { background: rgba(0,0,0,0.08); }

  /* ticks */
  .g-ticks { display: inline-flex; gap: 2px; align-self: center; flex-shrink: 0; }
  .gt { width: 6px; height: 5px; border-radius: 1.5px; background: var(--tick-off); }
  .gt.tick-on.sev-h { background: color-mix(in srgb, var(--sev-h) 45%, transparent); }
  .gt.tick-on.sev-l { background: color-mix(in srgb, var(--sev-l) 45%, transparent); }
  .gt.tick-on.sev-c { background: color-mix(in srgb, var(--sev-c) 55%, transparent); }
  .gt.tick-on.tickcap.sev-h { background: var(--sev-h); }
  .gt.tick-on.tickcap.sev-l { background: var(--sev-l); }
  .gt.tick-on.tickcap.sev-c { background: var(--sev-c); }
  .gt.tick-on.tick-glass { background: var(--tick-glass); }
  .gt.tick-on.tickcap-glass { background: var(--tick-glass-cap); }

  /* vertical tube — fill flattened to a liquid level */
  .g-vert { width: 5px; height: 16px; border-radius: 99px; background: var(--track); position: relative; overflow: hidden; flex-shrink: 0; align-self: center; }
  .gv-fill { position: absolute; left: 0; right: 0; bottom: 0; min-height: 3px; border-radius: 0; }
  .gv-fill.sev-h { background: color-mix(in srgb, var(--sev-h) 85%, transparent); }
  .gv-fill.sev-l { background: color-mix(in srgb, var(--sev-l) 85%, transparent); }
  .gv-fill.sev-c { background: color-mix(in srgb, var(--sev-c) 95%, transparent); }
  .gv-fill.gv-glass { background: linear-gradient(180deg, var(--glass-a), var(--glass-b)); box-shadow: inset 0 0.5px 0 var(--glass-rim); }
  .gv-fill.gv-ramp-h { background: linear-gradient(to top, var(--ramp-neutral), var(--sev-h)); }
  .gv-fill.gv-ramp-l { background: linear-gradient(to top, var(--ramp-neutral), var(--sev-l)); }
  .gv-fill.gv-ramp-c { background: linear-gradient(to top, var(--ramp-neutral), var(--sev-c)); }
  .gv-cap { position: absolute; top: 0; left: 0; right: 0; height: 2.5px; border-radius: 1px; }
  .gv-cap.sev-h { background: var(--sev-h); }
  .gv-cap.sev-l { background: var(--sev-l); }
  .gv-cap.sev-c { background: var(--sev-c); }

  /* fills on the capsule */
  .mfill.glass { background: linear-gradient(180deg, var(--glass-a), var(--glass-b)); box-shadow: inset 0 0.5px 0 var(--glass-rim); }
  .micro.glasschip { overflow: visible; }
  .micro.glasschip .mfill { overflow: visible; }
  .mcap { position: absolute; right: -0.5px; top: -0.5px; bottom: -0.5px; width: 2.5px; border-radius: 2px; }
  .mcap.sev-h { background: var(--sev-h); }
  .mcap.sev-l { background: var(--sev-l); }
  .mcap.sev-c { background: var(--sev-c); }
  .mfill.ramp-h { background: linear-gradient(90deg, var(--ramp-neutral), var(--sev-h)); }
  .mfill.ramp-l { background: linear-gradient(90deg, var(--ramp-neutral), var(--sev-l)); }
  .mfill.ramp-c { background: linear-gradient(90deg, var(--ramp-neutral), var(--sev-c)); }

  /* light fills are opaque — the dark scheme's 85% alpha composites over the light
     gray track and drains ~15% of the chroma the audit just restored */
  .light .mfill.sev-h, .light .gv-fill.sev-h { background: var(--sev-h); }
  .light .mfill.sev-l, .light .gv-fill.sev-l { background: var(--sev-l); }
  .light .mfill.sev-c, .light .gv-fill.sev-c { background: var(--sev-c); }
  .light .gt.tick-on.sev-h { background: color-mix(in srgb, var(--sev-h) 45%, white); }
  .light .gt.tick-on.sev-l { background: color-mix(in srgb, var(--sev-l) 45%, white); }
  .light .gt.tick-on.sev-c { background: color-mix(in srgb, var(--sev-c) 55%, white); }
  .light .gt.tick-on.tickcap.sev-h { background: var(--sev-h); }
  .light .gt.tick-on.tickcap.sev-l { background: var(--sev-l); }
  .light .gt.tick-on.tickcap.sev-c { background: var(--sev-c); }
  .light .mfill.wsev-h { background: linear-gradient(180deg, var(--sev-h), color-mix(in srgb, var(--sev-h) 74%, white)); }
  .light .mfill.wsev-l { background: linear-gradient(180deg, var(--sev-l), color-mix(in srgb, var(--sev-l) 74%, white)); }
  .light .mfill.wsev-c { background: linear-gradient(180deg, var(--sev-c), color-mix(in srgb, var(--sev-c) 74%, white)); }

  /* the rev-2 light translation, kept for the before/after audit card */
  .oldlight { --sev-h: #178538; --sev-l: #b36900; --sev-c: #d92921;
    --glass-a: rgba(0,0,0,0.20); --glass-b: rgba(0,0,0,0.12); --glass-rim: rgba(255,255,255,0.10); }
  .oldlight .mfill.sev-h, .oldlight .gv-fill.sev-h { background: color-mix(in srgb, var(--sev-h) 85%, transparent); }
  .oldlight .mfill.sev-l, .oldlight .gv-fill.sev-l { background: color-mix(in srgb, var(--sev-l) 85%, transparent); }
  .oldlight .mfill.sev-c, .oldlight .gv-fill.sev-c { background: color-mix(in srgb, var(--sev-c) 95%, transparent); }

  /* ---------- tactility: the proud fill, rev-2 dialed dose ---------- */
  .micro.pf { overflow: visible; height: 4px; background: var(--track); }
  .micro.pf .mfill { top: -1px; bottom: -1px; overflow: visible;
    box-shadow: 0 1px 2px rgba(0,0,0,0.38), inset 0 0.5px 0 var(--glass-rim); }
  .light .micro.pf .mfill { box-shadow: 0 1px 2px rgba(0,0,0,0.16), inset 0 0.5px 0 var(--glass-rim); }
  .micro.pf .mcap { top: -0.5px; bottom: -0.5px; }
  /* rev-1 dose, kept for comparison */
  .micro.pf.pf1 .mfill { top: -1.5px; bottom: -1.5px;
    box-shadow: 0 1px 2.5px rgba(0,0,0,0.5), inset 0 0.5px 0 rgba(255,255,255,0.30); }
  .micro.well.wellpf { overflow: visible; }
  .micro.well.wellpf .mfill { top: -0.5px; bottom: -0.5px; left: 0; border-radius: 99px;
    box-shadow: 0 1px 2px rgba(0,0,0,0.42), inset 0 0.5px 0 var(--glass-rim); }
  .light .micro.well.wellpf .mfill { box-shadow: 0 1px 2px rgba(0,0,0,0.18), inset 0 0.5px 0 var(--glass-rim); }

  /* ---------- style matrix ---------- */
  .matrix { display: grid; grid-template-columns: 128px repeat(4, 1fr); gap: 6px; }
  .mx-head { font-size: 11.5px; font-weight: 600; color: var(--text-secondary); text-align: center; align-self: end; padding-bottom: 4px; }
  .mx-form { font-size: 12.5px; font-weight: 600; color: var(--text-primary); display: flex; flex-direction: column; justify-content: center; padding-left: 6px; }
  .mx-form span { font-size: 10.5px; font-weight: 500; color: var(--text-tertiary); }
  .cell { background: var(--cell-bg); border-radius: 10px; box-shadow: inset 0 0 0 1px var(--cell-ring); display: flex; gap: 14px; align-items: center; justify-content: center; min-height: 48px; position: relative; padding: 10px 8px; }
  .warnmark { position: absolute; top: 5px; right: 7px; font-size: 7px; color: var(--sev-l); }
  .matrix-notes { font-size: 12px; color: var(--text-tertiary); margin-top: 14px; max-width: 720px; }
  .matrix-notes strong { color: var(--text-secondary); font-weight: 600; }

  /* light panel wrapper — a light island on the dark page */
  .light-panel { background: linear-gradient(180deg, #f6f7f9, #eceef2); border-radius: 16px; padding: 24px; box-shadow: 0 10px 30px rgba(0,0,0,0.35); }
  .light-panel .cell { box-shadow: inset 0 0 0 1px var(--cell-ring), 0 1px 3px rgba(0,0,0,0.04); background: #fff; }

  /* ---------- settings-picker mock ---------- */
  .settings-mock { width: 344px; max-width: 100%; background: linear-gradient(180deg, var(--tile-top), var(--tile-bottom)); box-shadow: inset 0 0 0 1px var(--ring), 0 6px 18px rgba(0,0,0,0.38); border-radius: 10px; padding: 15px 14px; display: flex; flex-direction: column; gap: 12px; }
  .sm-title { font-size: 13px; font-weight: 600; }
  .sm-row { display: flex; align-items: center; gap: 10px; }
  .sm-label { font-size: 12px; color: var(--text-secondary); width: 42px; flex-shrink: 0; }
  .sm-swatches { display: flex; gap: 6px; flex-wrap: wrap; }
  .swatch { height: 28px; min-width: 46px; padding: 0 9px; border-radius: 7px; background: rgba(255,255,255,0.05); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.06); display: inline-flex; align-items: center; justify-content: center; gap: 6px; }
  .swatch.sel { box-shadow: inset 0 0 0 1.5px rgba(150,161,255,0.75); background: rgba(150,161,255,0.08); }
  .sm-foot { font-size: 10.5px; color: var(--text-tertiary); }

  /* ---------- full-scale popover ---------- */
  .shots2 { display: grid; grid-template-columns: 1fr 1fr; gap: 24px; align-items: start; }
  .shots2 > * { min-width: 0; }
  .pop-wrap { display: flex; flex-direction: column; gap: 12px; }
  .pop-wrap figcaption { font-size: 12px; color: rgba(235,235,245,0.56); padding: 0 6px; }
  .popover-full { width: 388px; max-width: 100%; margin: 0 auto; background: var(--popover-bg); border-radius: 18px; padding: 22px; box-shadow: inset 0 0 0 1px rgba(255,255,255,0.05), 0 24px 60px rgba(0,0,0,0.5); display: flex; flex-direction: column; gap: 14px; color: var(--text-primary); }
  .light .popover-full { background: linear-gradient(180deg, #f6f7f9, #eceef2); box-shadow: inset 0 0 0 1px rgba(0,0,0,0.05), 0 24px 60px rgba(0,0,0,0.30); }
  .pop-head { display: flex; align-items: center; padding: 2px 2px 4px; }
  .pop-title { font-size: 22px; font-weight: 700; letter-spacing: -0.3px; }
  .pop-updated { margin-left: auto; font-size: 12px; color: var(--text-tertiary); }
  .pop-gear { margin-left: 12px; color: var(--text-secondary); font-size: 15px; }
  .pop-foot { display: flex; justify-content: space-between; padding: 4px 2px 0; }
  .pop-foot span { font-size: 13px; font-weight: 600; color: var(--text-secondary); }
  .pop-card { width: 100%; }
  .acct-block { display: flex; flex-direction: column; gap: 9px; }
  .chunk-gap { height: 14px; }

  .verdict { margin-top: 40px; margin-bottom: 32px; padding: 30px; border-radius: 18px; background: linear-gradient(180deg, var(--tile-top), var(--tile-bottom)); box-shadow: inset 0 0 0 1px var(--ring), 0 10px 30px rgba(0,0,0,0.35); }
  .verdict h2 { font-size: 24px; margin-bottom: 8px; }
  .verdict > p { max-width: 760px; }
  .verdict p, .verdict li, .lineage-table { font-size: 13.5px; color: var(--text-secondary); }
  .landed-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 12px; margin-top: 22px; }
  .landed-group { padding: 18px; border-radius: 12px; background: rgba(255,255,255,0.025); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.045); }
  .landed-group h3 { font-size: 14px; margin-bottom: 8px; }
  .landed-group strong { color: var(--text-primary); }
  .landed-group ul { padding-left: 17px; display: flex; flex-direction: column; gap: 5px; }
  .full-width-callout { margin-top: 20px; padding: 20px; border-radius: 14px; background: rgba(150,161,255,0.055); box-shadow: inset 0 0 0 1px rgba(150,161,255,0.16); }
  .full-width-callout h3 { font-size: 16px; margin-bottom: 6px; }
  .full-width-callout > p { max-width: 820px; }
  .lineage-wrap { overflow-x: auto; margin-top: 16px; }
  .lineage-table { width: 100%; min-width: 700px; border-collapse: collapse; }
  .lineage-table th { color: var(--text-primary); font-size: 11px; text-transform: uppercase; letter-spacing: 0.7px; text-align: left; padding: 8px 10px; border-bottom: 1px solid rgba(255,255,255,0.09); }
  .lineage-table td { padding: 9px 10px; border-bottom: 1px solid rgba(255,255,255,0.055); vertical-align: top; }
  .lineage-table tr:last-child td { border-bottom: 0; }
  .lineage-table strong { color: var(--text-primary); }
  .next-test { margin-top: 14px; padding-top: 14px; border-top: 1px solid rgba(255,255,255,0.08); }

  /* ---------- K × T density proof ---------- */
  .expanded-proof { margin-top: 44px; }
  .proof-note { max-width: 820px; margin-top: 12px; padding: 14px 16px; border-left: 2px solid var(--codex-accent); background: rgba(150,161,255,0.045); border-radius: 0 10px 10px 0; }
  .proof-note strong { color: var(--text-primary); }
  .theme-proof { margin-top: 26px; }
  .theme-proof > h3 { font-size: 15px; margin-bottom: 10px; }
  .theme-proof.light { padding: 22px; border-radius: 18px; background: linear-gradient(180deg, #f6f7f9, #eceef2); box-shadow: 0 10px 30px rgba(0,0,0,0.35); color: var(--text-primary); }
  .density-scroller { overflow-x: auto; padding: 1px 1px 12px; }
  .density-board { min-width: 940px; display: flex; flex-direction: column; gap: 14px; }
  .density-head, .density-row { display: grid; grid-template-columns: 74px repeat(2, minmax(0, 1fr)); gap: 18px; align-items: start; }
  .density-head { align-items: end; }
  .density-column-title { padding: 0 4px; }
  .density-column-title strong { display: block; font-size: 13px; color: var(--text-primary); }
  .density-column-title span { display: block; font-size: 11px; color: var(--text-tertiary); margin-top: 2px; }
  .density-count { position: sticky; left: 0; z-index: 4; min-height: 56px; padding: 10px 8px; border-radius: 10px; background: var(--page-bg); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.055); display: flex; flex-direction: column; align-items: center; justify-content: center; }
  .light .density-count { background: #fff; box-shadow: inset 0 0 0 1px rgba(0,0,0,0.06); }
  .density-count strong { font-size: 20px; line-height: 1; }
  .density-count span { font-size: 10px; color: var(--text-tertiary); margin-top: 4px; }
  .density-cell { min-width: 0; padding: 14px; border-radius: 16px; background: rgba(255,255,255,0.018); box-shadow: inset 0 0 0 1px rgba(255,255,255,0.04); }
  .light .density-cell { background: rgba(255,255,255,0.55); box-shadow: inset 0 0 0 1px rgba(0,0,0,0.045); }
  .density-pop-card .prov-head { margin-bottom: 12px; }
  .density-pop-card .acct-block + .acct-block { margin-top: 13px; padding-top: 13px; border-top: 1px solid var(--ring); }
  .density-meters { display: flex; flex-direction: column; gap: 9px; }
  .density-popover[data-layout="expanded"] .density-meters { gap: 12px; }
  .density-popover[data-account-count="5"] { box-shadow: inset 0 0 0 1px rgba(255,255,255,0.05), 0 18px 42px rgba(0,0,0,0.42); }
  .proof-read { margin-top: 12px; font-size: 12.5px; color: var(--text-secondary); max-width: 840px; }
  .proof-read strong { color: var(--text-primary); }

  /* Keep the review document usable at narrow widths. This comes after every grid's
     base declaration so the cascade cannot accidentally restore a two-column layout. */
  @media (max-width: 900px) {
    .grid, .quotes, .decisions, .shots2, .landed-grid { grid-template-columns: 1fr; }
  }
  @media (max-width: 640px) {
    .matrix { grid-template-columns: 104px repeat(4, 92px); overflow-x: auto; padding-bottom: 6px; }
  }
'''

html = f'''<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Headroom · Meter style — round 4</title>
<style>{CSS}</style>
<body>
<div class="page">

  <header class="masthead">
    <div class="eyebrow">Headroom · design feedback · round 4 · rev 5 · Aug 2026</div>
    <h1>Meter style, opened up</h1>
    <p class="lede">Round 3 swept the micro-gauge’s variables and the reaction wasn’t "pick one" — it was <strong style="color:var(--text-primary)">"I sort of like all of these."</strong> So this round reframes shape and fill as a user preference and tests whether the combinations hold together. Rev 3 settled the visual frame; rev 4 turned it into a decision record and drew a boundary around the original full-width gauges. Rev 5 renders that boundary: one expanded-layout candidate, tested against the micro default instead of reopening the entire matrix.</p>
  </header>

  <div class="quotes">
    <div class="quote">
      <div class="who">The turn · Kyle, Aug 28</div>
      <p>"What I’m starting to think is that I sort of like all these options — <em>I want to give users the ability to choose</em> any one of these for the display of their meter. You pick your shape of the meter, and then your color preference. That might be cool."</p>
    </div>
    <div class="quote">
      <div class="who">The rev-3 review · Kyle, Aug 28</div>
      <p>"I can’t really tell if I like the proud fill or not — <em>I’m leaning against it.</em> Labels at 90%. Countdown alone, D2 brightness. The weekly label and the 3d 23h next to it don’t look center-aligned. And light mode <em>just falls a little flat</em> — we need another audit of those colors."</p>
    </div>
  </div>
  <p class="transcript-note">Both paraphrased from Kyle’s voice notes; the Ridd tactility quote behind the proud-fill thread is verbatim in round 1 ("the line had a shadow to it and was slightly bigger than the actual bar container", 01:13–01:24).</p>

  <!-- ============ WHAT THIS ROUND SETTLES ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker" style="color:var(--text-tertiary)">Locked before we start</div>
      <h2>Where the axes stand</h2>
      <p>Kyle’s calls across both passes, folded into the frame. Everything below inherits these.</p>
    </div>
    <div class="decisions">
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>Gauge before the numeral.</strong> The right-edge reading cluster stays; the position axis is closed.</p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>"Left" vs "used" stays a user setting.</strong> Already shipped as a preference.</p></div>
      <div class="decision"><span class="d-mark d-new">NEW</span><p><strong>Shape and color become preferences.</strong> Four shapes and four color recipes survive; arc and ring park until their flagged columns have answers.</p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>The hue ramp stays in the running.</strong> Rev 1 tried to retire it; overruled — it rides with the shapes that can carry it, including a stepped version for ticks.</p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>Labels at 90%. Countdown alone.</strong> Both confirmed in rev 3; the structure is settled.</p></div>
      <div class="decision"><span class="d-mark d-kill">KILL</span><p><strong>Reset-line icons.</strong> One glyph reads fine; a column of repeated ones is noise. The countdown stands alone, dimmed a step.</p></div>
      <div class="decision"><span class="d-mark d-kill">KILL</span><p><strong>The proud fill</strong> — recommended cut, parked not deleted. Kyle leans against; the argument below concurs. Depth stays available through the machined shape.</p></div>
      <div class="decision"><span class="d-mark d-fix">FIX</span><p><strong>Baseline alignment.</strong> The label and its countdown were vertically centered as mixed font sizes, floating the countdown high. Text clusters now align on their baselines.</p></div>
      <div class="decision"><span class="d-mark d-fix">FIX</span><p><strong>Light-mode fills re-derived.</strong> The rev-2 translation read flat and disabled; an OKLCH audit found why and rebuilt the fills. Full before/after in the light section.</p></div>
      <div class="decision"><span class="d-mark d-keep">KEEP</span><p><strong>D2 ships at 53% dark / 72% light.</strong> The scheme-specific correction preserves the quieter hierarchy and clears 4.5:1 at 11px: 4.63:1 and 4.62:1 worst-case.</p></div>
      <div class="decision"><span class="d-mark d-defer">DEFER</span><p><strong>Multi-account density.</strong> Same-provider stacks get their own round once the meter is solid. Next.</p></div>
    </div>
  </section>

  <!-- ============ THE STYLE MATRIX ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-style">The matrix</div>
      <h2>Every shape × every color</h2>
      <p>If style is a preference, the system has to survive its worst combination, not just its best. Four shapes against four color recipes — each cell shows a healthy 72% and a low 38% so the "color as event" column can show its flip. The ticks × ramp cell is new in rev 2: quanta can’t carry a continuous gradient, but they can <em>step</em> it — each lit tick mixes further toward the severity color, the reading-edge tick at full strength.</p>
    </div>
    {matrix()}
    <p class="matrix-notes"><strong>Rev-2 changes:</strong> arc and ring are parked out of the matrix (a severity cap becomes a floating dot at an angle; a gradient can’t follow their path), which clears every ▲ but one — the stepped tick ramp is flagged as an experiment, not a proven cell. It reads as a real ramp at 72% (four steps) but collapses to a single solid tick at 12%, where it’s indistinguishable from plain solid. That might be fine — at critical, subtlety has done its job — or it might argue the ramp is a chip/tube-only recipe.</p>
  </section>

  <!-- ============ THE PICKER ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-style">The setting</div>
      <h2>How the preference surfaces</h2>
      <p>Two independent pickers, not one long list of combos — shape and color compose, and the swatches are live previews built from the real meter components, so the setting is honest about what you’ll get.</p>
    </div>
    <div class="grid">
{option('S1', 'Shape + color pickers', 'A Meter style tile in Settings → Appearance', settings_mock(), 'Shape swatches render at 62% healthy in each form’s own geometry; color swatches render a healthy + low pair, because a single value can’t tell "solid" and "color as event" apart — the pair shows each recipe’s behavior, not just its pigment. Selection ring is the accent.', tag='mine')}
      <div class="option reference">
        <div class="option-head">
          <span class="option-letter">·</span>
          <div><div class="option-title">The cost of choice</div><div class="option-sub">What customization commits us to</div></div>
        </div>
        <p class="option-note" style="font-size:13px; color:var(--text-secondary)">Every shipped combo has to hold up in both schemes, in the widgets, at three severities, and through the freshness states (stale, unavailable) — the matrix above appears twice in this document for exactly that reason. The rev-2 launch set is <strong style="color:var(--text-primary)">four shapes (chip, machined, ticks, tube) × four colors (solid, glass + cap, color as event, hue ramp)</strong> — sixteen combos, fifteen clean and one flagged (ticks × ramp) that ships only if the stepped version proves out. Arc and ring stay parked, not deleted. A default still has to be chosen for first-run: chip + color-as-event, per the round-3 verdict.</p>
      </div>
    </div>
  </section>

  <!-- ============ TACTILITY, DIALED ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-tact">Tactility, the verdict</div>
      <h2>The proud fill: recommend cutting it</h2>
      <p>Kyle leans against; this doc agrees, for a structural reason rather than a taste one. Ridd’s ask was born in round 1 <em>on the full-width bar</em>, where a proud fill has room to read as an object. Shrunk to a 32pt chip there is no good dose: at 1.5pt of overhang the shadows accumulate into texture, at 1pt the effect is nearly subliminal — machinery without a payoff. It also taxes every other axis: each of the four shapes needs its own proud answer, light mode amplifies the cast shadows, and the style matrix doubles its render states. The tactility Ridd wanted survives where it’s structural, not decorative: the machined well already delivers "you could touch it" through its recessed channel, with zero shadows on the fill. Flat fills everywhere else. The three variants stay below as the record — and the way back in, if the flat build feels sterile on the live surface.</p>
    </div>
    <div class="grid">
{option('·', 'Flat — the recommendation', 'No overhang, no shadow; depth belongs to the shape, not the fill', card('chip', 'event', extra_cls='lb90', reset_mode='dim1'), 'What ships: the chip stays a flat instrument and the row stays quiet. A user who wants physicality picks the machined shape — tactility becomes a facet of the shape preference instead of a fifth global variable.', tag='mine', ref=True)}
{option('T4', 'Dialed proud fill', '1pt overhang, softened shadow — the best case for the concept', card('chip', 'event', extra_cls='lb90', reset_mode='dim1', dose='pf'), 'The strongest version rev 2 found, kept for the record. Squint: the difference from flat is one hairline of shadow — which is exactly the argument that it isn’t earning its complexity.')}
{option('T5', 'Rev-1 dose', '1.5pt overhang, full shadow — the version that felt like too much', card('chip', 'event', extra_cls='lb90', reset_mode='dim1', dose='pf1'), 'The overdose that started the doubt: three shadowed rows per card accumulate into texture. Kept so the range of the dial stays visible.')}
{option('T6', 'Overfilled well', 'The machined channel with the fill just over its rim', card('well', 'solid', extra_cls='lb90', reset_mode='dim1', dose='wellpf'), 'The one variant with a future: if any proud fill returns, it’s this one — the recess and the overfill are the same material story. But the flat machined well below in the popovers already carries most of this depth for free.')}
    </div>
  </section>

  <!-- ============ READABILITY ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-read">Readability</div>
      <h2>Labels at 90%</h2>
      <p>Ridd asked for brighter labels in the round-3 video; rev 1 proposed 84%; Kyle’s call is 90%. All four steps shown so the choice stays judgeable — the numeral must remain the brightest text in the row, which is the argument that killed 100%.</p>
    </div>
    <div class="grid">
{option('·', '66% — the current value', 'text-secondary, as shipped and as mocked in rounds 2–3', card('chip', 'event', reset_mode='dim1'), 'The reference. Legible up close, but the window names are the row’s subject and they sit two levels below the numeral.', ref=True)}
{option('B1', '84% — rev 1’s proposal', 'One level up; maximum daylight between label and numeral', card('chip', 'event', extra_cls='lb84', reset_mode='dim1'), 'Clearly brighter than the reset line, clearly quieter than the numeral. The conservative reading of "should be white."')}
{option('B2', '90% — the pick', 'Kyle’s call — bright enough to read as white in practice', card('chip', 'event', extra_cls='lb90', reset_mode='dim1'), 'The rest of this document uses this. At 90% the label reads as white without ever competing with the 18pt numeral at 95%+ — the hierarchy survives on size and the remaining half-step. This is the value to carry into the build.', tag='Kyle’s pick')}
{option('B3', '100% — full white', 'Labels at text-primary, same ink as the numeral', card('chip', 'event', extra_cls='lb100', reset_mode='dim1'), 'The literal reading. Maximum legibility, but the label and the numeral now compete at the same brightness and the row loses its reading order — the numeral only wins by size.')}
    </div>
  </section>

  <!-- ============ THE RESET LINE ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker k-reset">The reset line</div>
      <h2>The countdown stands alone</h2>
      <p>Rev 1 proposed replacing "Resets in" with a glyph; seeing the ↻ repeated down a column of rows killed it — one icon is information, five in a stack are noise. Rev 2 narrowed the direction to a bare, dimmed countdown; rev 3 picked D2 visually because it recedes behind the newly brightened labels without becoming merely discoverable. Rev 4 resolves the token itself: 53% in dark mode and 72% in light mode, each slightly quieter than D1 while clearing 4.5:1 at 11px.</p>
    </div>
    <div class="grid">
{option('·', '"· Resets in 3h 11m"', 'The current line — full prose at 56%', card('chip', 'event', extra_cls='lb90'), 'The reference. Unambiguous, but next to a 90% label the sentence now costs more width than the information is worth.', ref=True)}
{option('D1', 'Bare, as-is brightness', 'Countdown alone at the current 56% tertiary', card('chip', 'event', extra_cls='lb90', reset_mode='bare'), 'Drop the prose, change nothing else. Densest possible row — but at the same brightness as the "left" unit, the naked duration invites reading as part of the value cluster rather than as metadata.')}
{option('D2', 'Bare, dimmed one step', '53% dark / 72% light — the accessible pick', card('chip', 'event', extra_cls='lb90', reset_mode='dim1'), 'The dim-down does the disambiguating that the word used to: the countdown reads as quiet metadata orbiting the label, not a second value. The resolved scheme-specific values measure 4.63–4.96:1 in dark mode and 4.62–4.70:1 in light, clearing the 4.5:1 floor at 11px while staying one visible step below D1. First-run ambiguity ("is 3d 23h the window length or the time left?") remains small, with the full sentence retained in the tooltip.', tag='Kyle’s pick')}
{option('D3', 'Bare, dimmed two steps', 'Countdown alone at 40% — the bracket', card('chip', 'event', extra_cls='lb90', reset_mode='dim2'), 'The far end of the dial, included to bracket D2. At 40% the countdown is discoverable rather than readable — probably past the point, since reset timing is the second most-checked fact on the surface.')}
    </div>
  </section>

  <!-- ============ REAL SCALE ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker" style="color:var(--codex-accent)">The proof</div>
      <h2>At real scale, twice</h2>
      <p>Same degraded day, same data, the resolved frame applied (90% labels, bare countdown at the accessible D2 dose, baseline-aligned text clusters). Left is the recommended flat default; right is a user who picked the machined shape with the glass-cap recipe.</p>
    </div>
    <div class="shots2">
      <figure class="pop-wrap">
        {popover('chip', 'event')}
        <figcaption>Default style: chip + color-as-event, flat per the tactility verdict. The reset column is now the quietest thing on the surface and the labels the clearest — the inversion Ridd’s "label text should be white" note was pointing at.</figcaption>
      </figure>
      <figure class="pop-wrap">
        {popover('well', 'cap')}
        <figcaption>A customized style: machined well + glass fill with severity caps. Different material story, identical information hierarchy — the bar every shipped combo has to clear.</figcaption>
      </figure>
    </div>
  </section>

  <!-- ============ LIGHT MODE ============ -->
  <section>
    <div class="section-head">
      <div class="section-kicker" style="color:var(--sev-h)">The other scheme</div>
      <h2>Light mode, audited</h2>
      <p>Rev 2’s light translation used the app’s existing light tokens verbatim and fell flat — everything read gray, brown, and vaguely disabled. An OKLCH audit found three causes, none of them "the colors are too dark": <strong style="color:var(--text-primary)">the fills kept their dark-mode 85% alpha</strong>, so they composited toward the gray track and drained the chroma (the amber was landing at a muddy #c17c3a); <strong style="color:var(--text-primary)">"glass" was plain black-alpha</strong> — a gray fill on a gray track at the same hue is the exact recipe of a disabled slider; and <strong style="color:var(--text-primary)">amber can’t stay amber that dark</strong> — at the lightness the 3:1 track contrast demands, hue 67° has lost a third of its chroma, so it drifts 8.7° toward orange (inside the 10° drift threshold) where the gamut is wider. The rebuilt fills hold every hue from the dark tokens, sit at their maximum lightness that still clears 3:1 vs the track, and render opaque; glass becomes a cool steel gradient. These are a proposal for a light <em>fill</em> token set in <code>BrandColorValues.swift</code> — the 4.5:1 text tokens are untouched.</p>
    </div>
    <div class="grid" style="margin-bottom: 24px;">
{option('·', 'Rev 2 — before', 'The verbatim token translation: alpha fills, black-alpha glass', '<div class="light oldlight">' + card('chip', 'event', extra_cls='lb90', reset_mode='dim1') + '</div>', 'The flat version: healthy reads as a disabled slider, the amber composites to mud, and nothing on the card says "instrument."', ref=True)}
{option('L1', 'Rev 3 — after', 'Audited fills: opaque, chroma-restored, steel glass', '<div class="light">' + card('chip', 'event', extra_cls='lb90', reset_mode='dim1') + '</div>', 'Same rows, same geometry. Healthy’s steel fill now reads as material with intent, the amber is amber again (#bb6a1d), and the critical red has its urgency back (#f42a24). All three fills measure 3.06–3.07:1 against the track — compliance didn’t move, only the life did.', tag='mine')}
    </div>
    <div class="light light-panel" style="margin-bottom: 24px;">
    {matrix()}
    </div>
    <div class="shots2">
      <figure class="pop-wrap">
        <div class="light">{popover('chip', 'event')}</div>
        <figcaption>Light default: chip + color-as-event, flat, audited fills. Healthy rows are quiet steel rather than empty gray — present, not disabled.</figcaption>
      </figure>
      <figure class="pop-wrap">
        <div class="light">{popover('well', 'cap')}</div>
        <figcaption>Light customized: the machined well stays a pressed groove in the white tile; the glass fill is now steel instead of smoke. The severity caps wear the audited hues.</figcaption>
      </figure>
    </div>
  </section>

  <!-- ============ CONSOLIDATED DECISION RECORD ============ -->
  <section class="verdict">
    <div class="section-kicker" style="color:var(--codex-accent)">Decision record</div>
    <h2>Landed choices</h2>
    <p>This is the build-facing summary. Earlier sections keep the rejected variants and reasoning; this section is the one place to read what actually survived.</p>

    <div class="landed-grid">
      <article class="landed-group">
        <h3>Frame and hierarchy</h3>
        <ul>
          <li><strong>Gauge before the numeral</strong> in the right-edge reading cluster.</li>
          <li><strong>Window labels at 90%</strong>; the numeral remains primary through size and weight.</li>
          <li><strong>Bare countdown at D2:</strong> 53% dark / 72% light, measuring 4.63:1 / 4.62:1 worst-case at 11px.</li>
          <li>Label + countdown and numeral + unit are <strong>baseline-aligned clusters</strong>.</li>
          <li>The tooltip retains the full “Resets in …” sentence for cold-read ambiguity.</li>
        </ul>
      </article>

      <article class="landed-group">
        <h3>Meter system</h3>
        <ul>
          <li><strong>Default:</strong> chip + color-as-event.</li>
          <li><strong>Shape choices:</strong> chip, machined, ticks, tube.</li>
          <li><strong>Color choices:</strong> solid, glass + cap, color-as-event, hue ramp.</li>
          <li>Shape and color remain <strong>independent preferences</strong>; “left” vs “used” remains separate.</li>
          <li>Widgets follow the selected meter language only after each combination proves out there.</li>
        </ul>
      </article>

      <article class="landed-group">
        <h3>Material and color</h3>
        <ul>
          <li><strong>Flat fills ship.</strong> Proud/overfilled treatments stay in the record, not the recommendation.</li>
          <li>The machined shape carries tactility structurally through its recessed well.</li>
          <li>Light fills are scheme-specific and opaque; “glass” becomes cool steel rather than black-alpha gray.</li>
          <li>Every recipe preserves the green → amber → red severity ramp in both schemes.</li>
        </ul>
      </article>

      <article class="landed-group">
        <h3>Parked and gated</h3>
        <ul>
          <li><strong>Ticks × ramp</strong> remains an experiment; gate it on the low-percentage collapse.</li>
          <li><strong>Arc and ring</strong> stay parked until cap and path-gradient behavior have clean answers.</li>
          <li><strong>Multi-account density</strong> remains the next proof: same-provider stacks and the 640pt cap.</li>
          <li>Build the frame first, then the flat default, then expose the picker once at least two styles are real.</li>
        </ul>
      </article>
    </div>

    <div class="full-width-callout">
      <div class="section-kicker" style="color:var(--sev-l)">Recommendation · still open</div>
      <h3>Don’t bring back a full-width copy of every micro gauge</h3>
      <p>The old full gauges are the ancestors of this matrix, but restoring all of them would duplicate the system on the wrong axis. Full width changes row height, scanning behavior, and multi-account density; that makes it an <strong style="color:var(--text-primary)">expanded layout</strong>, not a fifth shape. The one candidate worth a fair return is the <strong style="color:var(--text-primary)">full-width recessed instrument + color-as-event</strong>: K’s continuous length read with T’s quiet healthy state.</p>

      <div class="lineage-wrap">
        <table class="lineage-table">
          <thead><tr><th>Micro family</th><th>Full-width ancestor</th><th>Recommendation</th></tr></thead>
          <tbody>
            <tr><td><strong>Solid</strong></td><td>Today / V · lit tube, full color</td><td>Do not restore; the color mass competes with the numeral again.</td></tr>
            <tr><td><strong>Glass + cap</strong></td><td>I / S · ghost or grey-glass fill, bright cap</td><td>Keep as a fill recipe; full width adds footprint without a new reading advantage.</td></tr>
            <tr><td><strong>Color as event</strong></td><td>B / T · healthy neutral, amber/red interrupt</td><td>Use inside the single expanded candidate; it is the calmest full-width behavior.</td></tr>
            <tr><td><strong>Hue ramp</strong></td><td>H / W · hue travel</td><td>Keep micro for now; full width restores too much ambient color.</td></tr>
            <tr><td><strong>Ticks</strong></td><td>J · segmented meter</td><td>Keep micro; at full width it reads like dashboard telemetry.</td></tr>
            <tr><td><strong>Machined</strong></td><td>K · recessed instrument</td><td><strong>Test this one.</strong> It uniquely regains continuous length-at-a-glance and makes depth earn its space.</td></tr>
          </tbody>
        </table>
      </div>

      <p class="next-test"><strong style="color:var(--text-primary)">Fair test:</strong> compare the current micro default against K × T at one, two, and five accounts in both schemes. That comparison is rendered immediately below. If the full-width version cannot justify its height at five accounts, keep it out of the preference model rather than adding a density toggle nobody asked for.</p>
    </div>
  </section>

  <!-- ============ THE SINGLE FULL-WIDTH RETURN ============ -->
  <section class="expanded-proof">
    <div class="section-head">
      <div class="section-kicker" style="color:var(--sev-l)">Open proof · expanded layout</div>
      <h2>K × T gets one fair return</h2>
      <p>This is not a fifth meter shape. It is a denser-versus-more-spatial layout choice: the current <strong style="color:var(--text-primary)">micro chip + color-as-event</strong> against an <strong style="color:var(--text-primary)">8px recessed instrument + color-as-event</strong>. The expanded version keeps K’s continuous length read and quarter marks, but uses T’s loudness rule: healthy is neutral material; amber and red interrupt only when the state earns it.</p>
      <p class="proof-note"><strong>Read the five-account row first.</strong> One account will flatter almost any meter. Five accounts reveals whether the full-width read is genuinely faster or whether the added vertical rhythm turns the popover into telemetry.</p>
    </div>

    {density_theme_panel('Dark scheme', '', '<strong>Dark read:</strong> the full-width version earns a cleaner spatial comparison between windows, but the cost compounds account by account. The decision is whether that faster length read is worth turning every window into a separate horizontal band.')}

    {density_theme_panel('Light scheme', ' light', '<strong>Light read:</strong> the recessed channel remains legible without becoming a dark trough. Healthy stays cool steel, while the audited amber and red fills retain the same event hierarchy as the micro default.')}
  </section>

  <footer style="color:var(--text-tertiary); font-size:12px;">
    Round 4 · rev 5 of the Ridd feedback series · consolidated from Kyle’s Aug 28 reviews and the rev-3 audit · dark mockups use the real scheme tokens from <code>BrandColorValues.swift</code>; audited light fills are proposed replacements · K × T expanded proof descends from the original recessed-instrument and color-as-event studies in <code>ridd-feedback-explorations.html</code> · previous micro round: <code>ridd-micro-gauge-explorations.html</code>
  </footer>
</div>
</body>
</html>
'''

open(OUT, 'w').write(html)
print('wrote', OUT, len(html), 'bytes')
