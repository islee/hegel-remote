"""Build the icon-study HTML page with the rendered PNGs embedded as data URIs."""

import base64
import json
import sys
from pathlib import Path

OUT = Path(sys.argv[1])
PAGE = Path(sys.argv[2])

# id, name, idea, scores: legibility, fit, distinct, meaning, simplicity
OPTIONS = [
    ("i01_silver_dial", "Silver Dial", "Current icon. Silver ring, black readout, dot-matrix volume arc, amber centre.", [4, 5, 4, 4, 4]),
    ("i02_black_dial", "Black Dial", "Same dial in the black finish; amber arc instead of white.", [3, 5, 3, 4, 4]),
    ("i03_oled_digits", "OLED Digits", "Just the readout: a big dot-matrix volume number.", [4, 4, 3, 2, 4]),
    ("i04_front_panel", "Front Panel", "A slice of the amp front: display strip over one knob.", [2, 5, 3, 4, 2]),
    ("i05_click_wheel", "Click Wheel", "White wheel with − and +, readout in the centre button.", [4, 3, 4, 4, 4]),
    ("i06_knob_indicator", "Knob", "One silver volume knob seen from above, with its indicator line.", [5, 4, 3, 5, 5]),
    ("i07_level_bars", "Level Bars", "Dot-matrix level meter rising left to right, amber peak.", [4, 3, 3, 4, 4]),
    ("i08_power_matrix", "Power", "The power symbol drawn in amber dots.", [5, 3, 3, 3, 5]),
    ("i09_wave_ring", "Wave Ring", "Dot-matrix waveform inside the silver ring.", [2, 3, 3, 3, 2]),
    ("i10_monogram", "Monogram", "Dot-matrix 'hr' on a black plate with an amber pixel.", [3, 3, 3, 2, 4]),
    ("i11_cone", "Cone", "Concentric rings, like a speaker cone or a knob from above.", [4, 2, 4, 3, 4]),
    ("i12_arc_gauge", "Arc Gauge", "Flat amber volume arc on black with a white hub.", [5, 3, 3, 4, 5]),
    ("i13_split", "Split Knob", "Half silver, half black knob: both H590 finishes in one.", [4, 4, 4, 3, 4]),
    ("i14_dot_grid", "Dot Grid", "5×5 dot field filling up to an amber level marker.", [4, 3, 3, 3, 4]),
]
CRITERIA = [
    ("Small-size legibility", 25, "Still reads at 32 px (Spotlight, Mac Dock, Settings)"),
    ("Design-language fit", 25, "Matches the app and the amp: matte black/silver, dot-matrix readout, dial"),
    ("Distinctive", 20, "Stands out on a home screen next to other audio apps"),
    ("Says what it does", 15, "Reads as volume / amplifier control without a label"),
    ("Simplicity", 15, "One idea, few elements, ages well"),
]


def uri(path: Path) -> str:
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode()


cards = []
for i, (key, name, idea, _) in enumerate(OPTIONS, 1):
    cards.append(f"""
  <article class="card" id="o{i}">
    <div class="big"><img src="{uri(OUT / f'{key}-180.png')}" width="180" height="180" alt="{name} icon at 180 px"></div>
    <div class="small">
      <img src="{uri(OUT / f'{key}-64.png')}" width="64" height="64" alt="{name} at 64 px">
      <img src="{uri(OUT / f'{key}-32.png')}" width="32" height="32" alt="{name} at 32 px">
      <span class="sizes">64 · 32 px</span>
    </div>
    <h3><span class="num">{i:02d}</span> {name}</h3>
    <p>{idea}</p>
  </article>""")

data = json.dumps({"options": [[o[1], o[3]] for o in OPTIONS], "criteria": [[c[0], c[1]] for c in CRITERIA]})
crit_rows = "".join(f"<tr><td>{c[0]}</td><td>{c[2]}</td></tr>" for c in CRITERIA)

html = f"""<title>hegel-remote Icon Study</title>
<meta name="claude:viewport-fit-sides" content="cover">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Doto:wght@800&family=Manrope:wght@400;600;700&display=swap">
<style>
/* Layout: contact sheet of icon cards on a mid-grey wall (so both dark and light icons read), then a scoring table. */
:root{{--bg:#d9dbdd;--surface:#eef0f1;--fg:#141516;--muted:#4f5459;--line:#bfc3c7;--accent:#a8741f;
  --display:Doto,"Courier New",monospace;--body:Manrope,"Helvetica Neue",Arial,sans-serif}}
@media (prefers-color-scheme: dark){{:root:not([data-theme="light"]){{--bg:#26292c;--surface:#1b1d20;--fg:#e8eaec;--muted:#a3a9ae;--line:#3a3e43;--accent:#d9a441;color-scheme:dark}}}}
:root[data-theme="dark"]{{--bg:#26292c;--surface:#1b1d20;--fg:#e8eaec;--muted:#a3a9ae;--line:#3a3e43;--accent:#d9a441;color-scheme:dark}}
body{{background:var(--bg);color:var(--fg);font-family:var(--body);font-size:16px;line-height:1.5;
  padding-left:max(16px,env(safe-area-inset-left,0px));padding-right:max(16px,env(safe-area-inset-right,0px));padding-block:32px 64px}}
main{{max-width:1180px;margin:0 auto;display:flex;flex-direction:column;gap:36px}}
h1{{font-family:var(--display);font-size:2.4rem;margin:0;letter-spacing:.02em;text-wrap:balance}}
h2{{font-size:1.3rem;margin:0 0 4px;text-wrap:balance}}
h3{{font-size:1rem;margin:0;display:flex;gap:8px;align-items:baseline}}
p{{margin:0;max-width:70ch}}
.lede{{color:var(--muted);font-size:1.05rem}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(230px,1fr));gap:16px}}
.card{{background:var(--surface);border:1px solid var(--line);border-radius:14px;padding:16px;display:flex;flex-direction:column;gap:10px;min-width:0}}
.big img{{display:block;border-radius:40px;max-width:100%;height:auto}}
.small{{display:flex;gap:12px;align-items:center}}
.small img:first-child{{border-radius:14px}} .small img:nth-child(2){{border-radius:7px}}
.sizes{{font-size:.75rem;color:var(--muted)}}
.num{{font-family:var(--display);color:var(--accent)}}
.card p{{font-size:.9rem;color:var(--muted)}}
.scroll{{overflow-x:auto}}
table{{border-collapse:collapse;width:100%;font-size:.92rem}}
th,td{{text-align:left;padding:7px 9px;border-bottom:1px solid var(--line)}}
th{{font-size:.72rem;letter-spacing:.06em;text-transform:uppercase;color:var(--muted)}}
td.n{{text-align:right;font-variant-numeric:tabular-nums}}
input[type=number]{{width:3.4em;font:inherit;background:var(--surface);color:var(--fg);border:1px solid var(--line);border-radius:4px}}
tr.top td{{font-weight:700;color:var(--accent)}}
.verdict{{background:var(--surface);border:1px solid var(--line);border-radius:12px;padding:16px;display:flex;flex-direction:column;gap:8px}}
</style>
<main>
<header style="display:flex;flex-direction:column;gap:8px">
  <h1>Icon Study</h1>
  <p class="lede">Fourteen app icon directions for hegel-remote, each shown large and at the real 64 px and 32 px sizes. None use Hegel's logo or artwork. Pick by number; any of them can be tuned (colours, dot count, finish) before it ships.</p>
</header>
<section class="grid">{''.join(cards)}
</section>
<section style="display:flex;flex-direction:column;gap:12px">
  <h2>Criteria</h2>
  <div class="scroll"><table><thead><tr><th>Criterion</th><th>Test</th></tr></thead><tbody>{crit_rows}</tbody></table></div>
</section>
<section style="display:flex;flex-direction:column;gap:12px">
  <h2>Scoring</h2>
  <p class="lede">My 1–5 scores from the renders above (judgement, not measurement). Edit the weights; the ranking updates.</p>
  <div class="scroll"><table id="score"><thead></thead><tbody></tbody></table></div>
</section>
<section class="verdict">
  <h2>Recommendation</h2>
  <p>With the default weights, <b>06 Knob</b> scores highest (4.35), just ahead of <b>01 Silver Dial</b> (4.25), the icon you have now. I'd still <b>keep 01</b>: the gap is inside the noise of 1–5 judgement scores, and 01 is the only one that repeats the app's own main screen. 01 ties the icon to the app's main screen (the dial and readout) and keeps the amber accent. 06 is the most legible at 32 px and the purest "volume knob", but it says less about this app. Good alternates: 12 Arc Gauge (flat, very legible), 13 Split Knob (both H590 finishes).</p>
  <p>Weak at small sizes: 04 Front Panel and 09 Wave Ring lose their detail at 32 px.</p>
</section>
</main>
<script>
(function(){{
  var D={data};
  var head=document.querySelector("#score thead"), body=document.querySelector("#score tbody");
  var hr="<tr><th>Option</th>"+D.criteria.map(function(c,i){{return "<th class='n'>"+c[0]+"<br><input type='number' min='0' max='60' id='w"+i+"' aria-label='Weight for "+c[0]+"' value='"+c[1]+"'></th>"}}).join("")+"<th class='n'>Total</th></tr>";
  head.innerHTML=hr;
  function calc(){{
    var w=D.criteria.map(function(_,i){{var v=parseFloat(document.getElementById("w"+i).value);return isNaN(v)||v<0?0:v}});
    var sum=w.reduce(function(a,b){{return a+b}},0)||1;
    var rows=D.options.map(function(o,k){{return {{k:k,name:o[0],s:o[1],t:o[1].reduce(function(a,v,i){{return a+v*w[i]}},0)/sum}}}});
    rows.sort(function(a,b){{return b.t-a.t}});
    body.innerHTML=rows.map(function(r,idx){{return "<tr"+(idx<3?" class='top'":"")+"><td>"+String(r.k+1).padStart(2,"0")+" "+r.name+"</td>"+r.s.map(function(v){{return "<td class='n'>"+v+"</td>"}}).join("")+"<td class='n'>"+r.t.toFixed(2)+"</td></tr>"}}).join("");
  }}
  head.addEventListener("input",calc); calc();
}})();
</script>
"""
PAGE.write_text(html)
print(PAGE, PAGE.stat().st_size)
