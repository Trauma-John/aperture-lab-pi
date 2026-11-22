#!/bin/bash -e
install -d "${ROOTFS_DIR}/opt/aperture"
install -m 755 files/retro-lab-install.sh "${ROOTFS_DIR}/opt/aperture/retro-lab-install.sh"
install -m 755 files/aperture-firstboot "${ROOTFS_DIR}/usr/local/sbin/aperture-firstboot"
install -m 644 files/aperture-firstboot.service "${ROOTFS_DIR}/etc/systemd/system/aperture-firstboot.service"
install -d "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d" "${ROOTFS_DIR}/etc/xdg/labwc"
install -m 644 files/50-aperture.conf "${ROOTFS_DIR}/etc/lightdm/lightdm.conf.d/50-aperture.conf"
install -m 755 files/labwc-autostart "${ROOTFS_DIR}/etc/xdg/labwc/autostart"
