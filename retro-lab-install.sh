#!/bin/bash
# Aperture Laboratories retro-lab theme installer for Raspberry Pi OS (Pi 5).
# Run as your normal user (NOT sudo):  bash retro-lab-install.sh
# Safe to run again any time: it refreshes the theme and keeps your settings.
set -e
HOSTNAME_NEW="aperture-lab"      # change this line if you want a different computer name
if [ "$(id -u)" = "0" ]; then echo "Run this as your normal user, not with sudo."; exit 1; fi
echo "== 1/7 Installing packages =="
sudo apt-get update
sudo apt-get install -y librsvg2-bin waybar wofi plymouth plymouth-themes fonts-dejavu curl python3 swaybg wlr-randr bluez cifs-utils
echo "== 2/7 Installing the theme engine =="
mkdir -p ~/.local/bin ~/.config/retro-lab ~/.cache/retro-lab
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
[ -f ~/.config/retro-lab/config ] || cat > ~/.config/retro-lab/config <<'CFG'
# mode: auto | day | dusk | night   (auto = switches by the hours below, 24h clock)
mode=auto
dawn=6
day=8
dusk=17
night=20
CFG

# retro-update: downloads and applies the newest version of this installer
cat > ~/.local/bin/retro-update <<'UP'
#!/bin/bash
URL=$(grep '^update_url=' ~/.config/retro-lab/config | cut -d= -f2-)
if [ -z "$URL" ]; then echo "No update address set yet. Ask Claude for the latest retro-lab-install.sh and run it with: bash retro-lab-install.sh"; exit 1; fi
curl -fsSL "$URL" -o /tmp/retro-lab-install.sh && bash /tmp/retro-lab-install.sh
UP
chmod +x ~/.local/bin/retro-update
U="https://raw.githubusercontent.com/Trauma-John/aperture-lab-pi/main/retro-lab-install.sh"
if grep -q '^update_url=' ~/.config/retro-lab/config; then sed -i "s|^update_url=\$|update_url=$U|" ~/.config/retro-lab/config; else echo "update_url=$U" >> ~/.config/retro-lab/config; fi

# Theme switcher: retro-theme day|dusk|night|auto  (Lab Desk picks it up within seconds)
cat > ~/.local/bin/retro-theme <<'SW'
#!/bin/bash
case "$1" in day|dusk|night|auto) sed -i "s/^mode=.*/mode=$1/" ~/.config/retro-lab/config; echo "Theme: $1";; *) echo "Use: retro-theme day|dusk|night|auto";; esac
SW
chmod +x ~/.local/bin/retro-theme

# Lab Desk: the draggable widgets + start menu
mkdir -p ~/.local/share/retro-lab ~/.config/autostart ~/.local/share/applications
rm -f ~/.config/autostart/retro-lab.desktop
cat > ~/.local/share/retro-lab/lab-desk.py <<'LDPY'
#!/usr/bin/env python3
"""Aperture Lab Desk: draggable desktop widgets served on http://localhost:8787 (no extra packages needed)."""
import configparser, getpass, shlex, glob, json, os, re, time, threading, subprocess, urllib.request, http.server, socketserver, collections, datetime, shutil, socket
HOME = os.path.expanduser("~"); CFG = HOME + "/.config/retro-lab/config"; LAYOUT = HOME + "/.config/retro-lab/layout.json"
PORT = int(os.environ.get("LABDESK_PORT", "8787"))
def cfg():
    c = dict(mode="auto", dawn="6", day="8", dusk="17", night="20", place="Penn Yan, NY", lat="42.66", lon="-77.05", tz="America/New_York", ping_host="1.1.1.1")
    try:
        for l in open(CFG):
            if "=" in l and not l.startswith("#"):
                k, v = l.strip().split("=", 1); c[k.strip()] = v.strip()
    except OSError: pass
    return c
def setmode(m):
    c = open(CFG).read() if os.path.exists(CFG) else ""
    c = re.sub(r"^mode=.*$", "mode=" + m, c, flags=re.M) if re.search(r"^mode=", c, re.M) else c + "\nmode=" + m + "\n"
    open(CFG, "w").write(c)
N = 60
H = collections.defaultdict(lambda: collections.deque(maxlen=N)); CUR = {}; PING = collections.deque(maxlen=30); TOP = []; WX = {"data": None, "t": 0}
def sh(cmd, t=3):
    try: return subprocess.run(cmd, capture_output=True, text=True, timeout=t).stdout
    except Exception: return ""
def read_cpu():
    r = {}
    for l in open("/proc/stat"):
        if l.startswith("cpu"):
            p = l.split(); v = list(map(int, p[1:9])); r[p[0]] = (sum(v) - v[3] - v[4], sum(v))
    return r
def disk_bytes():
    r = w = 0
    for l in open("/proc/diskstats"):
        p = l.split()
        if re.match(r"^(sd[a-z]+|mmcblk\d+|nvme\d+n\d+|vd[a-z]+)$", p[2]): r += int(p[5]) * 512; w += int(p[9]) * 512
    return r, w
def net_bytes():
    rx = tx = 0
    for l in open("/proc/net/dev").readlines()[2:]:
        n, d = l.split(":"); 
        if n.strip() != "lo": f = d.split(); rx += int(f[0]); tx += int(f[8])
    return rx, tx
def power():
    o = sh(["vcgencmd", "pmic_read_adc"]); cur = dict(re.findall(r"(\w+)_A current\(\d+\)=([\d.]+)A", o)); vol = dict(re.findall(r"(\w+)_V volt\(\d+\)=([\d.]+)V", o))
    return round(sum(float(cur[k]) * float(vol[k]) for k in cur if k in vol), 1) if cur else None
def sampler():
    pc, pd, pn, pt = read_cpu(), disk_bytes(), net_bytes(), time.time(); time.sleep(1)
    while True:
        c, d, n, t = read_cpu(), disk_bytes(), net_bytes(), time.time(); dt = max(t - pt, .1)
        cores = [100 * (c[k][0] - pc[k][0]) / max(1, c[k][1] - pc[k][1]) for k in sorted((k for k in c if k != "cpu"), key=lambda s: int(s[3:]))]
        cpu = 100 * (c["cpu"][0] - pc["cpu"][0]) / max(1, c["cpu"][1] - pc["cpu"][1])
        mi = {l.split(":")[0]: int(l.split()[1]) for l in open("/proc/meminfo")}
        try: temp = int(open("/sys/class/thermal/thermal_zone0/temp").read()) / 1000
        except Exception: temp = None
        fan = None
        if os.path.isdir("/sys/class/hwmon"):
            for x in os.listdir("/sys/class/hwmon"):
                try: fan = int(open(f"/sys/class/hwmon/{x}/fan1_input").read()); break
                except Exception: pass
        du = shutil.disk_usage("/"); up = float(open("/proc/uptime").read().split()[0])
        CUR.update(cores=cores, cpu=cpu, mem=100 * (1 - mi["MemAvailable"] / mi["MemTotal"]), memUsedGB=(mi["MemTotal"] - mi["MemAvailable"]) / 1048576, memTotalGB=mi["MemTotal"] / 1048576,
                   commitGB=mi.get("Committed_AS", 0) / 1048576, commitLimitGB=mi.get("CommitLimit", 0) / 1048576, temp=temp, fan=fan, uptime=up, diskPct=100 * du.used / du.total, diskFreeGB=du.free / 1e9,
                   dread=(d[0] - pd[0]) / dt, dwrite=(d[1] - pd[1]) / dt, down=(n[0] - pn[0]) / dt, up_=(n[1] - pn[1]) / dt, watts=power(), host=os.uname().nodename, user=getpass.getuser(),
                   ts=sh(["tailscale", "ip", "-4"]).strip().split("\n")[0] or None, load=os.getloadavg()[0])
        for k in ("cpu", "mem", "dread", "dwrite", "down", "up_", "temp", "watts"): H[k].append(CUR.get(k) or 0)
        pc, pd, pn, pt = c, d, n, t; time.sleep(2)
def pinger():
    while True:
        o = sh(["ping", "-c", "1", "-W", "1", cfg()["ping_host"]], 3); m = re.search(r"time=([\d.]+)", o); PING.append(float(m.group(1)) if m else None); time.sleep(3)
def topper():
    while True:
        agg = collections.Counter()
        for l in sh(["ps", "-eo", "comm=,rss="]).splitlines():
            try: n, r = l.rsplit(None, 1); agg[n.strip()] += int(r)
            except Exception: pass
        TOP[:] = [[k, v / 1024] for k, v in agg.most_common(6)]; time.sleep(5)
def weather():
    c = cfg()
    if time.time() - WX["t"] < 600: return
    WX["t"] = time.time()
    def go():
        try:
            u = ("https://api.open-meteo.com/v1/forecast?latitude=%s&longitude=%s&current=temperature_2m,relative_humidity_2m,dew_point_2m,pressure_msl,weather_code,wind_speed_10m,uv_index"
                 "&hourly=temperature_2m,pressure_msl&daily=temperature_2m_max,temperature_2m_min,sunrise,sunset,uv_index_max,weather_code&temperature_unit=fahrenheit&wind_speed_unit=mph&timezone=%s&forecast_days=5&forecast_hours=24") % (c["lat"], c["lon"], c["tz"].replace("/", "%2F"))
            WX["data"] = json.load(urllib.request.urlopen(u, timeout=10)); WX["data"]["place"] = c["place"]
        except Exception: WX["t"] = time.time() - 540
    threading.Thread(target=go, daemon=True).start()
APPS = {"t": 0, "list": []}
def apps():
    if time.time() - APPS["t"] < 60 and APPS["list"]: return APPS["list"]
    out = {}
    for d in ("/usr/share/applications", HOME + "/.local/share/applications"):
        for f in sorted(glob.glob(d + "/*.desktop")):
            p = configparser.RawConfigParser(strict=False); p.optionxform = str
            try: p.read(f, encoding="utf-8"); e = p["Desktop Entry"]
            except Exception: continue
            if e.get("Type", "Application") != "Application" or e.get("NoDisplay", "").lower() == "true" or e.get("Hidden", "").lower() == "true" or not e.get("Exec"): continue
            ids = os.path.basename(f)
            out[ids] = dict(id=ids, name=e.get("Name", ids), exec=e["Exec"], term=e.get("Terminal", "").lower() == "true", cat=(e.get("Categories", "Other").split(";")[0] or "Other"))
    APPS.update(t=time.time(), list=sorted(out.values(), key=lambda a: a["name"].lower())); return APPS["list"]
def launch(i):
    a = next((x for x in apps() if x["id"] == i), None)
    if not a: return
    cmd = shlex.split(re.sub(r"%[a-zA-Z%]", "", a["exec"]))
    if a["term"]: cmd = ["x-terminal-emulator", "-e"] + cmd
    subprocess.Popen(cmd, start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
def power_action(act):
    cmds = dict(reboot=["systemctl", "reboot"], shutdown=["systemctl", "poweroff"], logout=["labwc", "--exit"], lock=["swaylock", "-f", "-c", "2a1b14"])
    if act not in cmds: return
    if act in ("reboot", "shutdown", "logout"):
        subprocess.run([HOME + "/.local/bin/retro-sound", "shutdown"], timeout=6)   # plays only if sounds are on
    subprocess.Popen(cmds[act], start_new_session=True)
BAR = {"mode": ""}
PAL = {  # bg, panel, text, sub, accent, stroke
 "night": ("42,27,20", "255,225,170", "#f0e0bd", "#c9a77a", "#e0873a"),
 "day":   ("243,230,198", "122,59,20", "#4a2a16", "#8a5a38", "#d27a35"),
 "dusk":  ("90,45,28", "255,235,200", "#fbeed0", "#f0d6a4", "#e7a947")}
def theme_now():
    c = cfg()
    if c["mode"] in PAL: return c["mode"]
    h = datetime.datetime.now().hour; a, d, u, n = (int(c[k]) for k in ("dawn", "day", "dusk", "night"))
    return "day" if d <= h < u else "dusk" if (a <= h < d or u <= h < n) else "night"
def style_files():
    t = theme_now()
    if t == BAR["mode"]: return
    BAR["mode"] = t; bg, pn, tx, sb, ac = PAL[t]
    wb = f"""* {{ font-family: "DejaVu Sans Mono", monospace; font-size: 15px; border: none; border-radius: 0; min-height: 0; }}
window#waybar {{ background: transparent; color: {tx}; }}
#custom-start {{ font-size: 22px; color: {sb}; padding: 2px 18px; margin: 6px 6px 6px 12px; border-radius: 22px; background: rgba({bg},0.92); }}
#custom-start:hover {{ color: {tx}; }}
#taskbar {{ margin: 6px 0; }}
#taskbar button {{ background: rgba({bg},0.85); color: {tx}; border-radius: 18px; padding: 2px 16px; margin: 0 4px; }}
#taskbar button.active {{ background: {ac}; color: rgb({bg}); }}
#tray, #pulseaudio, #network, #custom-power {{ background: rgba({bg},0.92); color: {tx}; border-radius: 18px; padding: 2px 16px; margin: 6px 4px; }}
#custom-power {{ margin-right: 12px; }}
"""
    wf = f"""window {{ background: rgb({bg}); border: 2px solid rgba({pn},0.25); border-radius: 22px; font-family: "DejaVu Serif", serif; font-size: 17px; color: {tx}; }}
#input {{ background: rgba({pn},0.1); color: {tx}; border: 1px solid rgba({pn},0.25); border-radius: 14px; margin: 10px; padding: 8px 12px; }}
#inner-box, #outer-box, #scroll {{ background: transparent; }}
#entry {{ padding: 6px 10px; border-radius: 10px; }}
#entry:selected {{ background: {ac}; }} #entry:selected * {{ color: rgb({bg}); }}
#text {{ color: {tx}; }}
"""
    for path, body in ((HOME + "/.config/waybar/style.css", wb), (HOME + "/.config/wofi/style.css", wf)):
        os.makedirs(os.path.dirname(path), exist_ok=True); open(path, "w").write(body)
    subprocess.run(["pkill", "-USR2", "waybar"], stderr=subprocess.DEVNULL)
def styler():
    while True:
        try: style_files()
        except Exception: pass
        time.sleep(30)
def menu(kind):
    if kind == "power":
        o = subprocess.run(["wofi", "--dmenu", "--prompt", "Power"], input="Lock\nLog out\nRestart\nShut down\n", capture_output=True, text=True).stdout.strip()
        power_action({"Lock": "lock", "Log out": "logout", "Restart": "reboot", "Shut down": "shutdown"}.get(o, ""))
    else: subprocess.run(["wofi", "--show", "drun", "--prompt", "Search"])

KEYS = {"mode", "dawn", "day", "dusk", "night", "sounds", "sound_style", "sound_volume", "splash", "server_name", "server_lan", "server_share", "port_jellyfin", "port_seerr", "pc_name", "pc_mac", "server_user", "extras", "mail_tab"}
def setkey(k, v):
    if k not in KEYS or not re.match(r"^[A-Za-z0-9._:/ -]{0,80}$", v): return False
    lines = open(CFG).read().splitlines() if os.path.exists(CFG) else []
    for i, l in enumerate(lines):
        if l.startswith(k + "="): lines[i] = f"{k}={v}"; break
    else: lines.append(f"{k}={v}")
    open(CFG, "w").write("\n".join(lines) + "\n"); return True
def first(cmd):
    return sh(cmd).strip().splitlines()[0] if sh(cmd).strip() else ""
def settings_state():
    c = cfg(); st = dict(cfg=c)
    st["autologin"] = bool(sh(["bash", "-c", "grep -hE '^autologin-user=[^ ]' /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.d/* 2>/dev/null"]).strip())
    m = re.search(r"timeout (\d+)", open(HOME + "/.config/autostart/lab-idle-lock.desktop").read()) if os.path.exists(HOME + "/.config/autostart/lab-idle-lock.desktop") else None
    st["lock_min"] = int(m.group(1)) // 60 if m else 0
    st["autoupdates"] = "Unattended-Upgrade \"1\"" in (open("/etc/apt/apt.conf.d/20auto-upgrades").read() if os.path.exists("/etc/apt/apt.conf.d/20auto-upgrades") else "")
    st["firewall"] = sh(["systemctl", "is-active", "ufw"]).strip() == "active"
    st["tailscale"] = sh(["tailscale", "ip", "-4"]).strip().split("\n")[0] or ""
    st["roms"] = "/mnt/zimagames" in (open("/etc/fstab").read() if os.path.exists("/etc/fstab") else "")
    st["panel"] = "lab" if sh(["pgrep", "-x", "waybar"]).strip() else "stock"
    return st
TERM = {  # actions that need a terminal window (passwords, questions, long output)
 "login_password": "retro-login password", "login_auto": "retro-login auto", "secure": "retro-secure", "connect": "retro-connect",
 "update": "retro-update", "system_update": "sudo apt update && sudo apt full-upgrade -y", "fix_vivaldi": "retro-fix-vivaldi", "wake_setup": "retro-wake-setup", "guided_tailscale": "sudo tailscale up --operator=$USER", "roms_setup": "retro-roms", "roms_off": "retro-roms off"}
QUIET = {"panel_lab": ["retro-panel", "lab"], "panel_stock": ["retro-panel", "stock"], "rebuild": ["retro-connect", "--rebuild"], "chime": ["retro-sound", "startup"], "replay": ["lab-splash"],
         "lock_off": ["retro-lock", "off"], "lock_5": ["retro-lock", "5"], "lock_10": ["retro-lock", "10"], "lock_15": ["retro-lock", "15"], "lock_30": ["retro-lock", "30"], "lock_60": ["retro-lock", "60"]}
def run_action(a):
    if a in TERM:
        subprocess.Popen(["x-terminal-emulator", "-e", "bash", "-lc", "export PATH=$HOME/.local/bin:$PATH; " + TERM[a] + "; echo; read -r -p 'Done. Press Enter to close.'"], start_new_session=True)
    elif a in QUIET:
        subprocess.Popen([HOME + "/.local/bin/" + QUIET[a][0]] + QUIET[a][1:], start_new_session=True)
    elif a == "control_centre":
        for x in apps():
            if re.search(r"control centre|raspberry pi configuration", x["name"], re.I): launch(x["id"]); return
    elif a == "settings": subprocess.Popen([HOME + "/.local/bin/lab-settings"], start_new_session=True)
# ---------- system settings (Wi-Fi, Bluetooth, display, sound, time, storage, about)
def run(cmd, t=8):
    try: r = subprocess.run(cmd, capture_output=True, text=True, timeout=t); return (r.stdout + r.stderr).strip() if r.returncode else r.stdout.strip()
    except Exception as e: return ""
OK = re.compile(r"^[\w .:@/+,=-]{1,80}$")
SS = re.compile(r"^[^\x00-\x1f]{1,64}$")
MAC = re.compile(r"^([0-9A-F]{2}:){5}[0-9A-F]{2}$", re.I)
DISPFILE = HOME + "/.config/retro-lab/display.json"
def sysinfo(w):
    if w == "wifi":
        raw = run(["nmcli", "-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY", "dev", "wifi", "list"], 10)
        nets, seen = [], set()
        for l in raw.splitlines():
            f = re.split(r"(?<!\\):", l)
            if len(f) >= 4 and f[1] and f[1] not in seen: seen.add(f[1]); nets.append(dict(use=f[0] == "*", ssid=f[1].replace("\\:", ":"), sig=int(f[2] or 0), sec=f[3]))
        return dict(radio=run(["nmcli", "radio", "wifi"]).strip() == "enabled", nets=sorted(nets, key=lambda n: -n["sig"])[:20], conn=run(["nmcli", "-t", "-f", "NAME,TYPE,DEVICE", "con", "show", "--active"]))
    if w == "bt":
        sh_ = run(["bluetoothctl", "show"]); devs = []
        for l in run(["bluetoothctl", "devices"]).splitlines():
            m = re.match(r"Device ([0-9A-F:]{17}) (.*)", l, re.I)
            if m: devs.append(dict(mac=m.group(1), name=m.group(2), connected="Connected: yes" in run(["bluetoothctl", "info", m.group(1)])))
        return dict(powered="Powered: yes" in sh_, devices=devs, present=bool(sh_))
    if w == "display":
        outs, cur = [], None
        for l in run(["wlr-randr"]).splitlines():
            if l and not l.startswith(" "): cur = dict(name=l.split()[0], modes=[], scale=1.0, cur=""); outs.append(cur)
            elif cur is not None:
                m = re.match(r"\s+(\d+x\d+) px, ([\d.]+) Hz(.*)", l)
                if m: cur["modes"].append(m.group(1) + "@" + m.group(2)); cur["cur"] = m.group(1) + "@" + m.group(2) if "current" in m.group(3) else cur["cur"]
                m = re.match(r"\s+Scale: ([\d.]+)", l)
                if m: cur["scale"] = float(m.group(1))
        return dict(outputs=outs)
    if w == "audio":
        vol = run(["wpctl", "get-volume", "@DEFAULT_AUDIO_SINK@"]); m = re.search(r"([\d.]+)", vol)
        sinks = [l.split("\t")[1] for l in run(["pactl", "list", "short", "sinks"]).splitlines() if "\t" in l]
        return dict(vol=int(float(m.group(1)) * 100) if m else None, muted="MUTED" in vol, sinks=sinks, default=run(["pactl", "get-default-sink"]))
    if w == "time":
        d = {k: v for k, v in (l.split("=", 1) for l in run(["timedatectl", "show"]).splitlines() if "=" in l)}
        return dict(tz=d.get("Timezone", ""), ntp=d.get("NTP") == "yes", now=run(["date", "+%a %d %b %Y %H:%M"]), zones=run(["timedatectl", "list-timezones"]).splitlines(), kb=run(["bash", "-c", "grep -h XKBLAYOUT /etc/default/keyboard"]))
    if w == "storage":
        return dict(df=run(["df", "-h", "--output=source,size,used,avail,pcent,target", "-x", "tmpfs", "-x", "devtmpfs", "-x", "squashfs"]), lsblk=run(["lsblk", "-o", "NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,MODEL"]))
    if w == "about":
        osr = {k: v.strip('"') for k, v in (l.split("=", 1) for l in open("/etc/os-release").read().splitlines() if "=" in l)}
        model = open("/proc/device-tree/model").read().strip("\0") if os.path.exists("/proc/device-tree/model") else ""
        return dict(os=osr.get("PRETTY_NAME", ""), kernel=run(["uname", "-r"]), model=model, host=socket.gethostname(), up=run(["uptime", "-p"]), throttled=run(["vcgencmd", "get_throttled"]), temp=run(["vcgencmd", "measure_temp"]), user=os.environ.get("USER", ""))
    return {}
def term(cmd):
    subprocess.Popen(["x-terminal-emulator", "-e", "bash", "-lc", cmd + "; echo; read -r -p 'Done. Press Enter to close.'"], start_new_session=True)
def apply_display():
    try: j = json.load(open(DISPFILE))
    except Exception: return
    for o, v in j.items():
        if OK.match(o) and re.match(r"^\d+x\d+@[\d.]+$", v.get("mode", "")) and re.match(r"^[\d.]+$", str(v.get("scale", "1"))):
            subprocess.run(["wlr-randr", "--output", o, "--mode", v["mode"], "--scale", str(v["scale"])], capture_output=True)
def sysact(j):
    a = j.get("a", ""); g = lambda k: str(j.get(k, ""))
    if a == "wifi_connect" and SS.match(g("ssid")):
        cmd = ["nmcli", "dev", "wifi", "connect", g("ssid")] + (["password", g("pw")] if g("pw") else [])
        return run(cmd, 30) or "Connected"
    if a == "wifi_radio": return run(["nmcli", "radio", "wifi", "on" if g("v") == "on" else "off"])
    if a == "wifi_forget" and SS.match(g("ssid")): return run(["nmcli", "con", "delete", g("ssid")])
    if a == "bt_power": return run(["bluetoothctl", "power", "on" if g("v") == "on" else "off"])
    if a == "bt_scan": subprocess.Popen(["bluetoothctl", "--timeout", "10", "scan", "on"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); return "Scanning for 10 seconds"
    if a in ("bt_connect", "bt_disconnect", "bt_pair", "bt_remove") and MAC.match(g("mac")):
        if a == "bt_pair": return "\n".join(run(["bluetoothctl", c, g("mac")], 25) for c in ("pair", "trust", "connect"))
        return run(["bluetoothctl", a[3:], g("mac")], 15)
    if a == "display" and OK.match(g("out")) and re.match(r"^\d+x\d+@[\d.]+$", g("mode")) and re.match(r"^[\d.]+$", g("scale")):
        r = run(["wlr-randr", "--output", g("out"), "--mode", g("mode"), "--scale", g("scale")])
        try: d = json.load(open(DISPFILE))
        except Exception: d = {}
        d[g("out")] = dict(mode=g("mode"), scale=g("scale")); open(DISPFILE, "w").write(json.dumps(d)); return r or "Applied"
    if a == "vol" and g("v").isdigit(): return run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", str(min(100, int(g("v")))) + "%"])
    if a == "mute": return run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"])
    if a == "sink" and OK.match(g("v")): return run(["pactl", "set-default-sink", g("v")])
    if a == "tz" and re.match(r"^[A-Za-z_]+(/[A-Za-z_+-]+){0,2}$", g("v")): term("sudo timedatectl set-timezone " + g("v")); return "Opening a terminal for your password"
    if a == "ntp": term("sudo timedatectl set-ntp " + ("true" if g("v") == "on" else "false")); return "Opening a terminal for your password"
    if a == "kb" and re.match(r"^[a-z]{2,3}$", g("v")): term("sudo raspi-config nonint do_configure_keyboard " + g("v") + "; echo 'Log out and back in to apply the keyboard.'"); return "Opening a terminal for your password"
    if a == "passwd": term("passwd"); return "Opening a terminal"
    if a == "hostname" and re.match(r"^[a-z][a-z0-9-]{0,30}$", g("v")): term("sudo hostnamectl set-hostname " + g("v")); return "Opening a terminal for your password"
    return "Not allowed"

class Q(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def send(self, body, ct="application/json"):
        b = body.encode() if isinstance(body, str) else body; self.send_response(200); self.send_header("Content-Type", ct); self.send_header("Cache-Control", "no-store"); self.send_header("Content-Length", str(len(b))); self.end_headers(); self.wfile.write(b)
    def do_GET(self):
        if self.path.startswith("/api/stats"):
            weather(); lay = None
            try: lay = json.load(open(LAYOUT))
            except Exception: pass
            self.send(json.dumps(dict(cur=CUR, hist={k: list(v) for k, v in H.items()}, ping=list(PING), top=TOP, weather=WX["data"], cfg=cfg(), layout=lay)))
        elif self.path.startswith("/api/sys"): self.send(json.dumps(sysinfo(re.sub(r"[^a-z]", "", self.path.split("w=")[-1]))))
        elif self.path.startswith("/api/apps"): self.send(json.dumps(apps()))
        elif self.path.startswith("/api/settings"): self.send(json.dumps(settings_state()))
        elif self.path.startswith("/settings"): self.send(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "settings.html")).read(), "text/html; charset=utf-8")
        elif self.path.startswith("/splash"): self.send(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "splash.html")).read(), "text/html; charset=utf-8")
        else: self.send(PAGE, "text/html; charset=utf-8")
    def do_POST(self):
        if self.headers.get("X-Lab") != "1": return self.send("{}")   # blocks other web pages from poking the desk
        b = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        if self.path == "/api/layout": os.makedirs(os.path.dirname(LAYOUT), exist_ok=True); open(LAYOUT, "w").write(b)
        elif self.path == "/api/mode" and b in ("auto", "day", "dusk", "night"): setmode(b)
        elif self.path == "/api/menu": threading.Thread(target=menu, args=(b,), daemon=True).start() if not subprocess.run(["pgrep", "-x", "wofi"], capture_output=True).stdout else subprocess.run(["pkill", "-x", "wofi"])
        elif self.path == "/api/chime": subprocess.Popen([HOME + "/.local/bin/retro-sound", "startup"], start_new_session=True)
        elif self.path == "/api/splash-done": subprocess.run(["pkill", "-f", "retro-lab/splash-browser"])
        elif self.path == "/api/set":
            try: j = json.loads(b); setkey(j["k"], str(j["v"]))
            except Exception: pass
        elif self.path == "/api/action": run_action(b)
        elif self.path == "/api/sysact":
            try: out = sysact(json.loads(b))
            except Exception as e: out = "Error"
            return self.send(json.dumps(dict(out=out)))
        elif self.path == "/api/mail":
            u = {"gmail": "https://mail.google.com/", "proton": "https://mail.proton.me/"}.get(cfg().get("mail_tab"), "https://mail.google.com/")
            subprocess.Popen(["xdg-open", u], start_new_session=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        elif self.path == "/api/launch": launch(b)
        elif self.path == "/api/power": power_action(b)
        elif self.path == "/api/reset":
            try: os.remove(LAYOUT)
            except OSError: pass
        self.send("{}")
PAGE = open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "lab-desk.html")).read() if os.path.exists(os.path.join(os.path.dirname(os.path.abspath(__file__)), "lab-desk.html")) else "@@PAGE@@"
if __name__ == "__main__":
    for f in (sampler, pinger, topper, styler): threading.Thread(target=f, daemon=True).start()
    threading.Timer(4, apply_display).start()
    class S(socketserver.ThreadingMixIn, http.server.HTTPServer): daemon_threads = True; allow_reuse_address = True
    S(("127.0.0.1", PORT), Q).serve_forever()
LDPY
cat > ~/.local/share/retro-lab/lab-desk.html <<'LDHTML'
<!doctype html><html><head><meta charset="utf-8"><title>Lab Desk</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:linear-gradient(#2a1b14,#3a2518);--panel:rgba(255,225,170,.08);--pstroke:rgba(255,225,170,.18);--text:#f0e0bd;--sub:#c9a77a;--acc:#e0873a;--acc2:#e7c06a;--track:rgba(255,225,170,.12);--halo:#d27a35;--word:#f0e0bd;--ho:.5}
*{box-sizing:border-box}html,body{margin:0;height:100%;overflow:hidden;background:var(--bg);color:var(--text);font-family:Gelasio,Georgia,"DejaVu Serif",serif;user-select:none}
#bgart{position:fixed;inset:0;width:100%;height:100%;pointer-events:none}
.w{position:absolute;background:var(--panel);border:1.5px solid var(--pstroke);border-radius:26px;padding:0;overflow:hidden;contain:layout paint;display:flex;flex-direction:column}
.w .bar{cursor:grab;display:flex;justify-content:space-between;align-items:center;padding:12px 18px 2px;font-size:14px;letter-spacing:2px;color:var(--sub);text-transform:uppercase}
.w .bar:active{cursor:grabbing}.w .x{cursor:pointer;opacity:.5;font-size:18px;padding:0 4px;letter-spacing:0}.w .x:hover{opacity:1}
.w .body{padding:4px 18px 14px;flex:1;min-height:0;font-size:16px;line-height:1.5}
.big{font-size:44px;font-weight:900;line-height:1.1}.mid{font-size:26px}.sm{font-size:13px;color:var(--sub);letter-spacing:1px}
.row{display:flex;justify-content:space-between;gap:10px}.acc{color:var(--acc);font-weight:900}svg.g{width:100%;display:block}
.track{height:10px;border-radius:5px;background:var(--track);margin:4px 0;overflow:hidden}.track i{display:block;height:100%;border-radius:5px;background:var(--acc)}
#start{position:fixed;left:44px;bottom:14px;z-index:45}#ubtn{font:30px "DejaVu Sans Mono",monospace;color:var(--sub);cursor:pointer;padding:6px 14px;border-radius:16px}#ubtn:hover{background:var(--panel);color:var(--text)}
#menu{display:none;position:absolute;bottom:58px;left:0;width:340px;max-height:70vh;background:var(--bg);border:1.5px solid var(--pstroke);border-radius:22px;padding:14px;box-shadow:0 0 12px rgba(0,0,0,.3);flex-direction:column}#menu.open{display:flex}
#menu input{font:inherit;font-size:16px;color:var(--text);background:var(--panel);border:1.5px solid var(--pstroke);border-radius:14px;padding:9px 12px;outline:none;user-select:text}
#apps{overflow:auto;margin:10px 0;flex:1}#apps div{padding:7px 10px;border-radius:10px;cursor:pointer;font-size:17px}#apps div:hover{background:var(--panel)}#apps h4{margin:10px 6px 2px;font-size:12px;letter-spacing:3px;color:var(--sub);font-weight:400}
#pw button{font:inherit;font-size:14px;color:var(--text);background:var(--panel);border:1.5px solid var(--pstroke);border-radius:12px;padding:6px 10px;margin-right:6px;cursor:pointer}
#tab{position:fixed;left:0;top:50%;transform:translateY(-50%);width:26px;height:90px;border-radius:0 16px 16px 0;background:var(--panel);border:1.5px solid var(--pstroke);border-left:0;color:var(--sub);display:flex;align-items:center;justify-content:center;cursor:pointer;z-index:50;font-size:18px}
#side{position:fixed;left:-300px;top:0;bottom:0;width:270px;background:var(--bg);border-right:1.5px solid var(--pstroke);z-index:40;padding:20px;transition:left .2s;overflow:auto;box-shadow:0 0 12px rgba(0,0,0,.3)}
#side.open{left:0}#side h3{margin:0 0 10px;font-size:15px;letter-spacing:3px;color:var(--sub)}
#side label{display:flex;align-items:center;gap:10px;padding:7px 4px;cursor:pointer;font-size:16px}#side input{accent-color:var(--acc);width:18px;height:18px}
#side button{font:inherit;color:var(--text);background:var(--panel);border:1.5px solid var(--pstroke);border-radius:14px;padding:7px 12px;margin:3px 3px 3px 0;cursor:pointer}#side button.on{background:var(--acc);color:#2a1b14}
.hint{font-size:13px;color:var(--sub);margin-top:8px}
.mt{font:inherit;font-size:13px;color:var(--text);background:transparent;border:1.5px solid var(--stroke,rgba(128,128,128,.4));border-radius:12px;padding:3px 10px;cursor:pointer}.mt.on{background:var(--acc);color:#2a1b14}</style></head><body>
<svg id="bgart" viewBox="0 0 1920 1080" preserveAspectRatio="xMidYMid slice"></svg>
<div id="desk"></div><div id="tab" title="Widgets">&#9776;</div>
<div id="start"><div id="menu"><input id="q" placeholder="Search apps…" autocomplete="off"><div id="apps"></div><div id="pw"><button data-p="logout">Log out</button><button data-p="reboot">Restart</button><button data-p="shutdown">Shut down</button></div></div><div id="ubtn">User: <span id="uname">…</span></div></div>
<div id="side"><h3>WIDGETS</h3><div id="list"></div><h3 style="margin-top:18px">LOOK</h3><div id="modes"></div><h3 style="margin-top:18px">LAYOUT</h3><button id="openset" onclick="fetchP('/api/action',{method:'POST',body:'settings'})">Open Lab Settings</button><button id="reset">Reset positions</button><button id="all">Show all</button><button id="none">Hide all</button><div class="hint">Drag a widget by its title. Click &times; to close it, or tick it here to bring it back.</div></div>
<script>
const TH={
night:{bg:['#2a1b14','#3a2518'],panel:'rgba(255,225,170,.08)',pstroke:'rgba(255,225,170,.18)',text:'#f0e0bd',sub:'#c9a77a',acc:'#e0873a',acc2:'#e7c06a',track:'rgba(255,225,170,.12)',halo:'#d27a35',word:'#f0e0bd',ho:.5},
day:{bg:['#f3e6c6','#ead7ac'],panel:'rgba(122,59,20,.07)',pstroke:'rgba(122,59,20,.15)',text:'#4a2a16',sub:'#8a5a38',acc:'#d27a35',acc2:'#d9a93f',track:'rgba(122,59,20,.12)',halo:'#e7a947',word:'#7a3b14',ho:.5},
dusk:{bg:['#3d2016','#8a4426','#d98a3e','#ecc275'],panel:'rgba(60,25,10,.28)',pstroke:'rgba(255,235,200,.22)',text:'#fbeed0',sub:'#f0d6a4',acc:'#fff0cf',acc2:'#f2b45a',track:'rgba(255,235,200,.2)',halo:'#fff0cf',word:'#fff6e0',ho:.18}};
let D=null,layout={},curTheme='';
function theme(cfg){let m=cfg.mode;if(!TH[m]){const h=new Date().getHours(),a=+cfg.dawn,d=+cfg.day,u=+cfg.dusk,n=+cfg.night;m=(h>=d&&h<u)?'day':((h>=a&&h<d)||(h>=u&&h<n))?'dusk':'night'}
 const key=m+'|'+cfg.mode;if(key===curTheme)return;curTheme=key;const t=TH[m],r=document.documentElement.style;
 r.setProperty('--bg','linear-gradient('+t.bg.join(',')+')');for(const k in t)if(k!=='bg')r.setProperty('--'+k,t[k]);art(t);
 document.querySelectorAll('#modes button').forEach(b=>b.classList.toggle('on',b.dataset.m===cfg.mode))}
function art(t){document.getElementById('bgart').innerHTML=`<defs><filter id="sh" x="-100%" y="-100%" width="300%" height="300%"><feGaussianBlur stdDeviation="60"/></filter><clipPath id="cL"><circle r="210"/></clipPath><mask id="mL"><rect x="-220" y="-220" width="440" height="440" fill="#fff"/><g fill="#000"><rect x="-220" y="-150" width="440" height="14"/><rect x="-220" y="-95" width="440" height="14"/><rect x="-220" y="95" width="440" height="14"/><rect x="-220" y="150" width="440" height="14"/><circle r="62"/><rect x="-220" y="-14" width="440" height="14"/></g></mask><linearGradient id="gL" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8a4a22"/><stop offset=".45" stop-color="#d27a35"/><stop offset=".8" stop-color="#e7a947"/><stop offset="1" stop-color="#e3c26a"/></linearGradient></defs>
<circle cx="960" cy="500" r="330" fill="${t.halo}" filter="url(#sh)" opacity="${t.ho}"/><g transform="translate(960,500)"><g clip-path="url(#cL)" mask="url(#mL)"><rect x="-220" y="-220" width="440" height="440" fill="url(#gL)"/></g></g>
<text x="960" y="865" font-family="Gelasio,Georgia,DejaVu Serif,serif" font-size="120" font-weight="900" text-anchor="middle" fill="${t.word}">aperture</text><text x="960" y="925" font-family="Gelasio,Georgia,DejaVu Serif,serif" font-size="34" font-style="italic" text-anchor="middle" fill="${t.sub}" letter-spacing="26">LABORATORIES</text>`}
const fetchP=(u,o)=>fetch(u,{...o,headers:{'X-Lab':'1'}});
// ---------- helpers
const f0=n=>n==null?'—':Math.round(n),f1=n=>n==null?'—':(+n).toFixed(1);
const rate=b=>b>=1048576?(b/1048576).toFixed(1)+' MB/s':b>=1024?(b/1024).toFixed(0)+' KB/s':Math.round(b)+' B/s';
const bar=(v,c)=>`<div class="track"><i style="width:${Math.max(2,Math.min(100,v||0))}%;${c?'background:'+c:''}"></i></div>`;
function spark(a,h,cols,mx){h=h||60;const W=300;if(!a||!a.length)return'';let m=mx||Math.max(1,...a.flat());
 return `<svg class="g" viewBox="0 0 ${W} ${h}" preserveAspectRatio="none" style="height:${h}px">`+(Array.isArray(a[0])?a:[a]).map((s,i)=>{const p=s.map((v,j)=>`${(j/(Math.max(1,s.length-1))*W).toFixed(1)},${(h-2-(v||0)/m*(h-6)).toFixed(1)}`).join(' ');return `<polyline points="${p}" fill="none" stroke="${cols[i]}" stroke-width="2.5" stroke-linejoin="round" stroke-linecap="round"/>`}).join('')+'</svg>'}
const C=()=>({a:getComputedStyle(document.documentElement).getPropertyValue('--acc').trim(),b:getComputedStyle(document.documentElement).getPropertyValue('--acc2').trim()});
const WC={0:'Clear',1:'Mostly clear',2:'Partly cloudy',3:'Overcast',45:'Fog',48:'Fog',51:'Drizzle',53:'Drizzle',55:'Drizzle',61:'Rain',63:'Rain',65:'Heavy rain',71:'Snow',73:'Snow',75:'Heavy snow',80:'Showers',81:'Showers',82:'Heavy showers',95:'Thunderstorm'};
const hm=s=>s?new Date(s).toLocaleTimeString([], {hour:'numeric',minute:'2-digit'}):'—';
const noWx='<div class="sm">Waiting for weather… (needs internet)</div>';
// ---------- widgets  (render gets d = data)
const WIDGETS=[
{id:'system',title:'System',x:40,y:30,w:400,h:200,on:1,r:d=>`<div class="acc">${d.cur.host||''}</div><div>Tailscale &nbsp;<b>${d.cur.ts||'offline'}</b></div><div>Uptime &nbsp;<b>${up(d.cur.uptime)}</b></div><div>Load &nbsp;<b>${f1(d.cur.load)}</b></div>`},
{id:'clock',title:'',x:1650,y:30,w:230,h:112,on:1,r:d=>{const n=new Date();return `<div style="text-align:center;margin-top:4px"><div class="big" style="font-size:46px">${n.toLocaleTimeString([], {hour:'2-digit',minute:'2-digit',hour12:false})}</div><div style="font-size:18px;color:var(--sub)">${n.toLocaleDateString([], {weekday:'short',day:'2-digit',month:'short',year:'numeric'})}</div></div>`}},
{id:'cpu',title:'CPU cores',x:1010,y:30,w:410,h:200,on:1,r:d=>{const k=d.cur.cores||[],c=C();return `<svg class="g" viewBox="0 0 300 120" style="height:120px">`+k.map((v,i)=>{const w=300/k.length;const h=Math.max(8,v*1.1);return `<rect x="${i*w+6}" y="${115-h}" width="${w-12}" height="${h}" rx="8" fill="${i%2?c.a:c.b}" opacity=".9"/>`}).join('')+`</svg><div class="row sm"><span>${k.map((v,i)=>'C'+i).join(' ')}</span><span>total ${f0(d.cur.cpu)}%</span></div>`}},
{id:'temps',title:'Vitals',x:1440,y:30,w:190,h:200,on:1,r:d=>`<div class="mid"><b>${f0(d.cur.cpu)}%</b> <span class="sm">CPU</span></div><div class="mid"><b>${f0(d.cur.mem)}%</b> <span class="sm">MEM</span></div><div class="mid"><b>${f0(d.cur.temp)}°</b> <span class="sm">TEMP</span></div>`},
{id:'weather',title:'Weather',x:40,y:260,w:400,h:250,on:1,r:d=>{const w=d.weather;if(!w)return noWx;const c=w.current,h=w.hourly.temperature_2m,dl=w.daily,cl=C();return `<div class="sm">${w.place}</div><div class="row"><span class="big">${f0(c.temperature_2m)}°F</span><span style="text-align:right">${WC[c.weather_code]||''}<br><span class="sm">wind ${f0(c.wind_speed_10m)} mph</span></span></div>${spark(h,50,[cl.a])}<div class="sm">next 24 hours</div><div class="row sm">${dl.time.slice(1,5).map((t,i)=>`<span>${new Date(t+'T12:00').toLocaleDateString([], {weekday:'short'})}<br><b style="color:var(--text)">${f0(dl.temperature_2m_max[i+1])}/${f0(dl.temperature_2m_min[i+1])}°</b></span>`).join('')}</div>`}},
{id:'wx2',title:'Air & sun',x:40,y:530,w:400,h:160,on:1,r:d=>{const w=d.weather;if(!w)return noWx;const c=w.current,dl=w.daily;return `<div class="row"><span>Humidity</span><b>${f0(c.relative_humidity_2m)}%</b></div><div class="row"><span>Dew point</span><b>${f0(c.dew_point_2m)}°F</b></div><div class="row"><span>UV index</span><b>${f1(c.uv_index)} <span class="sm">(max ${f1(dl.uv_index_max[0])})</span></b></div><div class="row"><span>Sunrise / Sunset</span><b>${hm(dl.sunrise[0])} / ${hm(dl.sunset[0])}</b></div>`}},
{id:'pressure',title:'Pressure',x:40,y:710,w:400,h:150,on:1,r:d=>{const w=d.weather;if(!w)return noWx;const p=w.hourly.pressure_msl,cl=C(),now=w.current.pressure_msl,tr=p[p.length-1]-p[0];return `<div class="row"><span class="big" style="font-size:34px">${(now*0.02953).toFixed(2)} inHg</span><span class="sm">${tr>1?'rising':tr<-1?'falling':'steady'}</span></div>${spark(p.map(v=>v-Math.min(...p)),45,[cl.b],Math.max(1,Math.max(...p)-Math.min(...p)))}`}},
{id:'power',title:'Power & cooling',x:40,y:870,w:400,h:130,on:1,r:d=>{const c=d.cur;return `<div class="row"><span class="big" style="font-size:38px">${c.watts!=null?f1(c.watts)+' W':'— W'}</span><span class="big" style="font-size:38px">${c.fan!=null?c.fan+' rpm':'no fan data'}</span></div>${spark(d.hist.watts,40,[C().a])}`}},
{id:'network',title:'Network',x:1480,y:260,w:400,h:170,on:1,r:d=>`<div class="row"><span>↓ <b>${rate(d.cur.down||0)}</b></span><span>↑ <b>${rate(d.cur.up_||0)}</b></span></div>${spark([d.hist.down,d.hist.up_],70,[C().a,C().b])}`},
{id:'disk',title:'Disk',x:1480,y:450,w:400,h:170,on:1,r:d=>`<div class="row"><span>Read <b>${rate(d.cur.dread||0)}</b></span><span>Write <b>${rate(d.cur.dwrite||0)}</b></span></div>${spark([d.hist.dread,d.hist.dwrite],55,[C().a,C().b])}<div class="row sm"><span>${f0(d.cur.diskPct)}% used</span><span>${f0(d.cur.diskFreeGB)} GB free</span></div>`},
{id:'memory',title:'Memory & commit',x:1480,y:640,w:400,h:130,on:1,r:d=>{const c=d.cur;return `<div class="row"><span>RAM</span><b>${f1(c.memUsedGB)} / ${f1(c.memTotalGB)} GB</b></div>${bar(c.mem)}<div class="row"><span>Committed</span><b>${f1(c.commitGB)} GB</b></div>${bar(100*c.commitGB/Math.max(.1,c.commitLimitGB),'var(--acc2)')}`}},
{id:'top',title:'Top apps (memory)',x:1480,y:790,w:400,h:210,on:1,r:d=>(d.top||[]).map(t=>`<div class="row"><span>${t[0]}</span><b>${f0(t[1])} MB</b></div>`).join('')},
{id:'ping',title:'Ping & jitter',x:470,y:260,w:330,h:150,on:0,r:d=>{const p=(d.ping||[]).filter(x=>x!=null),av=p.length?p.reduce((a,b)=>a+b,0)/p.length:null,j=p.length>1?p.slice(1).reduce((a,b,i)=>a+Math.abs(b-p[i]),0)/(p.length-1):null;return `<div class="row"><span>Ping <b>${f0(p[p.length-1])} ms</b></span><span>Jitter <b>${f1(j)} ms</b></span></div>${spark(p,55,[C().a])}`}},
{id:'mail',title:'Mail',x:830,y:260,w:300,h:150,on:0,r:d=>{const t=(d.cfg&&d.cfg.mail_tab)||'gmail';return `<div class="row"><span><button class="mt ${t==='gmail'?'on':''}" onclick="mailTab('gmail')">Gmail</button> <button class="mt ${t==='proton'?'on':''}" onclick="mailTab('proton')">Proton Mail</button></span></div><div class="sm" style="margin:6px 0">Opens your ${t==='gmail'?'Gmail':'Proton Mail'} inbox in Vivaldi.</div><button class="mt" onclick="mailOpen()">Open inbox</button>`}},
{id:'claude',title:'Claude usage',x:830,y:410,w:300,h:130,on:0,r:d=>'<div class="sm">Not connected yet. Needs a Claude usage key.</div>'}];
const mailTab=async t=>{await fetchP('/api/set',{method:'POST',body:JSON.stringify({k:'mail_tab',v:t})});tick()};const mailOpen=()=>fetchP('/api/mail',{method:'POST',body:''});
function up(s){s=s||0;const d=Math.floor(s/86400),h=Math.floor(s%86400/3600),m=Math.floor(s%3600/60);return d?`${d}d ${h}h`:`${h}h ${m}m`}
// ---------- build
const desk=document.getElementById('desk'),els={};let z=10,saveT;
function save(){clearTimeout(saveT);saveT=setTimeout(()=>fetchP('/api/layout',{method:'POST',body:JSON.stringify(layout)}),400)}
function pos(w){const L=layout[w.id]||{};return {x:L.x??w.x,y:L.y??w.y,w:L.w??w.w,h:L.h??w.h,on:L.on??w.on}}
function place(w){const p=pos(w),e=els[w.id];e.style.cssText=`left:${p.x}px;top:${p.y}px;width:${p.w}px;height:${p.h}px;display:${p.on?'flex':'none'};z-index:${e.style.zIndex||5}`}
function build(){desk.innerHTML='';WIDGETS.forEach(w=>{const e=document.createElement('div');e.className='w';e.innerHTML=`<div class="bar"><span>${w.title}</span><span class="x" title="Close">&times;</span></div><div class="body"></div>`;if(!w.title)e.querySelector('.bar').style.padding='6px 14px 0';
 els[w.id]=e;desk.appendChild(e);place(w);
 e.querySelector('.x').onclick=()=>{layout[w.id]={...pos(w),on:0};place(w);save();lst()};
 e.querySelector('.bar').onpointerdown=ev=>{if(ev.target.className==='x')return;const p=pos(w),sx=ev.clientX,sy=ev.clientY;e.style.zIndex=++z;e.setPointerCapture(ev.pointerId);
  const mv=m=>{layout[w.id]={...pos(w),x:Math.max(0,p.x+m.clientX-sx),y:Math.max(0,p.y+m.clientY-sy)};e.style.left=layout[w.id].x+'px';e.style.top=layout[w.id].y+'px'};
  const upf=()=>{e.removeEventListener('pointermove',mv);e.removeEventListener('pointerup',upf);save()};e.addEventListener('pointermove',mv);e.addEventListener('pointerup',upf)}})}
function lst(){document.getElementById('list').innerHTML=WIDGETS.filter(w=>w.title).map(w=>`<label><input type="checkbox" data-id="${w.id}" ${pos(w).on?'checked':''}>${w.title}</label>`).join('');
 document.querySelectorAll('#list input').forEach(i=>i.onchange=()=>{const w=WIDGETS.find(x=>x.id===i.dataset.id);layout[w.id]={...pos(w),on:i.checked?1:0};place(w);save()})}
document.getElementById('modes').innerHTML=['auto','day','dusk','night'].map(m=>`<button data-m="${m}">${m[0].toUpperCase()+m.slice(1)}</button>`).join('');
document.querySelectorAll('#modes button').forEach(b=>b.onclick=async()=>{await fetchP('/api/mode',{method:'POST',body:b.dataset.m});tick()});
document.getElementById('tab').onclick=()=>document.getElementById('side').classList.toggle('open');
document.addEventListener('keydown',e=>{if(e.key==='Escape')document.getElementById('side').classList.remove('open')});
document.getElementById('reset').onclick=async()=>{layout={};await fetchP('/api/reset',{method:'POST'});build();lst()};
document.getElementById('all').onclick=()=>{WIDGETS.forEach(w=>layout[w.id]={...pos(w),on:1});WIDGETS.forEach(place);lst();save()};
document.getElementById('none').onclick=()=>{WIDGETS.forEach(w=>layout[w.id]={...pos(w),on:0});WIDGETS.forEach(place);lst();save()};
let first=1;
async function tick(){try{D=await (await fetch('/api/stats')).json()}catch(e){return}
 if(first){first=0;layout=D.layout||{};build();lst()}
 theme(D.cfg);document.getElementById('uname').textContent=D.cur.user||'';
 WIDGETS.forEach(w=>{if(pos(w).on)els[w.id].querySelector('.body').innerHTML=w.r(D)})}
let APPS=[];
async function loadApps(){try{APPS=await (await fetch('/api/apps')).json()}catch(e){}drawApps()}
function drawApps(){const q=document.getElementById('q').value.toLowerCase(),g={};APPS.filter(a=>a.name.toLowerCase().includes(q)).forEach(a=>(g[a.cat]=g[a.cat]||[]).push(a));
 document.getElementById('apps').innerHTML=Object.keys(g).sort().map(c=>`<h4>${c.toUpperCase()}</h4>`+g[c].map(a=>`<div data-id="${a.id}">${a.name}</div>`).join('')).join('');
 document.querySelectorAll('#apps div').forEach(d=>d.onclick=()=>{fetchP('/api/launch',{method:'POST',body:d.dataset.id});document.getElementById('menu').classList.remove('open')})}
document.getElementById('ubtn').onclick=()=>{fetchP('/api/menu',{method:'POST',body:'apps'});return;const m=document.getElementById('menu');m.classList.toggle('open');if(m.classList.contains('open')){loadApps();document.getElementById('q').value='';document.getElementById('q').focus()}};
document.getElementById('q').oninput=drawApps;
document.querySelectorAll('#pw button').forEach(b=>b.onclick=()=>{if(confirm(b.textContent+'?'))fetchP('/api/power',{method:'POST',body:b.dataset.p})});
document.addEventListener('pointerdown',e=>{if(!e.target.closest('#start'))document.getElementById('menu').classList.remove('open')});
tick();setInterval(tick,3000);
</script></body></html>
LDHTML
cat > ~/.local/share/retro-lab/settings.html <<'LSET'
<!doctype html><html><head><meta charset="utf-8"><title>Lab Settings</title><meta name="viewport" content="width=device-width,initial-scale=1">
<style>
:root{--bg:linear-gradient(#2a1b14,#3a2518);--panel:rgba(255,225,170,.08);--pstroke:rgba(255,225,170,.18);--text:#f0e0bd;--sub:#c9a77a;--acc:#e0873a;--acc2:#e7c06a;--track:rgba(255,225,170,.12)}
*{box-sizing:border-box}html,body{margin:0;min-height:100%;background:var(--bg);background-attachment:fixed;color:var(--text);font-family:Gelasio,Georgia,"DejaVu Serif",serif}
.wrap{max-width:1180px;margin:0 auto;padding:28px 20px 60px}.layout{display:flex;gap:18px;align-items:flex-start}.nav{display:flex;flex-direction:column;gap:6px;min-width:190px;position:sticky;top:16px}.nav button{text-align:left;border-radius:18px}.main{flex:1;min-width:0}pre{white-space:pre-wrap;font:13px/1.4 monospace;margin:6px 0;color:var(--sub)}.net{display:flex;justify-content:space-between;align-items:center;gap:8px;margin:6px 0}h1{margin:0 0 4px;font-size:34px}.sub{color:var(--sub);margin-bottom:22px}
.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(380px,1fr));gap:16px}
.card{background:var(--panel);border:1.5px solid var(--pstroke);border-radius:26px;padding:18px 22px}.card h2{margin:0 0 10px;font-size:14px;letter-spacing:3px;color:var(--sub);font-weight:400;text-transform:uppercase}
.row{display:flex;justify-content:space-between;align-items:center;gap:12px;margin:9px 0;flex-wrap:wrap}.lbl{font-size:16px}.note{font-size:13px;color:var(--sub);margin-top:6px}
button,select,input{font:inherit;color:var(--text);background:var(--panel);border:1.5px solid var(--pstroke);border-radius:14px;padding:7px 13px;cursor:pointer}
button:hover{border-color:var(--acc)}button.on{background:var(--acc);color:#2a1b14;border-color:var(--acc)}input{cursor:text;width:190px}input[type=range]{width:170px;padding:0}
select option{background:#3a2518;color:#f0e0bd}.ok{color:var(--acc2)}.toast{position:fixed;bottom:18px;left:50%;transform:translateX(-50%);background:var(--acc);color:#2a1b14;padding:8px 18px;border-radius:18px;opacity:0;transition:opacity .2s}.toast.show{opacity:1}
</style></head><body><div class="wrap"><h1>Lab Settings</h1><div class="sub">Everything for your Aperture lab Pi in one place.</div><div class="layout"><div class="nav" id="nav"></div><div class="main"><div class="grid" id="g"></div></div></div></div><div class="toast" id="t"></div>
<script>
const TH={night:{bg:['#2a1b14','#3a2518'],panel:'rgba(255,225,170,.08)',pstroke:'rgba(255,225,170,.18)',text:'#f0e0bd',sub:'#c9a77a',acc:'#e0873a',acc2:'#e7c06a',track:'rgba(255,225,170,.12)'},day:{bg:['#f3e6c6','#ead7ac'],panel:'rgba(122,59,20,.07)',pstroke:'rgba(122,59,20,.15)',text:'#4a2a16',sub:'#8a5a38',acc:'#d27a35',acc2:'#d9a93f',track:'rgba(122,59,20,.12)'},dusk:{bg:['#3d2016','#8a4426','#d98a3e','#ecc275'],panel:'rgba(60,25,10,.28)',pstroke:'rgba(255,235,200,.22)',text:'#fbeed0',sub:'#f0d6a4',acc:'#fff0cf',acc2:'#f2b45a',track:'rgba(255,235,200,.2)'}};
function theme(c){let m=c.mode;if(!TH[m]){const h=new Date().getHours(),a=+c.dawn,d=+c.day,u=+c.dusk,n=+c.night;m=(h>=d&&h<u)?'day':((h>=a&&h<d)||(h>=u&&h<n))?'dusk':'night'}const t=TH[m],r=document.documentElement.style;r.setProperty('--bg','linear-gradient('+t.bg.join(',')+')');for(const k in t)if(k!=='bg')r.setProperty('--'+k,t[k])}
const P=(u,b)=>fetch(u,{method:'POST',headers:{'X-Lab':'1'},body:b});
const toast=m=>{const e=document.getElementById('t');e.textContent=m;e.classList.add('show');setTimeout(()=>e.classList.remove('show'),1800)};
async function set(k,v,msg){await P('/api/set',JSON.stringify({k,v}));toast(msg||'Saved');load()}
async function act(a,msg){await P('/api/action',a);toast(msg||'Done');setTimeout(load,1500)}
const seg=(k,opts,cur)=>opts.map(o=>`<button class="${cur===o[0]?'on':''}" onclick="set('${k}','${o[0]}')">${o[1]}</button>`).join(' ');
const fld=(k,l,v,ph)=>`<div class="row"><span class="lbl">${l}</span><input id="f_${k}" value="${v||''}" placeholder="${ph||''}"></div>`;
async function saveConn(){for(const k of ['server_name','server_lan','server_share','port_jellyfin','port_seerr','pc_name','pc_mac','server_user']){const v=document.getElementById('f_'+k).value.trim();await P('/api/set',JSON.stringify({k,v}))}await act('rebuild','Saved. Start-menu shortcuts rebuilt.')}
async function saveHours(){for(const k of ['dawn','day','dusk','night']){await P('/api/set',JSON.stringify({k,v:document.getElementById('h_'+k).value}))}toast('Schedule saved');load()}
const mkCards=(s,c,sp,so)=>[`<div class="card"><h2>Look</h2><div class="row"><span class="lbl">Theme</span><span>${seg('mode',[['auto','Auto'],['day','Day'],['dusk','Dusk'],['night','Night']],c.mode)}</span></div>
<div class="row"><span class="lbl">Auto schedule (24h)</span><span>dawn <input id="h_dawn" style="width:55px" value="${c.dawn}"> day <input id="h_day" style="width:55px" value="${c.day}"> dusk <input id="h_dusk" style="width:55px" value="${c.dusk}"> night <input id="h_night" style="width:55px" value="${c.night}"> <button onclick="saveHours()">Save</button></span></div>
<div class="row"><span class="lbl">Startup animation</span><span>${seg('splash',[['on','On'],['off','Off']],sp?'on':'off')} <button onclick="act('replay','Playing…')">Replay</button></span></div></div>
`,`<div class="card"><h2>Sounds</h2><div class="row"><span class="lbl">Sounds</span><span>${seg('sounds',[['on','On'],['off','Off']],so?'on':'off')}</span></div>
<div class="row"><span class="lbl">Style</span><span>${seg('sound_style',[['a-warm-synth','Warm synth'],['b-lab-pa-chime','Lab chime'],['c-teletype-beeps','Teletype']],c.sound_style)}</span></div>
<div class="row"><span class="lbl">Volume</span><span><input type="range" min="10" max="100" value="${c.sound_volume||100}" onchange="set('sound_volume',this.value)"> <button onclick="act('chime','Playing…')">Test</button></span></div></div>
`,`<div class="card"><h2>Security</h2><div class="row"><span class="lbl">Login</span><span>${s.autologin?'<span class="ok">Automatic (no password)</span>':'<span class="ok">Password required</span>'}</span></div>
<div class="row"><span></span><span><button onclick="act('login_password')">Require password</button> <button onclick="act('login_auto')">Auto-login</button></span></div>
<div class="row"><span class="lbl">Lock screen after</span><span><select onchange="act(this.value,'Lock time set')">${[['lock_off','Never'],['lock_5','5 min'],['lock_10','10 min'],['lock_15','15 min'],['lock_30','30 min'],['lock_60','60 min']].map(o=>`<option value="${o[0]}" ${(o[0]==='lock_off'&&!s.lock_min)||o[0]==='lock_'+s.lock_min?'selected':''}>${o[1]}</option>`).join('')}</select></span></div>
<div class="row"><span class="lbl">Firewall</span><span class="${s.firewall?'ok':''}">${s.firewall?'On (Tailscale only)':'Off'}</span></div><div class="row"><span class="lbl">Automatic security updates</span><span class="${s.autoupdates?'ok':''}">${s.autoupdates?'On':'Off'}</span></div>
<div class="row"><span></span><button onclick="act('secure')">Run travel security setup</button></div></div>
`,`<div class="card"><h2>Connections</h2>${fld('server_name','Home server (Tailscale name)',c.server_name)}${fld('server_lan','Home server (home address)',c.server_lan)}${fld('server_share','Shared folder name',c.server_share)}${fld('server_user','Server login name',c.server_user)}${fld('port_jellyfin','Jellyfin port',c.port_jellyfin)}${fld('port_seerr','Seerr port',c.port_seerr)}${fld('pc_name','My PC (Tailscale name)',c.pc_name)}${fld('pc_mac','My PC MAC address',c.pc_mac,'AA-BB-CC-DD-EE-FF')}
<div class="row"><span class="lbl">Tailscale</span><span class="${s.tailscale?'ok':''}">${s.tailscale?'Connected '+s.tailscale:'Not connected'}</span></div>
<div class="row"><span><button onclick="saveConn()">Save and update menu</button></span><span><button onclick="act('connect')">Guided setup</button> <button onclick="act('wake_setup')">Set up Wake My PC</button></span></div><div class="note">Saved only on this Pi.</div></div>
`,`<div class="card"><h2>Mail card</h2><div class="row"><span class="lbl">Inbox the Mail card opens</span><span>${seg('mail_tab',[['gmail','Gmail'],['proton','Proton Mail']],c.mail_tab||'gmail')}</span></div><div class="note">Turn the card on with the ☰ tab in Lab Desk. It opens your inbox in Vivaldi; unread counts may come later.</div></div>
`,`<div class="card"><h2>Taskbar and widgets</h2><div class="row"><span class="lbl">Taskbar</span><span><button class="${s.panel==='lab'?'on':''}" onclick="act('panel_lab','Lab taskbar on')">Lab</button> <button class="${s.panel==='stock'?'on':''}" onclick="act('panel_stock','Stock taskbar on')">Stock Pi</button></span></div>
<div class="row"><span class="lbl">Widgets</span><span><button onclick="P('/api/reset','').then(()=>toast('Widget positions reset'))">Reset positions</button></span></div><div class="note">Show or hide individual widgets with the ☰ tab on the left edge of Lab Desk.</div></div>
`,`<div class="card"><h2>Updates and fixes</h2><div class="row"><span class="lbl">Lab theme</span><button onclick="act('update')">Check for updates</button></div><div class="row"><span class="lbl">Whole system</span><button onclick="act('system_update')">Update everything</button></div><div class="row"><span class="lbl">Vivaldi crashes on start?</span><button onclick="act('fix_vivaldi')">Apply fix</button></div></div>
`,`<div class="card"><h2>Advanced (stock Pi settings, rarely needed)</h2><div class="row"><span class="lbl">Display, Wi-Fi, Bluetooth, audio devices, keyboard…</span><button onclick="act('control_centre','Opening…')">Open Control Centre</button></div><div class="note">The Control Centre can also switch auto-login on or off.</div></div>`];
const PAGES=[['look','Look & sound'],['network','Network'],['display','Display'],['audio','Sound & keyboard'],['time','Date & time'],['accounts','Accounts & security'],['connections','Home server & PC'],['storage','Storage & power'],['desktop','Desktop'],['updates','Updates & about']];
let page=(()=>{try{return localStorage.getItem('lsPage')||'look'}catch(e){return 'look'}})();
const S=async(a,x)=>{const r=await (await P('/api/sysact',JSON.stringify({a,...x}))).json();toast((r.out||'Done').slice(0,80));return r.out};
const W=async w=>await (await fetch('/api/sys?w='+w)).json();
const esc=t=>String(t).replace(/[&<>"']/g,m=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[m]));
function go(p){page=p;try{localStorage.setItem('lsPage',p)}catch(e){}load(true)}
async function wifiGo(i){const n=window._nets[i];await S('wifi_connect',{ssid:n.ssid,pw:(document.getElementById('wpw')||{}).value||''});go('network')}
async function wifiForget(i){await S('wifi_forget',{ssid:window._nets[i].ssid});go('network')}
async function btDo(a,m){await S(a,{mac:m});setTimeout(()=>go('network'),1200)}
async function dispApply(o){const m=document.getElementById('m_'+o).value,sc=document.getElementById('s_'+o).value;await S('display',{out:o,mode:m,scale:sc})}
async function tzSet(){await S('tz',{v:document.getElementById('tzsel').value})}
async function kbSet(){await S('kb',{v:document.getElementById('kb').value.trim()})}
async function hostSet(){await S('hostname',{v:document.getElementById('hn').value.trim()})}
async function pwr(x){if(confirm(x+'?'))await P('/api/power',x)}
async function extra(pg,s,c,CARDS){
 if(pg==='network'){const w=await W('wifi'),b=await W('bt');window._nets=w.nets;
  return `<div class="card"><h2>Wi-Fi</h2><div class="row"><span class="lbl">Wi-Fi radio</span><span><button class="${w.radio?'on':''}" onclick="S('wifi_radio',{v:'on'}).then(()=>go('network'))">On</button> <button class="${w.radio?'':'on'}" onclick="S('wifi_radio',{v:'off'}).then(()=>go('network'))">Off</button></span></div><div class="row"><span class="lbl">Password for a new network</span><input id="wpw" type="password" placeholder="leave empty if open"></div>${w.nets.map((n,i)=>`<div class="net"><span>${n.use?'&#9679; ':''}${esc(n.ssid)} <span class="note">${n.sig}% ${n.sec?'&#128274;':''}</span></span><span>${n.use?'<span class="ok">connected</span>':`<button onclick="wifiGo(${i})">Connect</button>`} <button onclick="wifiForget(${i})">Forget</button></span></div>`).join('')||'<div class="note">No networks found. Wired connections work automatically.</div>'}<div class="row"><button onclick="go('network')">Refresh</button></div></div>
<div class="card"><h2>Bluetooth</h2>${b.present?`<div class="row"><span class="lbl">Bluetooth</span><span><button class="${b.powered?'on':''}" onclick="S('bt_power',{v:'on'}).then(()=>go('network'))">On</button> <button class="${b.powered?'':'on'}" onclick="S('bt_power',{v:'off'}).then(()=>go('network'))">Off</button> <button onclick="S('bt_scan',{}).then(()=>setTimeout(()=>go('network'),11000))">Scan for devices</button></span></div>${b.devices.map(d=>`<div class="net"><span>${esc(d.name)} ${d.connected?'<span class="ok">connected</span>':''}</span><span>${d.connected?`<button onclick="btDo('bt_disconnect','${d.mac}')">Disconnect</button>`:`<button onclick="btDo('bt_pair','${d.mac}')">Pair / connect</button>`} <button onclick="btDo('bt_remove','${d.mac}')">Remove</button></span></div>`).join('')||'<div class="note">No devices yet. Put your device in pairing mode and press Scan.</div>'}`:'<div class="note">No Bluetooth adapter found.</div>'}</div>
<div class="card"><h2>Tailscale and VPN</h2><div class="row"><span class="lbl">Tailscale</span><span class="${s.tailscale?'ok':''}">${s.tailscale?'Connected '+s.tailscale:'Not connected'}</span></div><div class="row"><span></span><span><button onclick="act('guided_tailscale')">Sign in / reconnect</button></span></div><div class="note">Proton VPN has its own app in the start menu.</div></div>`}
 if(pg==='display'){const d=await W('display');
  return d.outputs.map(o=>`<div class="card"><h2>Screen ${esc(o.name)}</h2><div class="row"><span class="lbl">Resolution and refresh</span><select id="m_${o.name}">${o.modes.map(m=>`<option ${m===o.cur?'selected':''}>${m}</option>`).join('')}</select></div><div class="row"><span class="lbl">Scale (text size)</span><select id="s_${o.name}">${['1','1.25','1.5','1.75','2'].map(v=>`<option ${parseFloat(v)===o.scale?'selected':''}>${v}</option>`).join('')}</select></div><div class="row"><span></span><button onclick="dispApply('${o.name}')">Apply</button></div><div class="note">If the screen goes blank, wait 10 seconds and restart the Pi. Your choice is remembered at every start.</div></div>`).join('')||'<div class="card"><div class="note">No display info available (this page needs the lab desktop running).</div></div>'}
 if(pg==='audio'){const a=await W('audio'),t=await W('time');
  return `<div class="card"><h2>Sound output</h2>${a.vol===null?'<div class="note">No sound device found.</div>':`<div class="row"><span class="lbl">Volume</span><span><input type="range" min="0" max="100" value="${a.vol}" onchange="S('vol',{v:this.value})"> <button class="${a.muted?'on':''}" onclick="S('mute',{}).then(()=>go('audio'))">Mute</button></span></div><div class="row"><span class="lbl">Play sound through</span><select onchange="S('sink',{v:this.value})">${a.sinks.map(k=>`<option ${k===a.default?'selected':''}>${esc(k)}</option>`).join('')}</select></div>`}<div class="row"><span class="lbl">Lab sounds (startup chime etc.)</span><span>see Look &amp; sound</span></div></div>
<div class="card"><h2>Keyboard</h2><div class="row"><span class="lbl">Layout code (us, gb, de, fr...)</span><span><input id="kb" style="width:80px" value="${esc((t.kb.match(/="?([a-z,]+)/)||[,'us'])[1])}"> <button onclick="kbSet()">Apply</button></span></div><div class="note">Opens a terminal for your password. Log out and back in afterwards.</div></div>`}
 if(pg==='time'){const t=await W('time');
  return `<div class="card"><h2>Date and time</h2><div class="row"><span class="lbl">Now</span><b>${esc(t.now)}</b></div><div class="row"><span class="lbl">Set automatically from the internet</span><span><button class="${t.ntp?'on':''}" onclick="S('ntp',{v:'on'})">On</button> <button class="${t.ntp?'':'on'}" onclick="S('ntp',{v:'off'})">Off</button></span></div><div class="row"><span class="lbl">Time zone</span><span><select id="tzsel">${t.zones.map(z=>`<option ${z===t.tz?'selected':''}>${esc(z)}</option>`).join('')}</select> <button onclick="tzSet()">Set</button></span></div><div class="note">Time zone and automatic time open a terminal for your password. Travelling? Change the time zone here.</div></div>`}
 if(pg==='accounts'){const a=await W('about');
  return `<div class="card"><h2>Account</h2><div class="row"><span class="lbl">Signed in as</span><b>${esc(a.user)}</b></div><div class="row"><span class="lbl">Change my password</span><button onclick="S('passwd',{})">Change password</button></div><div class="row"><span class="lbl">Computer name</span><span><input id="hn" style="width:150px" value="${esc(a.host)}"> <button onclick="hostSet()">Rename</button></span></div></div>`+CARDS[2]}
 if(pg==='storage'){const d=await W('storage');
  return `<div class="card"><h2>Storage</h2><pre>${esc(d.df)}</pre><pre>${esc(d.lsblk)}</pre><div class="note">Plug in a USB drive and it shows up here and in Files.</div></div><div class="card"><h2>Power</h2><div class="row"><button onclick="pwr('lock')">Lock screen</button><button onclick="pwr('logout')">Log out</button><button onclick="pwr('reboot')">Restart</button><button onclick="pwr('shutdown')">Shut down</button></div></div>`}
 if(pg==='updates'){const a=await W('about');
  return CARDS[6]+`<div class="card"><h2>About this computer</h2><div class="row"><span>System</span><b>${esc(a.os)}</b></div><div class="row"><span>Computer</span><b>${esc(a.model)}</b></div><div class="row"><span>Name</span><b>${esc(a.host)}</b></div><div class="row"><span>Kernel</span><b>${esc(a.kernel)}</b></div><div class="row"><span>Up</span><b>${esc(a.up)}</b></div><div class="row"><span>Temperature</span><b>${esc(a.temp)}</b></div><div class="row"><span>Power / throttling</span><b>${esc(a.throttled)}</b></div></div>`+CARDS[7]}
 return ''}
async function load(force){const s=await (await fetch('/api/settings')).json(),c=s.cfg;theme(c);
 document.getElementById('nav').innerHTML=PAGES.map(p=>`<button class="${p[0]===page?'on':''}" onclick="go('${p[0]}')">${p[1]}</button>`).join('');
 const sp=(c.splash||'off')==='on',so=(c.sounds||'on')==='on';
 const CARDS=mkCards(s,c,sp,so);
 let h='';
 if(page==='look')h=CARDS[0]+CARDS[1]+CARDS[4];
 else if(page==='connections')h=CARDS[3]+`<div class="card"><h2>Game library (home server)</h2><div class="row"><span class="lbl">Retro Console games from the server</span><span class="${s.roms?'ok':''}">${s.roms?'Connected':'Off'}</span></div><div class="row"><span></span><span><button onclick="act('roms_setup')">Set up / change login</button> <button onclick="act('roms_off')">Turn off</button></span></div><div class="note">Keeps your games in the roms folder on the server. Works at home and away through Tailscale. If the server is off, Retro Console uses this Pi's own ROMs folder.</div></div>`;
 else if(page==='desktop')h=CARDS[5];
 else h=await extra(page,s,c,CARDS);
 document.getElementById('g').innerHTML=h}
load();setInterval(()=>{if(['look','connections','desktop'].includes(page)&&(!document.activeElement||!['INPUT','SELECT'].includes(document.activeElement.tagName)))load()},15000);
</script></body></html>
LSET
cat > ~/.local/share/retro-lab/splash.html <<'LSPL'
<!doctype html><html><head><meta charset="utf-8"><title>Startup</title><style>html,body{margin:0;height:100%;overflow:hidden;background:#000;cursor:none}#r{width:1920px;height:1080px;position:relative;transform-origin:0 0}</style></head><body><div id="r"></div><script>
const fit=()=>{document.getElementById('r').style.transform='scale('+Math.max(innerWidth/1920,innerHeight/1080)+')'};fit();addEventListener('resize',fit);
window.rA=(()=>{
window.render=function(t,f){
 const ease=x=>x<0?0:x>1?1:x*x*(3-2*x);
 let h='';
 const bgO=ease((t-1.1)/.5);
 const line=ease((t-.5)/.6), thick=ease((t-1.1)/.5);
 const flick=t<1.4?(.04+.08*Math.abs(Math.sin(f*12.9898)*43758.5453%1)):0;
 h+='<div style="position:absolute;inset:0;background:#000"></div>';
 h+='<div style="position:absolute;inset:0;background:linear-gradient(#2a1b14,#3a2518);opacity:'+(t<1.1?0:bgO)+';clip-path:inset('+(50-50*thick)+'% 0 '+(50-50*thick)+'% 0)"></div>';
 if(t>=.5&&t<1.7){const w=1920*line,hh=4+1000*thick*thick;const op=t<1.1?1:1-ease((t-1.3)/.4);h+='<div style="position:absolute;left:'+(960-w/2)+'px;top:'+(540-hh/2)+'px;width:'+w+'px;height:'+hh+'px;background:#e0873a;box-shadow:0 0 40px #e0873a;opacity:'+op+'"></div>'}
 if(t>=1.5){
  const halo=ease((t-3)/1.5)*.5;
  h+='<div style="position:absolute;left:560px;top:100px;width:800px;height:800px;border-radius:50%;background:radial-gradient(#d27a35,transparent 65%);opacity:'+halo+'"></div>';
  const steps=[-150,-81,0,109,164,210];const k=t<1.8?0:Math.min(6,Math.floor((t-1.8)/.28)+1);const y=k?steps[k-1]:-220;
  h+='<svg style="position:absolute;inset:0" width="1920" height="1080" viewBox="0 0 1920 1080"><defs><clipPath id="cL"><circle r="210"/></clipPath><clipPath id="rv"><rect x="-220" y="-220" width="440" height="'+(y+220)+'"/></clipPath><mask id="mL"><rect x="-220" y="-220" width="440" height="440" fill="#fff"/><g fill="#000"><rect x="-220" y="-150" width="440" height="14"/><rect x="-220" y="-95" width="440" height="14"/><rect x="-220" y="95" width="440" height="14"/><rect x="-220" y="150" width="440" height="14"/><circle r="62"/><rect x="-220" y="-14" width="440" height="14"/></g></mask><linearGradient id="gL" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8a4a22"/><stop offset=".45" stop-color="#d27a35"/><stop offset=".8" stop-color="#e7a947"/><stop offset="1" stop-color="#e3c26a"/></linearGradient></defs><g transform="translate(960,440)" clip-path="url(#rv)"><g clip-path="url(#cL)" mask="url(#mL)"><rect x="-220" y="-220" width="440" height="440" fill="url(#gL)"/></g></g>';
  const wo=ease((t-3.5)/.9);
  h+='<g opacity="'+wo+'" style="filter:drop-shadow(0 0 '+(20*wo)+'px rgba(224,135,58,.6))"><text x="960" y="775" font-family="Gelasio,Georgia,DejaVu Serif,serif" font-size="110" font-weight="900" text-anchor="middle" fill="#f0e0bd">aperture</text><text x="960" y="830" font-family="Gelasio,Georgia,DejaVu Serif,serif" font-size="32" font-style="italic" text-anchor="middle" fill="#c9a77a" letter-spacing="24">LABORATORIES</text></g>';
  const L=[];
  L.forEach((l,i)=>{const n=Math.max(0,Math.min(l[0].length,Math.floor((t-l[1])*34)));const cur=(n<l[0].length&&n>0)||(i==2&&n==l[0].length&&Math.floor(t*3)%2==0)?'_':'';h+='<text x="960" y="'+(900+i*34)+'" font-family="DejaVu Sans Mono,monospace" font-size="24" text-anchor="middle" fill="#e0873a">'+l[0].slice(0,n)+cur+'</text>'});
  h+='</svg>';
 }
 h+='<div style="position:absolute;inset:0;background:repeating-linear-gradient(0deg,rgba(0,0,0,.18) 0 2px,transparent 2px 4px);pointer-events:none"></div>';
 if(flick)h+='<div style="position:absolute;inset:0;background:#e8d9b0;opacity:'+flick+'"></div>';
 const d=ease((t-6.7)/.9);
 h+='<img src="" style="position:absolute;inset:0;width:1920px;height:1080px;opacity:'+d+'">';
 document.getElementById('r').innerHTML=h;
};;return window.render})();
window.rD=(()=>{
const ease=x=>x<0?0:x>1?1:x*x*(3-2*x);
const rnd=n=>Math.abs(Math.sin(n*12.9898)*43758.5453)%1;
const SER='font-family="Gelasio,Georgia,DejaVu Serif,serif"';
function logo(y,mono,op){const col=mono?'<linearGradient id="gL" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#ffb000"/><stop offset="1" stop-color="#ffb000"/></linearGradient>':'<linearGradient id="gL" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#8a4a22"/><stop offset=".45" stop-color="#d27a35"/><stop offset=".8" stop-color="#e7a947"/><stop offset="1" stop-color="#e3c26a"/></linearGradient>';
 return '<defs><clipPath id="cL"><circle r="210"/></clipPath><clipPath id="rv"><rect x="-220" y="-220" width="440" height="'+(y+220)+'"/></clipPath><mask id="mL"><rect x="-220" y="-220" width="440" height="440" fill="#fff"/><g fill="#000"><rect x="-220" y="-150" width="440" height="14"/><rect x="-220" y="-95" width="440" height="14"/><rect x="-220" y="95" width="440" height="14"/><rect x="-220" y="150" width="440" height="14"/><circle r="62"/><rect x="-220" y="-14" width="440" height="14"/></g></mask>'+col+'</defs><g opacity="'+op+'" transform="translate(960,440)" clip-path="url(#rv)"><g clip-path="url(#cL)" mask="url(#mL)"><rect x="-220" y="-220" width="440" height="440" fill="url(#gL)"'+(mono?' style="filter:drop-shadow(0 0 14px #ffb000)"':'')+'/></g></g>'}
function word(wo,col1,col2){return '<g opacity="'+wo+'" style="filter:drop-shadow(0 0 '+(20*wo)+'px rgba(224,135,58,.6))"><text x="960" y="775" '+SER+' font-size="110" font-weight="900" text-anchor="middle" fill="'+col1+'">aperture</text><text x="960" y="830" '+SER+' font-size="32" font-style="italic" text-anchor="middle" fill="'+col2+'" letter-spacing="24">LABORATORIES</text></g>'}
function scan(){return '<div style="position:absolute;inset:0;background:repeating-linear-gradient(0deg,rgba(0,0,0,.18) 0 2px,transparent 2px 4px);pointer-events:none"></div>'}
function deskFade(t,s){return '<img src="" style="position:absolute;inset:0;width:1920px;height:1080px;opacity:'+ease((t-s)/.9)+'">'}
function typed(lines,t,y0,col,size){return lines.map((l,i)=>{const n=Math.max(0,Math.min(l[0].length,Math.floor((t-l[1])*34)));const cur=(n<l[0].length&&n>0)?'_':'';return '<text x="960" y="'+(y0+i*40)+'" font-family="DejaVu Sans Mono,monospace" font-size="'+size+'" text-anchor="middle" fill="'+col+'">'+l[0].slice(0,n)+cur+'</text>'}).join('')}
const NIGHT='<div style="position:absolute;inset:0;background:linear-gradient(#2a1b14,#3a2518)"></div>';
const SCENES={
b:(t,f)=>{ // iris
 let h='<div style="position:absolute;inset:0;background:#000"></div>';
 const open=ease((t-.8)/2),rr=open*1250;
 h+='<div style="position:absolute;inset:0;opacity:'+(t<.8?0:1)+'">'+NIGHT+'<div style="position:absolute;left:560px;top:140px;width:800px;height:800px;border-radius:50%;background:radial-gradient(#d27a35,transparent 65%);opacity:'+(.5*ease((t-2.6)/1.2))+'"></div><svg style="position:absolute;inset:0" width="1920" height="1080" viewBox="0 0 1920 1080">'+logo(210,0,1)+word(ease((t-3.2)/.9),'#f0e0bd','#c9a77a')+typed([['WELCOME TO THE LAB',4.6]],t,905,'#e0873a',26)+'</svg></div>';
 if(t>=.8&&open<1){const ang=open*70,pts=[];for(let k=0;k<6;k++){const a=(k*60+ang)*Math.PI/180;pts.push((960+rr*Math.cos(a)).toFixed(1)+','+(540+rr*Math.sin(a)).toFixed(1))}
  h+='<svg style="position:absolute;inset:0" width="1920" height="1080"><path fill="#0b0705" fill-rule="evenodd" d="M0 0H1920V1080H0Z M'+pts.join(' L')+'Z"/><polygon points="'+pts.join(' ')+'" fill="none" stroke="#e0873a" stroke-width="5" stroke-linejoin="round"/>'+pts.map((p,k)=>{const q=pts[(k+2)%6];return '<line x1="'+p.split(',')[0]+'" y1="'+p.split(',')[1]+'" x2="'+(960+(q.split(',')[0]-960)*1.9)+'" y2="'+(540+(q.split(',')[1]-540)*1.9)+'" stroke="#3a2518" stroke-width="3"/>'}).join('')+'</svg>'}
 else if(t<.8){h+='<svg style="position:absolute;inset:0" width="1920" height="1080"><circle cx="960" cy="540" r="'+(4+2*rnd(f))+'" fill="#e0873a"/></svg>'}
 return h+scan()+deskFade(t,6.6)},
c:(t,f)=>{ // film leader
 let h='<div style="position:absolute;inset:0;background:#000"></div>';
 const jx=(rnd(f)-.5)*6,jy=(rnd(f+99)-.5)*6;
 if(t>=.3&&t<3.6){const n=t<1.4?3:t<2.4?2:1,sw=((t-.3)%1);h+='<div style="position:absolute;inset:0;background:#d9c79a;transform:translate('+jx+'px,'+jy+'px)"></div><svg style="position:absolute;inset:0;transform:translate('+jx+'px,'+jy+'px)" width="1920" height="1080"><g fill="none" stroke="#4a2a16" stroke-width="5"><circle cx="960" cy="540" r="400"/><circle cx="960" cy="540" r="330" stroke-width="2"/><line x1="560" y1="540" x2="1360" y2="540"/><line x1="960" y1="140" x2="960" y2="940"/></g><path d="M960 540 L'+(960+400*Math.cos(sw*6.283-1.57))+' '+(540+400*Math.sin(sw*6.283-1.57))+' A400 400 0 '+(sw>.5?1:0)+' 0 960 140Z" fill="rgba(74,42,22,.25)" transform="scale(1,1)"/><text x="960" y="650" '+SER+' font-size="320" font-weight="900" text-anchor="middle" fill="#4a2a16">'+n+'</text><text x="960" y="1010" font-family="DejaVu Sans Mono,monospace" font-size="26" text-anchor="middle" fill="#4a2a16" letter-spacing="8">APERTURE LABORATORIES · REEL 1</text></svg>';
  for(let i=0;i<40;i++)h+='<div style="position:absolute;left:'+(rnd(f*3+i)*1920)+'px;top:'+(rnd(f*7+i)*1080)+'px;width:'+(2+rnd(i)*3)+'px;height:'+(2+rnd(i+5)*3)+'px;background:rgba(40,25,15,.5);border-radius:50%"></div>';
  if(rnd(f+3)>.7)h+='<div style="position:absolute;left:'+(rnd(f+8)*1920)+'px;top:0;width:3px;height:1080px;background:rgba(40,25,15,.35)"></div>'}
 if(t>=3.6){const fl=1-ease((t-3.6)/.25);h+=NIGHT+'<div style="position:absolute;left:560px;top:140px;width:800px;height:800px;border-radius:50%;background:radial-gradient(#d27a35,transparent 65%);opacity:'+(.5*ease((t-3.9)/1))+'"></div><svg style="position:absolute;inset:0;transform:translate('+(t<4.2?jx:0)+'px,'+(t<4.2?jy:0)+'px)" width="1920" height="1080" viewBox="0 0 1920 1080">'+logo(210,0,1)+word(ease((t-4)/.9),'#f0e0bd','#c9a77a')+typed([['PROJECTION READY',4.8]],t,905,'#e0873a',26)+'</svg><div style="position:absolute;inset:0;background:#fff;opacity:'+fl*.8+'"></div>'}
 return h+scan()+deskFade(t,6.6)},
d:(t,f)=>{ // amber terminal
 let h='<div style="position:absolute;inset:0;background:#120a00"></div>';
 const A='#ffb000';
 if(t<3.5){const all=['APERTURE LABORATORIES BIOS v1.953','CPU: ARM CORTEX-A76 x4 .......... OK','MEMORY TEST: '+Math.min(16384,Math.floor(Math.max(0,t-.3)*7000))+'K','DETECTING DRIVES ................ OK','LOADING KERNEL .................. OK','MOUNTING /LAB ................... OK','STARTING NETWORK ................ OK','TAILSCALE LINK .................. ESTABLISHED','FIREWALL ........................ ACTIVE','ACOUSTICS ....................... WARM','LOADING WIDGETS ................. OK','PRESENT USER: AUTHENTICATED'];
  const n=Math.min(all.length,Math.floor((t-.3)*3.6)+1);h+='<div style="position:absolute;left:200px;top:140px;font-family:DejaVu Sans Mono,monospace;font-size:30px;line-height:52px;color:'+A+';text-shadow:0 0 12px '+A+';white-space:pre">'+all.join('\n').slice(0,Math.max(0,Math.floor((t-.3)*150)))+(Math.floor(t*4)%2?'_':'')+'</div>'}
 else{const m=ease((t-4.6)/.8);h+='<div style="position:absolute;inset:0;background:linear-gradient(#2a1b14,#3a2518);opacity:'+m+'"></div><svg style="position:absolute;inset:0" width="1920" height="1080" viewBox="0 0 1920 1080">'+logo(210,1,1-m)+logo(210,0,m)+word(ease((t-4.2)/.9),m>.5?'#f0e0bd':'#ffb000',m>.5?'#c9a77a':'#ffb000')+typed([['SYSTEM READY. HAVE A PLEASANT DAY.',5.0]],t,905,m>.5?'#e0873a':A,26)+'</svg>'}
 return h+scan()+deskFade(t,6.7)}};
window.render=(s,t,f)=>{document.getElementById('r').innerHTML=SCENES[s](t,f)};;return SCENES.d})();
const O=2.7,TOTAL=7.7,post=(u)=>fetch(u,{method:'POST',headers:{'X-Lab':'1'},body:''}).catch(()=>{});
const SKIP=location.search.indexOf('skiplog')>=0;let chimed=false,done=false,start=null,last=-1;
const ease=x=>x<0?0:x>1?1:x*x*(3-2*x);
function frame(now){if(start===null)start=now-(SKIP?O*1000:0);const t=(now-start)/1000,f=Math.floor(t*24);
 if(f!==last){last=f;const el=document.getElementById('r');let h;
  if(t<O+.5){
   if(t<2.5)h=window.rD(Math.min(t,2.45),f);
   else if(t<2.9){const k=(t-2.5)/.4;h='<div style="position:absolute;inset:0;transform:scaleY('+(1-.992*k*k)+');filter:brightness('+(1+2*k)+')">'+window.rD(2.45,f)+'</div>'}
   else h='<div style="position:absolute;inset:0;background:#000"></div><div style="position:absolute;left:660px;top:538px;width:600px;height:5px;background:#ffb000;box-shadow:0 0 30px #ffb000"></div>';
  } else {window.rA(t-O,f);h=el.innerHTML}
  el.innerHTML=h.replace(/<img[^>]*>/g,'');
  document.body.style.opacity=t<O+4.0?1:1-ease((t-(O+4.0))/.9);
 }
 if(!chimed&&t>=O+1.8){chimed=true;post('/api/chime')}
 if(!done&&t>=TOTAL+.2){done=true;post('/api/splash-done');return}
 requestAnimationFrame(frame)}
requestAnimationFrame(frame);
</script></body></html>
LSPL
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
    <windowRule identifier="lab-desk"><serverDecoration>no</serverDecoration><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher></windowRule>
    <windowRule title="Lab Desk*"><serverDecoration>no</serverDecoration><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher><action name="ToggleAlwaysOnBottom"/></windowRule>
    <windowRule identifier="chrome-localhost__-*"><serverDecoration>no</serverDecoration><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher></windowRule>
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
    <windowRule identifier="lab-desk"><serverDecoration>no</serverDecoration><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher></windowRule>
    <windowRule title="Lab Desk*"><serverDecoration>no</serverDecoration><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher><action name="ToggleAlwaysOnBottom"/></windowRule>
    <windowRule identifier="chrome-localhost__-*"><serverDecoration>no</serverDecoration><skipTaskbar>yes</skipTaskbar><skipWindowSwitcher>yes</skipWindowSwitcher></windowRule>
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
cat > ~/.local/bin/retro-splash <<'RSP'
#!/bin/bash
case "$1" in on|off) sed -i "s/^splash=.*/splash=$1/" ~/.config/retro-lab/config; echo "Startup animation: $1";; *) echo "Use: retro-splash on | off";; esac
RSP
chmod +x ~/.local/bin/retro-splash
grep -q '^splash=' ~/.config/retro-lab/config || echo "splash=off" >> ~/.config/retro-lab/config
cat > ~/.local/share/applications/lab-splash.desktop <<'DT'
[Desktop Entry]
Type=Application
Name=Replay startup animation
Exec=/bin/bash -c "$HOME/.local/bin/lab-splash"
Icon=video-display
Categories=Settings;
DT
chmod +x ~/.local/bin/lab-desk
pkill -f lab-desk.py 2>/dev/null || true   # so a re-run loads the newest version
# Custom taskbar (Waybar) + start menu (Wofi) in the lab theme
mkdir -p ~/.config/waybar ~/.config/wofi
cat > ~/.config/waybar/config <<'WB'
{
  "layer": "top", "position": "bottom", "height": 48, "margin-left": 8, "margin-right": 8, "margin-bottom": 6,
  "modules-left": ["custom/start", "wlr/taskbar"],
  "modules-right": ["tray", "network", "pulseaudio", "custom/power"],
  "custom/start": { "format": "User: @@USER@@", "on-click": "curl -s -X POST -H 'X-Lab: 1' -d apps http://localhost:8787/api/menu", "tooltip": false },
  "wlr/taskbar": { "format": "{icon} {title}", "icon-size": 18, "tooltip": false, "on-click": "activate", "on-click-middle": "close", "max-length": 24, "ignore-list": ["lab-desk", "chrome-localhost__-Default"] },
  "tray": { "spacing": 10 },
  "network": { "format-wifi": "wifi {signalStrength}%", "format-ethernet": "net", "format-disconnected": "offline", "tooltip": false },
  "pulseaudio": { "format": "vol {volume}%", "format-muted": "muted", "on-click": "pavucontrol", "tooltip": false },
  "custom/power": { "format": "power", "on-click": "curl -s -X POST -H 'X-Lab: 1' -d power http://localhost:8787/api/menu", "tooltip": false }
}
WB
sed -i "s/@@USER@@/$USER/" ~/.config/waybar/config
cat > ~/.config/wofi/config <<'WF'
width=420
height=520
location=bottom_left
xoffset=12
yoffset=-64
allow_images=true
insensitive=true
hide_scroll=true
WF
cat > ~/.local/bin/retro-panel <<'RP'
#!/bin/bash
# retro-panel stock = go back to the normal Pi taskbar;  retro-panel lab = use the lab taskbar
case "$1" in
 stock) rm -f ~/.config/autostart/lab-bar.desktop; pkill waybar; (nohup /usr/bin/lwrespawn /usr/bin/wf-panel-pi >/dev/null 2>&1 &); echo "Stock taskbar back.";;
 lab) cp ~/.local/share/retro-lab/lab-bar.desktop ~/.config/autostart/lab-bar.desktop; pkill -f 'lwrespawn.*wf-panel-pi'; pkill wf-panel-pi; (nohup waybar >/dev/null 2>&1 &); echo "Lab taskbar on.";;
 *) echo "Use: retro-panel stock | lab";;
esac
RP
chmod +x ~/.local/bin/retro-panel
cat > ~/.local/share/retro-lab/lab-bar.desktop <<'AS'
[Desktop Entry]
Type=Application
Name=Lab Taskbar
Exec=/bin/bash -c "$HOME/.local/bin/lab-bar"
AS
cp ~/.local/share/retro-lab/lab-bar.desktop ~/.config/autostart/lab-bar.desktop
# Remove the taskbar clock so Lab Desk has the only clock (takes effect after reboot)
for f in ~/.config/wf-panel-pi.ini ~/.config/wf-panel-pi/wf-panel-pi.ini; do
  [ -f "$f" ] && sed -i -E '/^widgets_(left|right)=/ s/(^|[ =])clock( |$)/\1\2/' "$f" && sed -i -E '/^widgets_(left|right)=/ s/  +/ /g' "$f" || true
done
cat > ~/.local/bin/lab-settings <<'LSS'
#!/bin/bash
pgrep -f lab-desk.py >/dev/null || (nohup python3 ~/.local/share/retro-lab/lab-desk.py >/dev/null 2>&1 &)
sleep 1
B=$(command -v chromium || command -v chromium-browser || command -v vivaldi-stable)
exec "$B" --app=http://localhost:8787/settings --window-size=1100,860 --no-first-run --user-data-dir="$HOME/.cache/retro-lab/settings-browser"
LSS
chmod +x ~/.local/bin/lab-settings
cat > ~/.local/share/applications/lab-settings.desktop <<'AS'
[Desktop Entry]
Type=Application
Name=Lab Settings
Exec=/bin/bash -c "$HOME/.local/bin/lab-settings"
Icon=preferences-system
Categories=Settings;
AS
cat > ~/.config/autostart/lab-desk.desktop <<'AS'
[Desktop Entry]
Type=Application
Name=Lab Desk
Exec=/bin/bash -c "$HOME/.local/bin/lab-desk"
AS
cat > ~/.local/share/applications/lab-desk.desktop <<'AS'
[Desktop Entry]
Type=Application
Name=Lab Desk (widgets)
Exec=/bin/bash -c "$HOME/.local/bin/lab-desk"
Icon=utilities-system-monitor
Categories=Utility;
AS
for m in day dusk night auto; do
cat > ~/.local/share/applications/retro-theme-$m.desktop <<DT
[Desktop Entry]
Type=Application
Name=Lab Theme: ${m^}
Exec=$HOME/.local/bin/retro-theme $m
Icon=preferences-desktop-theme
Categories=Settings;
DT
done

echo "== 3/7 Computer name =="
if grep -q '^127.0.1.1' /etc/hosts; then sudo sed -i "s/^127.0.1.1.*/127.0.1.1\t$HOSTNAME_NEW/" /etc/hosts; else echo "127.0.1.1	$HOSTNAME_NEW" | sudo tee -a /etc/hosts >/dev/null; fi
sudo hostnamectl set-hostname "$HOSTNAME_NEW"

echo "== 4/7 Login screen and boot splash =="
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

echo "== 5/7 Soft retro colours for apps =="
for v in gtk-3.0 gtk-4.0; do
mkdir -p ~/.config/$v
cat > ~/.config/$v/gtk.css <<'GT'
@define-color accent_color #d27a35;
@define-color accent_bg_color #d27a35;
@define-color theme_selected_bg_color #d27a35;
@define-color theme_selected_fg_color #fbeed0;
GT
done

echo "== 6/7 Tailscale (remote access) =="
command -v tailscale >/dev/null || curl -fsSL https://tailscale.com/install.sh | sudo sh

echo "== 7/7 RustDesk (remote desktop) =="
if command -v rustdesk >/dev/null; then echo "RustDesk already installed."; else
URL=$(curl -fsSL https://api.github.com/repos/rustdesk/rustdesk/releases/latest | grep -o 'https://[^"]*aarch64\.deb' | head -1)
if [ -n "$URL" ]; then
  curl -fsSL -o /tmp/rustdesk.deb "$URL" && sudo apt-get install -y /tmp/rustdesk.deb
else
  echo "Could not find the RustDesk download. Get it at https://rustdesk.com (choose Linux, aarch64 .deb)."
fi
fi

echo "== Retro console (RetroArch) =="
for p in unzip retroarch retroarch-assets libretro-core-info libretro-nestopia libretro-snes9x libretro-genesisplusgx libretro-gambatte libretro-mgba libretro-beetle-pce libretro-mupen64plus-next libretro-pcsx-rearmed; do
  sudo apt-get install -y "$p" >/dev/null 2>&1 || echo "  (skipped $p, not available)"
done
mkdir -p ~/ROMs/{NES,SNES,Genesis,GameBoy,GBA,N64,PSX,PCEngine} ~/.config/retroarch
# PS1, N64, PC Engine and Dreamcast cores are not in Debian: fetch the 64-bit Pi builds from libretro
CORES=~/.local/share/retro-lab/cores; mkdir -p "$CORES"
for f in /usr/lib/*/libretro/*.so; do [ -f "$f" ] && ln -sf "$f" "$CORES/$(basename "$f")"; done
for c in pcsx_rearmed mupen64plus_next mednafen_pce flycast; do
  if [ ! -f "$CORES/${c}_libretro.so" ]; then
    curl -fsSL -m 120 "https://buildbot.libretro.com/nightly/linux/aarch64/latest/${c}_libretro.so.zip" -o /tmp/core-$c.zip && unzip -oq /tmp/core-$c.zip -d "$CORES" || echo "  (skipped core $c, no download)"
    rm -f /tmp/core-$c.zip
  fi
done
if [ ! -f ~/.config/retroarch/retroarch.cfg ]; then
cat > ~/.config/retroarch/retroarch.cfg <<RA
rgui_browser_directory = "$HOME/ROMs"
input_autodetect_enable = "true"
video_fullscreen = "true"
menu_show_quit_retroarch = "true"
libretro_directory = "$HOME/.local/share/retro-lab/cores"
libretro_info_path = "/usr/share/libretro/info"
RA
fi
cat > ~/.local/share/applications/retro-console.desktop <<'AS'
[Desktop Entry]
Type=Application
Name=Retro Console
Comment=Play classic games (RetroArch)
Exec=retroarch
Icon=retroarch
Categories=Game;
AS

echo "== Sounds, connections, security tools =="
sudo apt-get install -y zenity gvfs-backends swaylock swayidle ufw unattended-upgrades pulseaudio-utils >/dev/null 2>&1 || echo "  (some helper packages were skipped)"
cat >> ~/.config/retro-lab/config <<'CFG2'
CFG2
grep -q '^sounds=' ~/.config/retro-lab/config || echo "sounds=on" >> ~/.config/retro-lab/config
grep -q '^sound_volume=' ~/.config/retro-lab/config || echo "sound_volume=100" >> ~/.config/retro-lab/config
grep -q '^mail_tab=' ~/.config/retro-lab/config || echo "mail_tab=gmail" >> ~/.config/retro-lab/config
grep -q '^sound_style=' ~/.config/retro-lab/config || echo "sound_style=a-warm-synth" >> ~/.config/retro-lab/config
for k in pc_mac server_user pc_name server_name server_lan server_share port_jellyfin port_seerr extras; do grep -q "^$k=" ~/.config/retro-lab/config || echo "$k=" >> ~/.config/retro-lab/config; done

# --- retro chimes (original, synthesized on this computer; no audio files downloaded)
mkdir -p ~/.local/share/retro-lab/sounds
cat > ~/.local/share/retro-lab/make-sounds.py <<'SND'
import wave, struct, math, os, random, sys
R = 44100
OUT = os.path.expanduser(sys.argv[1] if len(sys.argv) > 1 else "~/.local/share/retro-lab/sounds/")
def fm(f, d, vol=.5, dec=3.5):
    out = []
    for i in range(int(R * d)):
        t = i / R; env = math.exp(-dec * t) * min(1, t * 90)
        s = math.sin(2 * math.pi * f * t + 1.3 * env * math.sin(2 * math.pi * f * 2 * t)) + .25 * math.sin(2 * math.pi * f * 3 * t) * env
        out.append(s * env * vol)
    return out
def bell(f, d, vol=.5, dec=2.2):
    parts = [(1, 1), (2.0, .5), (2.76, .35), (5.4, .15), (8.93, .08)]
    return [vol * sum(a * math.sin(2 * math.pi * f * k * i / R) * math.exp(-dec * (1 + k * .25) * i / R) for k, a in parts) * min(1, i / R * 300) for i in range(int(R * d))]
def sq(f, d, vol=.25, sweep=0):
    out = []; ph = 0
    for i in range(int(R * d)):
        t = i / R; ph += 2 * math.pi * (f + sweep * t / d) / R
        env = min(1, t * 400) * min(1, (d - t) * 200)
        out.append((1 if math.sin(ph) > 0 else -1) * vol * env)
    return out
def clack(d=.03, vol=.4, seed=1):
    r = random.Random(seed); return [vol * (r.random() * 2 - 1) * math.exp(-60 * i / R) for i in range(int(R * d))]
def mix(parts):
    buf = [0.0] * max(int(R * s) + len(x) for s, x in parts)
    for s, x in parts:
        o = int(R * s)
        for i, v in enumerate(x): buf[o + i] += v
    return buf
def save(style, name, buf):
    os.makedirs(OUT + style, exist_ok=True); pk = max(abs(v) for v in buf) or 1
    with wave.open(f"{OUT}{style}/{name}.wav", "w") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
        w.writeframes(b"".join(struct.pack("<h", int(v / pk * .8 * 32767)) for v in buf))
C4, G4, E4 = 261.63, 392.0, 329.63; C5, E5, G5, B5, C6 = 523.25, 659.25, 783.99, 987.77, 1046.5
# a = warm analog synth
save("a-warm-synth", "startup", mix([(0, fm(C5 / 2, 2.2, .5, 1.6)), (.05, fm(C5, 1.2)), (.22, fm(E5, 1.1)), (.44, fm(G5, 1.1)), (.66, fm(B5, 1.2)), (.95, fm(C6, 1.8, .6, 2))]))
save("a-warm-synth", "login", mix([(0, fm(G5, .8)), (.16, fm(C6, 1.3, .6, 2.5))]))
save("a-warm-synth", "shutdown", mix([(0, fm(C6, 1)), (.22, fm(G5, 1)), (.44, fm(E5, 1)), (.7, fm(C5, 1.6, .6, 2)), (.7, fm(C5 / 2, 1.6, .4, 2))]))
save("a-warm-synth", "notify", fm(G5, .6, .6, 4))
# b = 70s lab PA chime (ding-dong bells)
save("b-lab-pa-chime", "startup", mix([(0, bell(G5, 2.2)), (.55, bell(E5, 2.2)), (1.1, bell(C5, 2.8))]))
save("b-lab-pa-chime", "login", mix([(0, bell(E5, 1.8)), (.5, bell(C5, 2.2))]))
save("b-lab-pa-chime", "shutdown", mix([(0, bell(C5, 1.8)), (.55, bell(G4, 1.8)), (1.1, bell(C4, 3))]))
save("b-lab-pa-chime", "notify", bell(G5, 1.4))
# c = teletype and computer beeps
save("c-teletype-beeps", "startup", mix([(i * .045, clack(seed=i)) for i in range(14)] + [(.75, sq(880, .09)), (.9, sq(1175, .09)), (1.05, sq(1480, .09)), (1.25, sq(440, .5, .2, 880))]))
save("c-teletype-beeps", "login", mix([(0, sq(1175, .08)), (.12, sq(1760, .14))]))
save("c-teletype-beeps", "shutdown", mix([(0, sq(1480, .09)), (.14, sq(1175, .09)), (.28, sq(880, .09)), (.45, sq(880, .7, .2, -660))]))
save("c-teletype-beeps", "notify", sq(1320, .07))
SND
python3 ~/.local/share/retro-lab/make-sounds.py
cat > ~/.local/bin/retro-sound <<'RS'
#!/bin/bash
# retro-sound startup|login|shutdown  (does nothing if sounds are off)
grep -q '^sounds=on' ~/.config/retro-lab/config || exit 0
S=$(grep "^sound_style=" ~/.config/retro-lab/config | cut -d= -f2-); F=~/.local/share/retro-lab/sounds/${S:-a-warm-synth}/$1.wav
[ -f "$F" ] || exit 0
V=$(grep "^sound_volume=" ~/.config/retro-lab/config | cut -d= -f2-); V=${V:-100}
if command -v paplay >/dev/null; then paplay --volume=$((V*655)) "$F"; elif command -v pw-play >/dev/null; then pw-play --volume=0.$(printf %02d $((V%100))) "$F"; else aplay -q "$F"; fi
RS
chmod +x ~/.local/bin/retro-sound
cat > ~/.local/bin/retro-sounds <<'RS2'
#!/bin/bash
case "$1" in
 on|off) sed -i "s/^sounds=.*/sounds=$1/" ~/.config/retro-lab/config; echo "Sounds: $1"; [ "$1" = on ] && ~/.local/bin/retro-sound login;;
 a|b|c) S=$(ls ~/.local/share/retro-lab/sounds | grep "^$1-"); sed -i "s/^sound_style=.*/sound_style=$S/" ~/.config/retro-lab/config; echo "Style: $S"; ~/.local/bin/retro-sound startup;;
 *) echo "Use: retro-sounds on | off | a | b | c   (a = warm synth, b = lab PA chime, c = teletype beeps)";;
esac
RS2
chmod +x ~/.local/bin/retro-sounds
for m in on off; do
cat > ~/.local/share/applications/lab-sounds-$m.desktop <<DT
[Desktop Entry]
Type=Application
Name=Lab Sounds: ${m^^}
Exec=$HOME/.local/bin/retro-sounds $m
Icon=audio-volume-high
Categories=Settings;
DT
done
# play the startup chime when the desktop opens

# --- retro-connect: sets up Jellyfin, Seerr, server apps, PC remote and file shortcuts
cat > ~/.local/bin/retro-server-host <<'RH'
#!/bin/bash
# Prints the address to use for the home server: its Tailscale name if reachable (works anywhere), else its home-network address.
C=~/.config/retro-lab/config; g(){ grep "^$1=" $C | cut -d= -f2-; }
P=${1:-80}; T=$(g server_name); L=$(g server_lan)
for h in "$T" "$L"; do
  [ -n "$h" ] && timeout 2 bash -c "exec 3<>/dev/tcp/$h/$P" 2>/dev/null && { echo "$h"; exit 0; }
done
echo "${T:-$L}"
RH
chmod +x ~/.local/bin/retro-server-host
cat > ~/.local/bin/retro-open <<'RO'
#!/bin/bash
# retro-open PORT : open a home-server web app in its own Vivaldi window
H=$("$HOME/.local/bin/retro-server-host" "$1")
B=$(command -v vivaldi-stable || command -v chromium || command -v chromium-browser)
exec "$B" --app="http://$H:$1"
RO
chmod +x ~/.local/bin/retro-open
cat > ~/.local/bin/retro-files <<'RF'
#!/bin/bash
# Open the home server's shared folder (SMB over Tailscale). The file manager asks for your server login the first time.
C=~/.config/retro-lab/config; g(){ grep "^$1=" $C | cut -d= -f2-; }
H=$("$HOME/.local/bin/retro-server-host" 445); S=$(g server_share)
exec pcmanfm "smb://$H/$S/"
RF
chmod +x ~/.local/bin/retro-files
# --- Wake My PC: the always-on server sends a Wake-on-LAN packet to your PC
cat > ~/.local/share/retro-lab/wol.py <<'WOL'
import socket, sys
mac = bytes.fromhex(sys.argv[1].replace(":", "").replace("-", ""))
s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
s.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
for _ in range(3): s.sendto(b"\xff" * 6 + mac * 16, (sys.argv[2], 9))
print("Magic packet sent.")
WOL
cat > ~/.local/bin/retro-wake <<'RW'
#!/bin/bash
# Wake My PC: asks the home server (over Tailscale) to send a Wake-on-LAN packet, then waits for the PC to appear.
C=~/.config/retro-lab/config; g(){ grep "^$1=" $C | cut -d= -f2-; }
MAC=$(g pc_mac); PC=$(g pc_name); U=$(g server_user); T=$(g server_name); L=$(g server_lan)
[ -z "$MAC" ] || [ -z "$U" ] && { echo "Run retro-connect first (it needs your PC's MAC address and the server login name)."; read -r -p "Press Enter"; exit 1; }
B="${L%.*}.255"; [ -z "$L" ] && B=255.255.255.255
H=$T; [ -z "$H" ] && H=$L
echo "Asking the server ($H) to wake your PC..."
if ! ssh -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new "$U@$H" "docker run --rm --net=host -i python:3-alpine python - '$MAC' '$B'" < ~/.local/share/retro-lab/wol.py; then
  echo; echo "Could not reach the server or run the wake command. Run retro-wake-setup (once, while at home), then try again."; read -r -p "Press Enter"; exit 1
fi
echo "Waiting for $PC to come online (up to 3 minutes)..."
for i in $(seq 1 36); do
  if tailscale ping -c 1 --timeout 3s "$PC" >/dev/null 2>&1; then echo "$PC is ONLINE. You can connect now (start menu: Remote: My PC)."; ~/.local/bin/retro-sound notify; notify-send "Wake My PC" "$PC is online" 2>/dev/null; read -r -t 8 -p "" ; exit 0; fi
  printf "."; sleep 5
done
echo; echo "No answer yet. Check the PC has power, a network cable, Wake-on-LAN enabled, and Tailscale set to run unattended."; read -r -p "Press Enter"
RW
chmod +x ~/.local/bin/retro-wake
cat > ~/.local/bin/retro-wake-setup <<'RWS'
#!/bin/bash
# One-time: prepares the home server (Tailscale SSH + permission to run Docker + the tiny wake tool). Run this while you're at home.
C=~/.config/retro-lab/config; g(){ grep "^$1=" $C | cut -d= -f2-; }
U=$(g server_user); H=$(g server_lan); [ -z "$H" ] && H=$(g server_name)
[ -z "$U" ] || [ -z "$H" ] && { echo "Run retro-connect first."; exit 1; }
echo "You'll be asked for the server's password (twice maybe). Nothing is stored."
ssh -t -o StrictHostKeyChecking=accept-new "$U@$H" 'sudo tailscale set --ssh; sudo usermod -aG docker "$USER"; sudo docker pull python:3-alpine'
echo "Server ready. Test it with the start menu button: Wake My PC."
RWS
chmod +x ~/.local/bin/retro-wake-setup
cat > ~/.local/bin/retro-pc <<'RPC'
#!/bin/bash
# Connect to your Windows PC with RustDesk over Tailscale (private direct connection).
N=$(grep '^pc_name=' ~/.config/retro-lab/config | cut -d= -f2-)
IP=$(tailscale ip -4 "$N" 2>/dev/null | head -1)
exec rustdesk --connect "${IP:-$N}"
RPC
chmod +x ~/.local/bin/retro-pc
cat > ~/.local/bin/retro-connect <<'RC'
#!/bin/bash
# Asks for your server and PC details, then makes start-menu shortcuts. Run again any time to change them.
# Everything you type is stored only on this Pi (~/.config/retro-lab/config).
C=~/.config/retro-lab/config
getv(){ grep "^$1=" $C | cut -d= -f2-; }
setv(){ if grep -q "^$1=" $C; then sed -i "s|^$1=.*|$1=$2|" $C; else echo "$1=$2" >> $C; fi; }
ask(){ local cur d v; cur=$(getv "$2"); d=${cur:-$3}; read -r -p "$1 [${d:-none}]: " v
  if [ "$v" = "-" ]; then setv "$2" ""; elif [ -n "$v" ]; then setv "$2" "$v"; elif [ -z "$cur" ] && [ -n "$3" ]; then setv "$2" "$3"; fi; }
REB=0; [ "$1" = "--rebuild" ] && REB=1
if [ $REB = 0 ]; then
echo "Press Enter to keep what's shown. Type - to clear an answer."
echo
ask "Home server: its Tailscale name or 100.x address (works anywhere)" server_name zimaboard2
ask "Home server: its home-network address (used when you're home, optional)" server_lan
ask "Home server: name of the shared folder for file access" server_share
ask "Jellyfin port" port_jellyfin 8097
ask "Seerr port" port_seerr 5055
read -r -p "Also add shortcuts for Radarr, Sonarr, Prowlarr, Deluge and Maintainerr? [Y/n] " x
[ "$x" = "n" ] || [ "$x" = "N" ] && setv extras off || setv extras on
ask "Your Windows PC's Tailscale name or address (for remote desktop)" pc_name
ask "Your PC's MAC address, like AA-BB-CC-DD-EE-FF (for Wake My PC, optional)" pc_mac
ask "Your login name on the home server (for Wake My PC, optional)" server_user
fi
A=~/.local/share/applications
rm -f $A/lab-wake.desktop $A/lab-jellyfin.desktop $A/lab-seerr.desktop $A/lab-pc.desktop $A/lab-files.desktop $A/lab-srv-*.desktop
mk(){ printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\nIcon=%s\nCategories=Network;\n' "$2" "$3" "$4" > $A/$1.desktop; }
if [ -n "$(getv server_name)$(getv server_lan)" ]; then
  mk lab-jellyfin "Jellyfin" "$HOME/.local/bin/retro-open $(getv port_jellyfin)" video-display
  mk lab-seerr "Seerr (request movies)" "$HOME/.local/bin/retro-open $(getv port_seerr)" folder-video
  if [ "$(getv extras)" = "on" ]; then
    mk lab-srv-radarr "Server: Radarr" "$HOME/.local/bin/retro-open 7878" applications-multimedia
    mk lab-srv-sonarr "Server: Sonarr" "$HOME/.local/bin/retro-open 8989" applications-multimedia
    mk lab-srv-prowlarr "Server: Prowlarr" "$HOME/.local/bin/retro-open 9696" applications-internet
    mk lab-srv-deluge "Server: Deluge" "$HOME/.local/bin/retro-open 8112" applications-internet
    mk lab-srv-maintainerr "Server: Maintainerr" "$HOME/.local/bin/retro-open 6246" applications-utilities
  fi
  [ -n "$(getv server_share)" ] && mk lab-files "Files: Home server" "$HOME/.local/bin/retro-files" folder-remote
fi
[ -n "$(getv pc_mac)" ] && [ -n "$(getv server_user)" ] && mk lab-wake "Wake My PC" "x-terminal-emulator -e $HOME/.local/bin/retro-wake" system-shutdown
[ -n "$(getv pc_name)" ] && mk lab-pc "Remote: My PC" "$HOME/.local/bin/retro-pc" computer
echo
if [ $REB = 0 ] && [ -n "$(getv pc_mac)" ] && [ -n "$(getv server_user)" ]; then
  read -r -p "Prepare the home server for Wake My PC now? (do this while you're at home) [y/N] " w
  [ "$w" = "y" ] || [ "$w" = "Y" ] && ~/.local/bin/retro-wake-setup
fi
echo "Done. In the start menu look for: Jellyfin, Seerr, Server: ..., Files: Home server, Remote: My PC."
echo "Tip: to reach your home server from anywhere, it must be signed in to Tailscale (yours already is)."
RC
chmod +x ~/.local/bin/retro-connect
cat > ~/.local/bin/retro-send <<'SD'
#!/bin/bash
# Send files to your PC over Tailscale (Taildrop). Your PC must have Tailscale and be signed in to the same account.
PC=$(grep '^pc_name=' ~/.config/retro-lab/config | cut -d= -f2-)
[ -z "$PC" ] && { zenity --error --text="Run retro-connect first to set your PC's name."; exit 1; }
F=$(zenity --file-selection --multiple --separator=$'\n' --title="Send to $PC") || exit 0
echo "$F" | while read -r f; do tailscale file cp "$f" "$PC:" && notify-send "Sent" "$(basename "$f") to $PC" 2>/dev/null; done
SD
chmod +x ~/.local/bin/retro-send
cat > ~/.local/share/applications/lab-send.desktop <<'DT'
[Desktop Entry]
Type=Application
Name=Send file to my PC
Exec=/bin/bash -c "$HOME/.local/bin/retro-send"
Icon=document-send
Categories=Network;
DT
mkdir -p ~/Downloads/Received
cat > ~/.local/share/applications/lab-received.desktop <<'DT'
[Desktop Entry]
Type=Application
Name=Files received from my PC
Exec=pcmanfm %h/Downloads/Received
Icon=folder-download
Categories=Network;
DT
cat > ~/.config/autostart/taildrop-receive.desktop <<'DT'
[Desktop Entry]
Type=Application
Name=Taildrop Receive
Exec=/bin/bash -c "while true; do tailscale file get --loop --conflict=rename $HOME/Downloads/Received; sleep 10; done"
DT
cat > ~/.local/share/applications/lab-update-system.desktop <<'DT'
[Desktop Entry]
Type=Application
Name=Update the whole system
Exec=x-terminal-emulator -e bash -c "sudo apt update && sudo apt full-upgrade -y; echo; read -p 'Done. Press Enter to close.'"
Icon=system-software-update
Categories=System;
DT

# --- Game library on the home server (Retro Console reads ROMs over the network)
cat > ~/.local/bin/retro-roms <<'RR'
#!/bin/bash
# retro-roms         : connect the home server's game library (asks for the server's SMB login)
# retro-roms off     : disconnect it
C=~/.config/retro-lab/config; M=/mnt/zimagames
getv(){ grep "^$1=" $C | cut -d= -f2-; }
if [ "$1" = off ]; then
  sudo sed -i "\|$M|d" /etc/fstab; sudo systemctl daemon-reload; sudo systemctl stop mnt-zimagames.automount 2>/dev/null; sudo umount -l $M 2>/dev/null
  echo "Game library disconnected. Retro Console uses ~/ROMs on this Pi."; exit 0
fi
H=$(getv server_name); [ -z "$H" ] && H=$(getv server_lan); S=$(getv server_share)
if [ -z "$H" ] || [ -z "$S" ]; then echo "Set your server name and shared folder name first (Lab Settings > Home server & PC, or run retro-connect)."; exit 1; fi
echo "Connecting to //$H/$S"
read -r -p "Server login name [$(getv server_user)]: " U; U=${U:-$(getv server_user)}
read -r -s -p "Server password: " P; echo
sudo apt-get install -y cifs-utils >/dev/null
sudo mkdir -p /etc/aperture $M
printf 'username=%s\npassword=%s\n' "$U" "$P" | sudo tee /etc/aperture/smb-credentials >/dev/null
sudo chown root:root /etc/aperture/smb-credentials; sudo chmod 600 /etc/aperture/smb-credentials
unset P
sudo sed -i "\|$M|d" /etc/fstab
echo "//$H/$S $M cifs credentials=/etc/aperture/smb-credentials,uid=$(id -u),gid=$(id -g),iocharset=utf8,vers=3.0,file_mode=0664,dir_mode=0775,_netdev,nofail,noauto,x-systemd.automount,x-systemd.idle-timeout=120,x-systemd.mount-timeout=8 0 0" | sudo tee -a /etc/fstab >/dev/null
sudo systemctl daemon-reload; sudo systemctl restart mnt-zimagames.automount
if timeout 15 ls $M >/dev/null 2>&1; then
  mkdir -p $M/roms/{NES,SNES,Genesis,GameBoy,GBA,N64,PSX,PCEngine,Dreamcast}
  echo "Connected. Your game folders are on the server in: roms/ (NES, SNES, Genesis, GameBoy, GBA, N64, PSX, PCEngine, Dreamcast)."
  echo "Copy games into them from your PC, then open Retro Console."
else
  echo "Couldn't reach the server share. Check the name, the share name and the login, then run this again."
  echo "(The setting is saved; it never slows down start-up if the server is off.)"
fi
RR
chmod +x ~/.local/bin/retro-roms
cat > ~/.local/bin/retro-console <<'RCN'
#!/bin/bash
# Opens RetroArch with the server's game library if it is reachable, otherwise the local ~/ROMs folder
M=/mnt/zimagames; D=~/ROMs
if grep -q "$M" /etc/fstab 2>/dev/null && timeout 6 ls "$M/roms" >/dev/null 2>&1; then D=$M/roms; fi
sed -i "s|^rgui_browser_directory.*|rgui_browser_directory = \"$D\"|" ~/.config/retroarch/retroarch.cfg 2>/dev/null
exec retroarch "$@"
RCN
chmod +x ~/.local/bin/retro-console
grep -q '^libretro_directory' ~/.config/retroarch/retroarch.cfg 2>/dev/null || printf 'libretro_directory = "%s/.local/share/retro-lab/cores"\nlibretro_info_path = "/usr/share/libretro/info"\n' "$HOME" >> ~/.config/retroarch/retroarch.cfg
sed -i 's|^Exec=retroarch$|Exec=/bin/bash -c "$HOME/.local/bin/retro-console"|' ~/.local/share/applications/retro-console.desktop

# --- retro-login / retro-lock
cat > ~/.local/bin/retro-login <<'RL'
#!/bin/bash
# retro-login password = ask for your password at start-up;  retro-login auto = log in automatically
case "$1" in
 password) sudo raspi-config nonint do_boot_behaviour B3 && echo "Password required at start-up.";;
 auto) sudo raspi-config nonint do_boot_behaviour B4 && echo "Automatic login on (anyone who has the Pi can open it).";;
 *) echo "Use: retro-login password | auto";;
esac
RL
chmod +x ~/.local/bin/retro-login
cat > ~/.local/bin/retro-lock <<'RK'
#!/bin/bash
# retro-lock <minutes> | off : lock the screen after that many idle minutes
F=~/.config/autostart/lab-idle-lock.desktop
pkill -x swayidle 2>/dev/null || true
case "$1" in
 off) rm -f "$F"; echo "Auto-lock off.";;
 ''|*[!0-9]*) echo "Use: retro-lock <minutes> | off"; exit 1;;
 *) mkdir -p ~/.config/autostart
    printf '[Desktop Entry]\nType=Application\nName=Lab Screen Lock\nExec=swayidle -w timeout %s '"'"'swaylock -f -c 2a1b14'"'"' before-sleep '"'"'swaylock -f -c 2a1b14'"'"'\n' $(($1*60)) > "$F"
    (nohup swayidle -w timeout $(($1*60)) 'swaylock -f -c 2a1b14' before-sleep 'swaylock -f -c 2a1b14' >/dev/null 2>&1 &)
    echo "Screen locks after $1 minutes.";;
esac
RK
chmod +x ~/.local/bin/retro-lock

# --- retro-secure: travel-safe hardening
cat > ~/.local/bin/retro-secure <<'SE'
#!/bin/bash
# Locks the Pi down so it can be used on hotel / cafe / airport Wi-Fi. Safe to run again.
set -e
echo "1/5 Automatic security updates"
sudo apt-get install -y unattended-upgrades >/dev/null
printf 'APT::Periodic::Update-Package-Lists "1";\nAPT::Periodic::Unattended-Upgrade "1";\nAPT::Periodic::AutocleanInterval "7";\n' | sudo tee /etc/apt/apt.conf.d/20auto-upgrades >/dev/null
echo "2/5 Firewall: nothing can connect to the Pi except through Tailscale"
sudo apt-get install -y ufw >/dev/null
sudo ufw --force reset >/dev/null
sudo ufw default deny incoming >/dev/null
sudo ufw default allow outgoing >/dev/null
sudo ufw allow in on tailscale0 >/dev/null
sudo ufw --force enable >/dev/null
echo "3/5 Remote terminal: Tailscale SSH only (no passwords, no open SSH port)"
sudo systemctl disable --now ssh 2>/dev/null || true
if tailscale status >/dev/null 2>&1; then sudo tailscale set --ssh --operator="$USER" && echo "   Tailscale SSH on."; else echo "   Tailscale isn't signed in yet. Run: sudo tailscale up   then run retro-secure again."; fi
echo "4/5 Screen lock after 10 minutes idle"
~/.local/bin/retro-lock 10
cat > ~/.local/share/applications/lab-lock.desktop <<'DT'
[Desktop Entry]
Type=Application
Name=Lock screen
Exec=swaylock -f -c 2a1b14
Icon=system-lock-screen
Categories=System;
DT
echo "5/5 Ask for your password at start-up (so a lost Pi is not open)"
read -r -p "   Require a password to log in? [Y/n] " a
if [ "$a" != "n" ] && [ "$a" != "N" ]; then ~/.local/bin/retro-login password; fi
echo
echo "Secure. Firewall: $(sudo ufw status | head -1)"
echo "If you ever lose the Pi: log in at login.tailscale.com, open Machines, and remove it."
SE
chmod +x ~/.local/bin/retro-secure

echo "== 8/9 Vivaldi (browser) =="
if ! command -v vivaldi-stable >/dev/null; then
  curl -fsSL https://repo.vivaldi.com/archive/linux_signing_key.pub | sudo gpg --dearmor --yes -o /usr/share/keyrings/vivaldi-browser.gpg
  echo "deb [signed-by=/usr/share/keyrings/vivaldi-browser.gpg arch=$(dpkg --print-architecture)] https://repo.vivaldi.com/archive/deb/ stable main" | sudo tee /etc/apt/sources.list.d/vivaldi-archive.list >/dev/null
  sudo apt-get update && sudo apt-get install -y vivaldi-stable || echo "(Vivaldi install failed, everything else still works)"
fi
xdg-settings set default-web-browser vivaldi-stable.desktop 2>/dev/null || true
# Vivaldi loses the keyboard on the Pi's Wayland desktop, so run it through X11
if [ -f /usr/share/applications/vivaldi-stable.desktop ]; then
  cp /usr/share/applications/vivaldi-stable.desktop ~/.local/share/applications/vivaldi-stable.desktop
  sed -i 's|^\(Exec=[^ ]*vivaldi-stable\)\( --ozone-platform=x11\)*|\1 --ozone-platform=x11|' ~/.local/share/applications/vivaldi-stable.desktop
fi
cat > ~/.local/bin/retro-fix-vivaldi <<'FV'
#!/bin/bash
# Only needed if Vivaldi crashes on start. Switches the Pi 5 to the 4K-page kernel, which Chromium-type browsers like better.
grep -q '^kernel=kernel8.img' /boot/firmware/config.txt || echo 'kernel=kernel8.img' | sudo tee -a /boot/firmware/config.txt
echo "Done. Restart with: sudo reboot"
FV
chmod +x ~/.local/bin/retro-fix-vivaldi

echo "== 9/9 Proton VPN =="
if ! command -v protonvpn-app >/dev/null && ! dpkg -s proton-vpn-gnome-desktop >/dev/null 2>&1 && ! dpkg -s proton-vpn-gtk-app >/dev/null 2>&1; then
  sudo apt-get install -y extrepo && sudo extrepo enable protonvpn || true
  sudo sed -i 's/^Architectures:.*/Architectures: arm64/' /etc/apt/sources.list.d/extrepo_protonvpn.sources 2>/dev/null || true
  sudo apt-get update
  sudo apt-get install -y proton-vpn-gnome-desktop || sudo apt-get install -y proton-vpn-gtk-app || echo "(Proton VPN install failed, see notes from Claude)"
fi

~/.local/bin/retro-lab-render static /tmp/aperture-assets >/dev/null 2>&1 || true
cat > ~/.local/bin/retro-setup-steps <<'STEPS'
#!/bin/bash
echo "Three short setup steps."
echo
if ! tailscale status >/dev/null 2>&1; then
  echo "STEP 1: Sign in to Tailscale. Open the link it shows and log in."
  sudo tailscale up --operator="$USER" || true
fi
echo
echo "STEP 2: Tell me about your home server and PC (Enter to skip any)."
~/.local/bin/retro-connect || true
echo
echo "STEP 3: Travel security."
read -r -p "Apply security hardening now? [Y/n] " a
if [ "$a" != "n" ] && [ "$a" != "N" ]; then ~/.local/bin/retro-secure || true; fi
rm -f ~/.config/autostart/lab-first-login.desktop
echo
read -r -p "All set. Press Enter to close."
STEPS
chmod +x ~/.local/bin/retro-setup-steps
echo
if [ -n "$APERTURE_UNATTENDED" ]; then
  # image first boot: the setup steps run in a terminal the first time the desktop opens
  cat > ~/.config/autostart/lab-first-login.desktop <<'DT'
[Desktop Entry]
Type=Application
Name=Lab first-time setup
Exec=sh -c "sleep 8; x-terminal-emulator -e bash -lc $HOME/.local/bin/retro-setup-steps"
DT
  echo "Install finished."
else
  echo "ALL DONE with the install."
  ~/.local/bin/retro-setup-steps
  echo
  echo "Finally restart the Pi:  sudo reboot"
  echo "Later:  Lab Settings (start menu)  |  retro-update (new theme)  |  retro-theme day|dusk|night|auto  |  retro-sounds on|off  |  retro-connect  |  retro-secure"
fi
