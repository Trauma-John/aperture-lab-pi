#!/bin/bash
# Aperture lab: restyle the login screen and remove the stock Pi desktop flash. Run as your normal user: bash fix-login.sh
set -e
[ "$(id -u)" = "0" ] && { echo "Run as your normal user, not sudo."; exit 1; }
mkdir -p ~/.local/bin ~/.local/share/retro-lab
sudo mkdir -p /usr/share/aperture
python3 ~/.local/bin/retro-lab-render static /tmp/aperture-assets
sudo cp /tmp/aperture-assets/login.png /tmp/aperture-assets/wall.png /tmp/aperture-assets/logo.png /usr/share/aperture/
# Themed login box (dark rounded panel, warm colours). Logo sits above the box.
sudo mkdir -p /usr/share/themes/ApertureLogin/gtk-3.0
printf '[Desktop Entry]\nType=X-GNOME-Metatheme\nName=ApertureLogin\nComment=Aperture Laboratories login\n\n[X-GNOME-Metatheme]\nGtkTheme=ApertureLogin\n' | sudo tee /usr/share/themes/ApertureLogin/index.theme >/dev/null
sudo tee /usr/share/themes/ApertureLogin/gtk-3.0/gtk.css >/dev/null <<'GTK'
* { font-family: "DejaVu Serif", serif; font-size: 16px; font-weight: bold; color: #f6e7c1; text-shadow: none; box-shadow: none; }
#login_window, #login-window { background-color: #2a1b14; background-image: none; border: none; border-radius: 0; padding: 0; }
#login_window > *, #login-window > * { margin: 12px; padding: 20px; border: 3px solid #e0873a; border-radius: 30px; background-color: #2a1b14; background-image: linear-gradient(#3a2518, #2a1b14); }
#content_frame, #login_frame, #login_box, #user_box { border: none; background: none; background-image: none; padding: 0; margin: 0; }
#panel_window, #panel-window { background-color: rgba(42,27,20,0.0); background-image: none; border: none; }
image { opacity: 0; margin: 0 -105px 0 0; }
combobox, combobox button, combobox * { background-image: none; background-color: transparent; border: none; color: #e7c06a; font-style: italic; }
entry { background-color: #1c110b; background-image: none; color: #f6e7c1; caret-color: #e0873a; border: 2px solid #e0873a; border-radius: 16px; padding: 8px 14px; min-height: 24px; }
entry:focus { border-color: #ffd08a; }
button { background-color: #e0873a; background-image: none; border: 2px solid #ffd08a; border-radius: 16px; padding: 7px 22px; }
button label { color: #2a1b14; }
button:hover { background-color: #ffd08a; }
menu, menuitem, popover { background-color: #3a2518; color: #f6e7c1; }
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
sz = Math.Int(Window.GetHeight() / 40);
if (sz < 16) sz = 16;
font = "DejaVu Sans Mono Bold " + sz;
x0 = Window.GetWidth() * 0.08;
y0 = Window.GetHeight() * 0.10;
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
counter = 0;
fun refresh() {
  counter++;
  shown = Math.Int(counter / 14);
  if (shown > n - 1) shown = n - 1;
  for (i = 0; i <= shown; i++) spr[i].SetOpacity(1);
  cur.SetPosition(x0 + img[shown].GetWidth() + 6, y0 + shown * step, 10);
  ph = counter - 50 * Math.Int(counter / 50);
  if (ph < 28) cur.SetOpacity(1); else cur.SetOpacity(0);
}
Plymouth.SetRefreshFunction(refresh);
PS
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
else
  ~/.local/bin/retro-sound startup
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
echo "Done. Restart now:  sudo reboot"
