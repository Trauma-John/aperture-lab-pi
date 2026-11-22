#!/bin/bash -e
# --- Branding: no Pi OS name anywhere the user can see
sed -i 's/^PRETTY_NAME=.*/PRETTY_NAME="Aperture Lab OS"/; s/^NAME=.*/NAME="Aperture Lab OS"/; s|^HOME_URL=.*|HOME_URL="https://github.com/Trauma-John/aperture-lab-pi"|' /etc/os-release || true
echo "Aperture Laboratories  -  Aperture Lab OS" > /etc/issue
echo "Aperture Laboratories" > /etc/issue.net
rm -f /etc/rpi-issue /etc/motd
echo "aperture-lab" > /etc/hostname
# --- Quiet boot so the amber terminal splash is all you see
for f in /boot/firmware/cmdline.txt /boot/cmdline.txt; do
  [ -f "$f" ] && ! grep -q 'plymouth.ignore-serial-consoles' "$f" && sed -i 's/$/ quiet splash plymouth.ignore-serial-consoles logo.nologo vt.global_cursor_default=0/' "$f" || true
done
for f in /boot/firmware/config.txt /boot/config.txt; do
  [ -f "$f" ] && ! grep -q '^disable_splash' "$f" && echo 'disable_splash=1' >> "$f" || true
done
# --- Services: first-boot wizard runs once, then turns the graphical login on
systemctl disable lightdm 2>/dev/null || true
systemctl enable aperture-firstboot.service
systemctl set-default graphical.target
update-alternatives --install /usr/bin/x-terminal-emulator x-terminal-emulator /usr/bin/foot 50
update-alternatives --set x-terminal-emulator /usr/bin/foot
mkdir -p /var/lib/aperture
