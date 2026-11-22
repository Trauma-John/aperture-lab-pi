# Aperture Lab for Raspberry Pi

A retro 1970s lab-style desktop for the Pi 5: Lab Desk widgets, custom taskbar and start menu, themed boot and login screens, sounds, Tailscale remote access and travel security.

## Option 1: install on an existing Raspberry Pi OS
Run as your normal user (not sudo):

    bash retro-lab-install.sh

Afterwards `retro-update` fetches the newest version from this repo.

## Option 2: flash a ready-made image
Download the newest `.img.xz` from the Releases page, then use Raspberry Pi Imager > Choose OS > Use custom. On first boot a short wizard sets up your user, Wi-Fi and the desktop (needs internet).

The image is built by GitHub Actions (`.github/workflows/build-image.yml`) with pi-gen.
