#!/bin/bash
# Aperture lab: restyle the login screen. Run as your normal user:  bash fix-login.sh
set -e
[ "$(id -u)" = "0" ] && { echo "Run as your normal user, not sudo."; exit 1; }
sudo mkdir -p /usr/share/aperture
python3 ~/.local/bin/retro-lab-render static /tmp/aperture-assets
sudo cp /tmp/aperture-assets/login.png /tmp/aperture-assets/wall.png /tmp/aperture-assets/logo.png /usr/share/aperture/
# Themed login box (dark rounded panel, warm colours). Logo sits above the box.
sudo mkdir -p /usr/share/themes/ApertureLogin/gtk-3.0
printf '[Desktop Entry]\nType=X-GNOME-Metatheme\nName=ApertureLogin\nComment=Aperture Laboratories login\n\n[X-GNOME-Metatheme]\nGtkTheme=ApertureLogin\n' | sudo tee /usr/share/themes/ApertureLogin/index.theme >/dev/null
sudo tee /usr/share/themes/ApertureLogin/gtk-3.0/gtk.css >/dev/null <<'GTK'
* { font-family: "DejaVu Serif", serif; font-size: 16px; font-weight: bold; color: #f6e7c1; text-shadow: none; box-shadow: none; -gtk-icon-shadow: none; }
#login_window, #login-window, #login_frame, #content_frame, #login_box {
  background-color: #2a1b14; background-image: linear-gradient(#3a2518, #2a1b14); border-radius: 30px; border: 3px solid #e0873a; padding: 16px; }
#content_frame { border: 1.5px solid #8a5a38; background-image: none; background-color: transparent; }
#panel_window, #panel-window { background-color: rgba(42,27,20,0.0); background-image: none; }
image { opacity: 0; min-width: 0; min-height: 0; -gtk-icon-transform: scale(0.01); }
combobox, combobox button, combobox * { background-image: none; background-color: transparent; border: none; color: #e7c06a; font-style: italic; }
entry { background-color: #f3e6c6; background-image: none; color: #2a1b14; caret-color: #c8641e; border: 2px solid #e0873a; border-radius: 16px; padding: 8px 14px; min-height: 24px; }
entry:focus { border-color: #fff0cf; }
button { background-color: #f3e6c6; background-image: none; color: #4a2a16; border: 2px solid #e0873a; border-radius: 16px; padding: 7px 20px; }
button label { color: #4a2a16; }
button:hover { background-color: #e0873a; }
button:hover label { color: #2a1b14; }
menu, menuitem, popover { background-color: #3a2518; color: #f6e7c1; }
menuitem:hover { background-color: #e0873a; color: #2a1b14; }
GTK
# Rename the session so it no longer says "Raspberry Pi OS"
for s in /usr/share/wayland-sessions/*.desktop /usr/share/xsessions/*.desktop; do
  [ -f "$s" ] && sudo sed -i '/^Name\(\[.*\]\)\?=.*\(Raspberry\|labwc\|Labwc\)/ s/=.*/=Aperture Lab/' "$s" || true
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
echo "Done. Lock or restart to see the new login screen:  sudo reboot"
