#!/bin/bash
# Aperture lab: restyle the login screen and remove the stock Pi desktop flash. Run as your normal user: bash fix-login.sh
set -e
[ "$(id -u)" = "0" ] && { echo "Run as your normal user, not sudo."; exit 1; }
mkdir -p ~/.local/bin ~/.local/share/retro-lab
sudo apt-get install -y librsvg2-bin >/dev/null
cat > ~/.local/bin/retro-lab-render <<'PYEOF'
#!/usr/bin/env python3
"""Aperture retro-lab wallpaper renderer. Draws the desktop as an SVG with live stats."""
import os, sys, json, time, socket, subprocess, shutil, datetime
HOME = os.path.expanduser("~")
CFG = HOME + "/.config/retro-lab/config"
CACHE = HOME + "/.cache/retro-lab"
THEMES = {
 "night": dict(bg=["#2a1b14","#3a2518"], panel="rgba(255,225,170,.08)", pstroke="rgba(255,225,170,.18)", text="#f0e0bd", sub="#c9a77a", acc="#e0873a", acc2="#e7c06a", track="rgba(255,225,170,.12)", halo="#d27a35", ho=.5, word="#f0e0bd", glow=60),
 "day":   dict(bg=["#f3e6c6","#ead7ac"], panel="rgba(122,59,20,.07)", pstroke="rgba(122,59,20,.15)", text="#4a2a16", sub="#8a5a38", acc="#d27a35", acc2="#d9a93f", track="rgba(122,59,20,.12)", halo="#e7a947", ho=.5, word="#7a3b14", glow=70),
 "dusk":  dict(bg=["#3d2016","#8a4426","#d98a3e","#ecc275"], panel="rgba(60,25,10,.28)", pstroke="rgba(255,235,200,.22)", text="#fbeed0", sub="#f0d6a4", acc="#fff0cf", acc2="#f2b45a", track="rgba(255,235,200,.2)", halo="#fff0cf", ho=.18, word="#fff6e0", glow=60),
}
def config():
    c = dict(mode="auto", dawn="6", day="8", dusk="17", night="20")
    try:
        for l in open(CFG):
            if "=" in l and not l.startswith("#"):
                k, v = l.strip().split("=", 1); c[k.strip()] = v.strip()
    except OSError: pass
    return c
def pick_theme(c):
    if c["mode"] in THEMES: return c["mode"]
    h = datetime.datetime.now().hour
    dawn, day, dusk, night = (int(c[k]) for k in ("dawn", "day", "dusk", "night"))
    if day <= h < dusk: return "day"
    if dawn <= h < day or dusk <= h < night: return "dusk"
    return "night"
def logo(x, y, r, i="L"):
    return f'''<g transform="translate({x},{y}) scale({r/210})"><defs><clipPath id="c{i}"><circle r="210"/></clipPath><mask id="m{i}"><rect x="-220" y="-220" width="440" height="440" fill="#fff"/><g fill="#000"><rect x="-220" y="-150" width="440" height="14"/><rect x="-220" y="-95" width="440" height="14"/><rect x="-220" y="95" width="440" height="14"/><rect x="-220" y="150" width="440" height="14"/><circle r="62"/><rect x="-220" y="-14" width="440" height="14"/></g></mask><linearGradient id="g{i}" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8a4a22"/><stop offset=".45" stop-color="#d27a35"/><stop offset=".8" stop-color="#e7a947"/><stop offset="1" stop-color="#e3c26a"/></linearGradient></defs><g clip-path="url(#c{i})" mask="url(#m{i})"><rect x="-220" y="-220" width="440" height="440" fill="url(#g{i})"/></g></g>'''
def iris(cx, cy, t):
    import math
    R, r = 56, 20; c = t["acc"]; g = t["bg"][0]
    l = "".join(f'<line x1="{r*math.cos(math.radians(k*60)):.1f}" y1="{r*math.sin(math.radians(k*60)):.1f}" x2="{R*math.cos(math.radians(k*60+62)):.1f}" y2="{R*math.sin(math.radians(k*60+62)):.1f}" stroke="{g}" stroke-width="3.5"/>' for k in range(6))
    return f'<g transform="translate({cx},{cy})"><circle r="{R}" fill="{c}" opacity=".92"/>{l}<circle r="{r}" fill="{g}"/></g>'
def sh(cmd, t=2):
    try: return subprocess.run(cmd, capture_output=True, text=True, timeout=t).stdout.strip()
    except Exception: return ""
def stats():
    os.makedirs(CACHE, exist_ok=True)
    cur = {}
    for l in open("/proc/stat"):
        if l.startswith("cpu"):
            p = l.split(); v = list(map(int, p[1:9])); cur[p[0]] = [sum(v) - v[3] - v[4], sum(v)]
    prev = {}
    try: prev = json.load(open(CACHE + "/stat.json"))
    except Exception: pass
    json.dump(cur, open(CACHE + "/stat.json", "w"))
    def pct(k):
        if k not in prev: return 0
        dt = cur[k][1] - prev[k][1]; return 100 * (cur[k][0] - prev[k][0]) / dt if dt > 0 else 0
    cores = [pct(k) for k in sorted((k for k in cur if k != "cpu"), key=lambda s: int(s[3:]))]
    mi = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
    mem = 100 * (1 - mi["MemAvailable"] / mi["MemTotal"])
    try: temp = int(open("/sys/class/thermal/thermal_zone0/temp").read()) / 1000
    except Exception: temp = 0
    du = shutil.disk_usage("/"); disk = 100 * du.used / du.total
    fan = ""
    for d in os.listdir("/sys/class/hwmon") if os.path.isdir("/sys/class/hwmon") else []:
        try: fan = open(f"/sys/class/hwmon/{d}/fan1_input").read().strip(); break
        except Exception: pass
    ts = sh(["tailscale", "ip", "-4"]).split("\n")[0] or "offline"
    up = float(open("/proc/uptime").read().split()[0]); upS = f"{int(up//86400)}d {int(up%86400//3600)}h" if up > 86400 else f"{int(up//3600)}h {int(up%3600//60)}m"
    return dict(cpu=pct("cpu"), cores=cores, mem=mem, temp=temp, disk=disk, fan=fan, ts=ts, up=upS)
def bar(x, y, w, v, t, col):
    return f'<rect x="{x}" y="{y}" width="{w}" height="12" rx="6" fill="{t["track"]}"/><rect x="{x}" y="{y}" width="{max(12, w*min(v,100)/100):.0f}" height="12" rx="6" fill="{col}"/>'
def svg(tn, widgets=True, W=1920, H=1080, s=None):
    t = THEMES[tn]; host = socket.gethostname()
    stops = "".join(f'<stop offset="{i/(len(t["bg"])-1)}" stop-color="{c}"/>' for i, c in enumerate(t["bg"]))
    out = f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 1920 1080" preserveAspectRatio="xMidYMid slice"><defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient><filter id="sh" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="{t["glow"]}"/></filter></defs>
<rect x="-400" y="-400" width="2720" height="1880" fill="url(#bg)"/>
<circle cx="960" cy="470" r="330" fill="{t["halo"]}" filter="url(#sh)" opacity="{t["ho"]}"/>'''
    F = 'font-family="Gelasio,Georgia,DejaVu Serif,serif"'
    if widgets and s:
        P = lambda x, y, w, h: f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="26" fill="{t["panel"]}" stroke="{t["pstroke"]}" stroke-width="1.5"/>'
        out += P(50,60,600,150) + P(670,60,190,190) + P(1130,50,400,190) + P(1550,50,140,190) + P(1710,50,160,190) + P(1600,770,270,250)
        now = datetime.datetime.now()
        n = max(1, len(s["cores"])); cw = 300 / n
        cb = "".join(f'<rect x="{1160+i*cw+6:.0f}" y="{215-max(10,c*1.4):.0f}" width="{cw-14:.0f}" height="{max(10,c*1.4):.0f}" rx="8" fill="{t["acc"] if i%2 else t["acc2"]}" opacity=".85"/>' for i, c in enumerate(s["cores"]))
        out += f'''<g {F} fill="{t["text"]}">
<g font-size="17" fill="{t["sub"]}" letter-spacing="2"><text x="80" y="100">SYSTEM · {host.upper()}</text><text x="700" y="100">DISK</text><text x="1630" y="810">COOLING</text><text x="1160" y="85">CORES</text></g>
<text x="80" y="145" font-size="21"><tspan fill="{t["acc"] if tn!="dusk" else t["acc2"]}" font-weight="900">Tailscale</tspan>   {s["ts"]}</text><text x="80" y="185" font-size="21" opacity=".85">Uptime   {s["up"]}</text>
<text x="700" y="155" font-size="44" font-weight="900">{s["disk"]:.0f}%</text>{bar(700,180,130,s["disk"],t,t["acc2"])}
<text x="1090" y="105" font-size="56" text-anchor="end" font-weight="900">{now:%H:%M}</text><text x="1090" y="160" font-size="34" text-anchor="end" opacity=".8">{now:%a %d %b}</text>
{cb}
<text x="1568" y="105" font-size="32" >{s["cpu"]:.0f}%</text><text x="1568" y="155" font-size="32">{s["mem"]:.0f}%</text><text x="1568" y="205" font-size="32">{s["temp"]:.0f}°</text>
<g font-size="13" fill="{t["sub"]}" text-anchor="end"><text x="1676" y="105">CPU</text><text x="1676" y="155">MEM</text><text x="1676" y="205">TEMP</text></g>
{iris(1790,145,t)}
<text x="1630" y="890" font-size="58" font-weight="900">{s["fan"] or "—"}<tspan font-size="22"> rpm</tspan></text>{bar(1630,925,200,min(100,(int(s["fan"] or 0))/50),t,t["acc"])}{bar(1630,965,200,s["temp"],t,t["acc2"])}
<text x="70" y="1020" font-size="30" fill="{t["sub"]}" font-style="italic">user · {os.environ.get("USER","user")}</text></g>'''
    out += logo(960, 470, 200)
    out += f'''<g {F}><text x="960" y="835" font-size="120" font-weight="900" text-anchor="middle" fill="{t["word"]}">aperture</text><text x="960" y="895" font-size="34" text-anchor="middle" fill="{t["sub"]}" letter-spacing="26" font-style="italic">LABORATORIES</text></g></svg>'''
    return out
def login_svg(W=1920, H=1080):
    t = THEMES["night"]; F = 'font-family="Gelasio,Georgia,DejaVu Serif,serif"'
    stops = "".join(f'<stop offset="{i/(len(t["bg"])-1)}" stop-color="{c}"/>' for i, c in enumerate(t["bg"]))
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 1920 1080" preserveAspectRatio="xMidYMid slice"><defs><linearGradient id="bg" x1="0" y1="0" x2="0" y2="1">{stops}</linearGradient><filter id="bl" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="70"/></filter></defs>
<rect x="-400" y="-400" width="2720" height="1880" fill="url(#bg)"/><circle cx="960" cy="130" r="260" fill="{t["halo"]}" filter="url(#bl)" opacity=".45"/>
{logo(960, 125, 100)}<g {F}><text x="960" y="320" font-size="84" font-weight="900" text-anchor="middle" fill="{t["word"]}">aperture</text><text x="960" y="363" font-size="24" text-anchor="middle" fill="{t["sub"]}" letter-spacing="18" font-style="italic">LABORATORIES</text></g></svg>'''
def png(svgtext, path, w=None):
    tmp = path + ".svg"; open(tmp, "w").write(svgtext)
    subprocess.run(["rsvg-convert", tmp, "-o", path], check=True); os.remove(tmp)
def screen():
    for f in sorted(__import__("glob").glob("/sys/class/drm/*/modes")):
        try:
            if open(f.replace("modes", "status")).read().strip() == "connected":
                w, h = open(f).readline().strip().split("x"); return int(w), int(h.split("i")[0])
        except Exception: pass
    return 1920, 1080
if __name__ == "__main__":
    c = config()
    if len(sys.argv) > 1 and sys.argv[1] == "static":   # login screen + boot logo (run during install)
        out = sys.argv[2]; os.makedirs(out, exist_ok=True)
        png(svg("night", False), out + "/wall.png")
        png(login_svg(), out + "/login.png")
        png(f'<svg xmlns="http://www.w3.org/2000/svg" width="420" height="420" viewBox="-210 -210 420 420">{logo(0,0,210,"P")}</svg>', out + "/logo.png")
        steps = [-150, -81, 0, 109, 164, 210]
        for k in range(7):   # logo revealed stripe by stripe, for the boot splash
            y = -220 if k == 0 else steps[k - 1]
            png(f'<svg xmlns="http://www.w3.org/2000/svg" width="420" height="420" viewBox="-210 -210 420 420"><clipPath id="rv"><rect x="-220" y="-220" width="440" height="{y+220}"/></clipPath><g clip-path="url(#rv)">{logo(0,0,210,"P")}</g></svg>', f"{out}/logo-{k}.png")
        png('<svg xmlns="http://www.w3.org/2000/svg" width="900" height="200" viewBox="0 0 900 200"><g font-family="Gelasio,Georgia,DejaVu Serif,serif"><text x="450" y="105" font-size="110" font-weight="900" text-anchor="middle" fill="#f0e0bd">aperture</text><text x="450" y="160" font-size="32" font-style="italic" text-anchor="middle" fill="#c9a77a" letter-spacing="24">LABORATORIES</text></g></svg>', out + "/wordmark.png")
        sys.exit()
    if len(sys.argv) > 2 and sys.argv[1] == "preview":  # preview <theme> <file>
        open(sys.argv[3], "w").write(svg(sys.argv[2], True, s=dict(cpu=26,cores=[20,45,80,30],mem=45,temp=50,disk=38,fan="2400",ts="100.64.0.7",up="3h 12m"))); sys.exit()
    tn = pick_theme(c); W, H = screen()
    os.makedirs(CACHE, exist_ok=True)
    flip = "a" if int(time.time()//60) % 2 else "b"
    path = f"{CACHE}/wall-{flip}.png"
    png(svg(tn, True, W, H, stats()), path)
    subprocess.run(["pcmanfm", "--set-wallpaper", path, "--wallpaper-mode=stretch"], stderr=subprocess.DEVNULL)

PYEOF
chmod +x ~/.local/bin/retro-lab-render
sudo mkdir -p /usr/share/aperture
python3 ~/.local/bin/retro-lab-render static /tmp/aperture-assets
sudo cp /tmp/aperture-assets/login.png /tmp/aperture-assets/wall.png /tmp/aperture-assets/logo.png /usr/share/aperture/
# Themed login box (dark rounded panel, warm colours). Logo sits above the box.
sudo mkdir -p /usr/share/themes/ApertureLogin/gtk-3.0
printf '[Desktop Entry]\nType=X-GNOME-Metatheme\nName=ApertureLogin\nComment=Aperture Laboratories login\n\n[X-GNOME-Metatheme]\nGtkTheme=ApertureLogin\n' | sudo tee /usr/share/themes/ApertureLogin/index.theme >/dev/null
sudo tee /usr/share/themes/ApertureLogin/gtk-3.0/gtk.css >/dev/null <<'GTK'
* { font-family: "DejaVu Serif", serif; font-size: 16px; font-weight: bold; color: #f6e7c1; text-shadow: none; box-shadow: none; border: none; border-radius: 0; background-image: none; background-color: transparent; padding: 0; margin: 0; }
#login_window, #login-window { background-color: #2a1b14; border: 3px solid #e0873a; padding: 26px; }
#panel_window, #panel-window { background-color: rgba(42,27,20,0.0); }
image { opacity: 0; margin: 0 -80px 0 0; }
combobox, combobox * { color: #e7c06a; font-style: italic; }
entry { background-color: #1c110b; color: #f6e7c1; caret-color: #e0873a; border: 2px solid #e0873a; border-radius: 16px; padding: 8px 14px; min-height: 24px; margin: 6px 0; }
entry:focus { border-color: #ffd08a; }
button { background-color: #e0873a; border: 2px solid #ffd08a; border-radius: 16px; padding: 7px 22px; margin: 6px 4px 0 4px; }
button label { color: #2a1b14; }
button:hover { background-color: #ffd08a; }
menu, menuitem, popover { background-color: #3a2518; color: #f6e7c1; padding: 4px; }
menuitem:hover { background-color: #e0873a; color: #2a1b14; }
GTK
# Rename the session so it no longer says "Raspberry Pi OS"
for s in /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop; do
  case "$s" in */aperture.desktop) continue;; esac
  [ -f "$s" ] && sudo sed -i '/^Name\(\[.*\]\)\?=.*\(Raspberry\|labwc\|Labwc\)/ s/=.*/=Aperture Lab (safe mode)/' "$s" || true
done
for f in /etc/lightdm/pi-greeter.conf; do
  if [ -f "$f" ]; then
    sudo sed -i '/^wallpaper=/d;/^desktop_bg=/d;/^gtk-theme-name=/d;/^gtk-font-name=/d' "$f"
    sudo sed -i '/^\[greeter\]/a wallpaper=/usr/share/aperture/login.png\ngtk-theme-name=ApertureLogin\ngtk-font-name=DejaVu Serif 12' "$f"
  fi
done
if dpkg -s lightdm-gtk-greeter >/dev/null 2>&1; then
  sudo tee /etc/lightdm/lightdm-gtk-greeter.conf >/dev/null <<'GC'
[greeter]
background=/usr/share/aperture/login.png
user-background=false
theme-name=ApertureLogin
font-name=DejaVu Serif 12
hide-user-image=true
indicators=~host;~spacer;~clock;~spacer;~session;~power
clock-format=%a %H:%M
position=50%,center 50%,center
GC
fi
sudo mkdir -p /usr/share/plymouth/themes/aperture
sudo cp /tmp/aperture-assets/logo-*.png /tmp/aperture-assets/wordmark.png /usr/share/plymouth/themes/aperture/
sudo tee /usr/share/plymouth/themes/aperture/aperture.plymouth >/dev/null <<'PL'
[Plymouth Theme]
Name=Aperture
Description=Retro Aperture Laboratories boot screen (amber terminal)
ModuleName=script
[script]
ImageDir=/usr/share/plymouth/themes/aperture
ScriptFile=/usr/share/plymouth/themes/aperture/aperture.script
PL
sudo tee /usr/share/plymouth/themes/aperture/aperture.script >/dev/null <<'PS'
Window.SetBackgroundTopColor(0.07, 0.04, 0.0);
Window.SetBackgroundBottomColor(0.07, 0.04, 0.0);
W = Window.GetWidth();
H = Window.GetHeight();
lines[0] = "APERTURE LABORATORIES BIOS v1.953";
lines[1] = "CPU: ARM CORTEX-A76 x4 .......... OK";
lines[2] = "MEMORY TEST: 16384K";
lines[3] = "DETECTING DRIVES ................ OK";
lines[4] = "LOADING KERNEL .................. OK";
lines[5] = "MOUNTING /LAB ................... OK";
lines[6] = "STARTING NETWORK ................ OK";
lines[7] = "TAILSCALE LINK .................. ESTABLISHED";
lines[8] = "FIREWALL ........................ ACTIVE";
lines[9] = "ACOUSTICS ....................... WARM";
lines[10] = "LOADING WIDGETS ................. OK";
lines[11] = "AWAITING USER";
n = 12;
sz = Math.Int(H / 40);
if (sz < 16) sz = 16;
font = "DejaVu Sans Mono Bold " + sz;
x0 = W * 0.08;
y0 = H * 0.10;
step = sz * 2.1;
for (i = 0; i < n; i++) {
  img[i] = Image.Text(lines[i], 1.0, 0.69, 0.0, 1.0, font);
  spr[i] = Sprite(img[i]);
  spr[i].SetPosition(x0, y0 + i * step, 10);
  spr[i].SetOpacity(0);
}
cimg = Image.Text("_", 1.0, 0.69, 0.0, 1.0, font);
cur = Sprite(cimg);
cur.SetOpacity(0);
s = H / 1080;
for (i = 0; i < 7; i++) frame[i] = Image("logo-" + i + ".png").Scale(420 * s, 420 * s);
word = Image("wordmark.png").Scale(720 * s, 160 * s);
logo_sprite = Sprite(frame[0]);
logo_sprite.SetPosition(W / 2 - 210 * s, H / 2 - 300 * s, 20);
logo_sprite.SetOpacity(0);
word_sprite = Sprite(word);
word_sprite.SetPosition(W / 2 - 360 * s, H / 2 + 90 * s, 20);
word_sprite.SetOpacity(0);
counter = 0;
fun refresh() {
  counter++;
  if (counter < 190) {
    shown = Math.Int(counter / 13);
    if (shown > n - 1) shown = n - 1;
    for (i = 0; i <= shown; i++) spr[i].SetOpacity(1);
    cur.SetPosition(x0 + img[shown].GetWidth() + 6, y0 + shown * step, 10);
    ph = counter - 50 * Math.Int(counter / 50);
    if (ph < 28) cur.SetOpacity(1); else cur.SetOpacity(0);
  } else {
    f = 1 - (counter - 190) / 20;
    if (f < 0) f = 0;
    for (i = 0; i < n; i++) spr[i].SetOpacity(f);
    cur.SetOpacity(0);
  }
  if (counter > 205) {
    idx = Math.Int((counter - 205) / 10);
    if (idx > 6) idx = 6;
    logo_sprite.SetImage(frame[idx]);
    logo_sprite.SetOpacity(1);
  }
  if (counter > 285) {
    o = (counter - 285) / 30;
    if (o > 1) o = 1;
    word_sprite.SetOpacity(o);
  }
}
Plymouth.SetRefreshFunction(refresh);
PS
# Startup chime during the boot animation (before login), and hold the boot screen until the animation has finished
sudo tee /usr/local/sbin/aperture-chime >/dev/null <<'CH'
#!/bin/bash
U=$(getent passwd 1000 | cut -d: -f1); C=/home/$U/.config/retro-lab/config
grep -q '^sounds=off' "$C" 2>/dev/null && exit 0
S=$(grep '^sound_style=' "$C" 2>/dev/null | cut -d= -f2-); V=$(grep '^sound_volume=' "$C" 2>/dev/null | cut -d= -f2-)
F=/home/$U/.local/share/retro-lab/sounds/${S:-a-warm-synth}/startup.wav
[ -f "$F" ] || exit 0
while [ "$(cut -d. -f1 /proc/uptime)" -lt 7 ]; do sleep 0.2; done
python3 - "$F" "${V:-100}" <<'PY' | aplay -q -
import sys, wave, array, io
w = wave.open(sys.argv[1]); p = w.getparams(); d = array.array("h", w.readframes(p.nframes)); v = int(sys.argv[2]) / 100
d = array.array("h", [int(x * v) for x in d])
o = io.BytesIO(); x = wave.open(o, "wb"); x.setparams(p); x.writeframes(d.tobytes()); x.close()
sys.stdout.buffer.write(o.getvalue())
PY
CH
sudo chmod +x /usr/local/sbin/aperture-chime
sudo tee /etc/systemd/system/aperture-chime.service >/dev/null <<'SV'
[Unit]
Description=Aperture startup chime
After=sound.target alsa-restore.service
[Service]
Type=simple
ExecStart=/usr/local/sbin/aperture-chime
[Install]
WantedBy=multi-user.target
SV
for u in plymouth-quit lightdm; do
  sudo mkdir -p /etc/systemd/system/$u.service.d
  printf '[Service]\nExecStartPre=/bin/sh -c '"'"'while [ "$(cut -d. -f1 /proc/uptime)" -lt 10 ]; do sleep 0.3; done'"'"'\n' | sudo tee /etc/systemd/system/$u.service.d/aperture-hold.conf >/dev/null
done
sudo systemctl daemon-reload
sudo systemctl enable aperture-chime.service 2>/dev/null || true
for f in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
  [ -f "$f" ] && ! grep -q splash "$f" && sudo sed -i 's/$/ quiet splash plymouth.ignore-serial-consoles/' "$f" || true
done
sudo plymouth-set-default-theme -R aperture || echo "(boot splash step skipped, everything else still works)"
cat > ~/.local/bin/lab-desk <<'LDS'
#!/bin/bash
# Lab Desk is the desktop itself: it restarts if it is closed or crashes. Also starts the startup animation.
mkdir -p ~/.cache/retro-lab
exec 9> ~/.cache/retro-lab/desk.lock
flock -n 9 || exit 0     # already running
B=$(command -v chromium || command -v chromium-browser || command -v vivaldi-stable)
(
  while true; do
    pgrep -f lab-desk.py >/dev/null || (nohup python3 ~/.local/share/retro-lab/lab-desk.py >/dev/null 2>&1 &)
    for i in $(seq 1 40); do curl -s -o /dev/null http://localhost:8787/ && break; sleep 0.25; done
    "$B" --class=lab-desk --app=http://localhost:8787 --start-maximized --enable-gpu-rasterization --ignore-gpu-blocklist --disable-background-timer-throttling --no-first-run --user-data-dir="$HOME/.cache/retro-lab/browser"
    sleep 1
  done
) &
if grep -q '^splash=on' ~/.config/retro-lab/config; then
  sleep 3
  ~/.local/bin/lab-splash
fi
wait
LDS
chmod +x ~/.local/bin/lab-desk
cat > ~/.local/bin/lab-splash <<'LSP'
#!/bin/bash
# The startup animation (also in the start menu as "Replay startup animation").
# After login it plays the logo part (the terminal text already ran during boot). "lab-splash full" plays everything.
B=$(command -v chromium || command -v chromium-browser || command -v vivaldi-stable)
Q="?skiplog=1"; [ "$1" = full ] && Q=""
exec "$B" --kiosk --app="http://localhost:8787/splash$Q" --no-first-run --noerrdialogs --autoplay-policy=no-user-gesture-required --user-data-dir="$HOME/.cache/retro-lab/splash-browser"
LSP
chmod +x ~/.local/bin/lab-splash
cat > ~/.local/bin/lab-bar <<'LB'
#!/bin/bash
# Swap the stock Raspberry Pi panel for the lab taskbar, as early as possible.
pkill -f 'lwrespawn.*wf-panel-pi' 2>/dev/null; pkill wf-panel-pi 2>/dev/null
( for i in 1 2 3 4 5 6; do sleep 1; pkill -f 'lwrespawn.*wf-panel-pi' 2>/dev/null; pkill wf-panel-pi 2>/dev/null; done ) &
pgrep -x waybar >/dev/null || exec waybar -c ~/.config/waybar/config -s ~/.config/waybar/style.css
LB
chmod +x ~/.local/bin/lab-bar
# Take the stock Pi desktop and panel out of the session (they cause the Pi OS wallpaper flash)
sudo apt-get install -y swaybg >/dev/null 2>&1 || true
mkdir -p ~/.config/labwc
SRC=~/.config/labwc/autostart; [ -f "$SRC" ] || SRC=/etc/xdg/labwc/autostart
if [ -f "$SRC" ]; then grep -v -E 'pcmanfm|wf-panel-pi|aperture-bg' "$SRC" > /tmp/labwc-autostart.new; else : > /tmp/labwc-autostart.new; fi
grep -q 'xdg-autostart\|dex' /tmp/labwc-autostart.new || echo 'dex --autostart --environment labwc &' >> /tmp/labwc-autostart.new
echo 'swaybg -c "#2a1b14" -i /usr/share/aperture/wall.png -m fill & # aperture-bg' >> /tmp/labwc-autostart.new
cp /tmp/labwc-autostart.new ~/.config/labwc/autostart
pkill pcmanfm 2>/dev/null || true
# Keep Lab Desk at the very bottom, out of the taskbar and out of Alt+Tab
mkdir -p ~/.config/labwc
python3 - <<'PYRC'
import os, re
p = os.path.expanduser("~/.config/labwc/rc.xml")
rule = """<!-- aperture-lab -->
    <windowRule identifier="lab-desk"><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher><action name="ToggleAlwaysOnBottom"/></windowRule>
    <windowRule identifier="chrome-localhost__-*"><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher><action name="ToggleAlwaysOnBottom"/></windowRule>
    <!-- /aperture-lab -->"""
x = open(p).read() if os.path.exists(p) else "<?xml version=\"1.0\"?>\n<labwc_config>\n</labwc_config>\n"
x = re.sub(r"<!-- aperture-lab -->.*?<!-- /aperture-lab -->", "", x, flags=re.S)
if "<windowRules>" in x: x = x.replace("<windowRules>", "<windowRules>\n    " + rule, 1)
elif "</labwc_config>" in x: x = x.replace("</labwc_config>", "  <windowRules>\n    " + rule + "\n  </windowRules>\n</labwc_config>")
open(p, "w").write(x)
PYRC
pkill -HUP labwc 2>/dev/null || true
# Aperture's own desktop session: labwc with ONLY our startup list, so no stock Pi desktop, panel or wallpaper ever starts.
sudo apt-get install -y dex labwc swaybg >/dev/null 2>&1 || true
sudo mkdir -p /etc/aperture/labwc
sudo tee /etc/aperture/labwc/autostart >/dev/null <<'AUT'
swaybg -c "#2a1b14" -i /usr/share/aperture/wall.png -m fill &
for f in "$HOME"/.config/autostart/*.desktop; do [ -f "$f" ] && dex "$f" & done
AUT
sudo tee /etc/aperture/labwc/rc.xml >/dev/null <<'RCX'
<?xml version="1.0"?>
<labwc_config>
  <windowRules>
    <windowRule identifier="lab-desk"><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher><action name="ToggleAlwaysOnBottom"/></windowRule>
    <windowRule identifier="chrome-localhost__-*"><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher><action name="ToggleAlwaysOnBottom"/></windowRule>
  </windowRules>
</labwc_config>
RCX
sudo tee /usr/local/bin/aperture-session >/dev/null <<'ASS'
#!/bin/bash
# Aperture Lab desktop session
[ -f /etc/default/keyboard ] && . /etc/default/keyboard
export XKB_DEFAULT_LAYOUT="${XKBLAYOUT:-us}" XKB_DEFAULT_MODEL="${XKBMODEL:-}" XKB_DEFAULT_VARIANT="${XKBVARIANT:-}" XKB_DEFAULT_OPTIONS="${XKBOPTIONS:-}"
export XDG_CURRENT_DESKTOP=labwc:wlroots XDG_SESSION_DESKTOP=labwc
exec labwc -C /etc/aperture/labwc
ASS
sudo chmod +x /usr/local/bin/aperture-session
sudo tee /usr/share/wayland-sessions/aperture.desktop >/dev/null <<'ASD'
[Desktop Entry]
Name=Aperture Lab
Comment=Aperture Laboratories desktop
Exec=/usr/local/bin/aperture-session
Type=Application
DesktopNames=labwc;wlroots
ASD
# make it the default session (the stock Pi sessions stay available as "safe mode")
sudo sed -i 's/^user-session=.*/user-session=aperture/; s/^autologin-session=.*/autologin-session=aperture/' /etc/lightdm/lightdm.conf 2>/dev/null || true
sudo mkdir -p /etc/lightdm/lightdm.conf.d
printf '[Seat:*]\nuser-session=aperture\n' | sudo tee /etc/lightdm/lightdm.conf.d/60-aperture-session.conf >/dev/null
printf '[Desktop]\nSession=aperture\n' > ~/.dmrc
[ -f /var/lib/AccountsService/users/$USER ] && sudo sed -i 's/^Session=.*/Session=aperture/' /var/lib/AccountsService/users/$USER || true
sed -i "s/^splash=.*/splash=off/" ~/.config/retro-lab/config
echo "Done. Restart now:  sudo reboot"
