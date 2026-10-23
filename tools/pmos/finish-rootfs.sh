#!/bin/sh
# Finish the pmOS rootfs after install-rootfs.sh + the overlay: user, services, WiFi, serial console.
# Runs on the tablet in the installer ramdisk with the rootfs mounted at /mnt/pmos.
# WiFi: converts the installer's /etc/wpa_supplicant.conf into a NetworkManager connection (mode 600, never printed).
set -e
R=/mnt/pmos
U=${PMOS_USER:-user}
PW=${PMOS_PASSWORD:-147147}		# pmbootstrap's default; change it on the tablet with passwd
say() { echo "pmos-finish: $*"; }
c() { chroot $R /usr/bin/env PATH=/usr/sbin:/usr/bin:/sbin:/bin "$@"; }

echo n9 > $R/etc/hostname
grep -q "^$U:" $R/etc/passwd || c adduser -D -s /bin/ash -g "" $U
for g in wheel video audio input netdev plugdev feedbackd seat render dialout; do c addgroup $U $g 2>/dev/null || true; done
echo "$U:$PW" | c chpasswd
c chown -R $U:$U /home/$U
[ -f $R/home/$U/.ssh/authorized_keys ] && chmod 700 $R/home/$U/.ssh && chmod 600 $R/home/$U/.ssh/authorized_keys
say "user $U ready"

# SSH: keys only (the default password must not open the tablet to the whole LAN), no root login
mkdir -p $R/etc/ssh/sshd_config.d
printf 'PasswordAuthentication no\nKbdInteractiveAuthentication no\nPermitRootLogin no\n' > $R/etc/ssh/sshd_config.d/50-n9-keys-only.conf
grep -q '^Include /etc/ssh/sshd_config.d' $R/etc/ssh/sshd_config 2>/dev/null || \
	sed -i '1i Include /etc/ssh/sshd_config.d/*.conf' $R/etc/ssh/sshd_config
say "sshd: key login only"

# seat for the compositor: phoc's libseat found no backend under greetd (elogind gave the greeter no seat);
# seatd works. (Do not add "openssh" to PKGS: it pulls the non-PAM sshd that rejects pmOS's UsePAM policy.)
c apk add -q seatd seatd-openrc >/dev/null 2>&1 || say "seatd install failed (needs network)"
for u in greetd $U; do c addgroup $u seat 2>/dev/null || true; done
# GPU: stock Mesa's tegra wrapper crashes (notes/gpu.md); the overlay ships a patched Mesa in /opt/mesa-n9
# (tools/pmos/mesa/build-mesa.sh). greetd gives the greeter a clean PAM environment: use /etc/environment.
sed -i '/^GBM_ALWAYS_SOFTWARE=/d; /^LIBGL_ALWAYS_SOFTWARE=/d; /^WLR_RENDERER=/d; /^LD_LIBRARY_PATH=/d' $R/etc/environment 2>/dev/null || true
if [ -f $R/opt/mesa-n9/lib/libgallium-26.1.6.so ]; then
	echo "LD_LIBRARY_PATH=/opt/mesa-n9/lib" >> $R/etc/environment
	say "GPU: patched Mesa from /opt/mesa-n9"
else	# fallback: software rendering (pixman compositor, llvmpipe clients)
	printf 'GBM_ALWAYS_SOFTWARE=1\nLIBGL_ALWAYS_SOFTWARE=1\nWLR_RENDERER=pixman\n' >> $R/etc/environment
	say "GPU: no patched Mesa, software rendering"
fi
# root over SSH with the same key only (passwords stay off)
if [ -f $R/home/$U/.ssh/authorized_keys ]; then
	mkdir -p $R/root/.ssh; cp $R/home/$U/.ssh/authorized_keys $R/root/.ssh/
	chmod 700 $R/root/.ssh; chmod 600 $R/root/.ssh/authorized_keys
	sed -i 's/^PermitRootLogin no/PermitRootLogin prohibit-password/' $R/etc/ssh/sshd_config.d/50-n9-keys-only.conf
fi

# watchdog: the boot cmdline arms tegra_wdt (early_start); busybox watchdog feeds it from the boot runlevel,
# so a hang resets the tablet instead of stranding it (first pmOS boot hung right after phoc's modeset)
if [ -e $R/etc/init.d/watchdog ]; then
	printf 'WATCHDOG_OPTS="-t 10 -T 60"\nWATCHDOG_DEV="/dev/watchdog"\n' > $R/etc/conf.d/watchdog
	c rc-update add watchdog boot >/dev/null 2>&1 && say "watchdog fed from the boot runlevel"
fi
# kernel log that survives a hang/reset, from the start of boot: n9-kmsg (sysinit) -> /var/log/kmsg.log
# (5 s sync, previous boot kept as kmsg.log.1); OpenRC's own log in /var/log/rc.log
rm -f $R/etc/local.d/n9-kmsg.start
[ -x $R/etc/init.d/n9-kmsg ] && ln -sf /etc/init.d/n9-kmsg $R/etc/runlevels/sysinit/n9-kmsg
grep -q '^rc_logger=' $R/etc/rc.conf || echo 'rc_logger="YES"' >> $R/etc/rc.conf
# our n9-modem service drives the modem: ModemManager would fight it, qcserial would claim the boot ROM
# (05c6:9008) that sahara needs; no IIO sensors are exposed on this board
c rc-update del modemmanager default >/dev/null 2>&1 || true
c rc-update del iio-sensor-proxy default >/dev/null 2>&1 || true
mkdir -p $R/etc/modprobe.d
printf '# n9: the modem boot ROM (05c6:9008) is driven by sahara over usbfs\nblacklist qcserial\n' > $R/etc/modprobe.d/n9-modem.conf
# Phosh greeter autostart (GREETD_AUTOSTART=0 to start it by hand; the watchdog covers a hang)
GREETD_AUTOSTART=${GREETD_AUTOSTART:-1}

# services (OpenRC); missing ones are skipped
[ "$GREETD_AUTOSTART" = 1 ] || c rc-update del greetd default >/dev/null 2>&1 || true
for s in sshd seatd networkmanager $([ "$GREETD_AUTOSTART" = 1 ] && echo greetd) n9-modem bluetooth chronyd; do
	[ -e $R/etc/init.d/$s ] && c rc-update add $s default >/dev/null 2>&1 && say "enabled $s"
done
# root autologin on the USB serial gadget (debug console; g_serial is built into the kernel)
if [ -e $R/etc/init.d/agetty ]; then
	ln -sf agetty $R/etc/init.d/agetty.ttyGS0
	echo 'agetty_options="--autologin root --noclear"' > $R/etc/conf.d/agetty.ttyGS0
	echo 'baud="115200"' >> $R/etc/conf.d/agetty.ttyGS0
	c rc-update add agetty.ttyGS0 default >/dev/null 2>&1 && say "serial console on ttyGS0"
fi
grep -q ttyGS0 $R/etc/securetty 2>/dev/null || echo ttyGS0 >> $R/etc/securetty

# WiFi from the installer's wpa_supplicant.conf (first network block)
if [ -f /etc/wpa_supplicant.conf ]; then
	SSID=$(sed -n 's/^[[:space:]]*ssid="\(.*\)"/\1/p' /etc/wpa_supplicant.conf | head -1)
	# psk is either a quoted passphrase or the derived 64-hex key; NetworkManager takes both forms
	PSK=$(sed -n -e 's/^[[:space:]]*psk="\(.*\)"/\1/p' -e 's/^[[:space:]]*psk=\([0-9a-fA-F]\{64\}\)[[:space:]]*$/\1/p' /etc/wpa_supplicant.conf | head -1)
	if [ -n "$SSID" ] && [ -n "$PSK" ]; then
		D=$R/etc/NetworkManager/system-connections
		mkdir -p $D
		umask 077
		printf '[connection]\nid=%s\ntype=wifi\nautoconnect=true\n\n[wifi]\nmode=infrastructure\nssid=%s\n\n[wifi-security]\nkey-mgmt=wpa-psk\npsk=%s\n\n[ipv4]\nmethod=auto\n\n[ipv6]\nmethod=auto\n' \
			"$SSID" "$SSID" "$PSK" > $D/wifi-home.nmconnection
		chmod 600 $D/wifi-home.nmconnection
		say "WiFi connection for the installer's network written"
	fi
fi
# the modem firmware/scripts live in the overlay; set the APN for the inserted SIM
[ -f $R/etc/conf.d/n9-modem ] || printf 'APN="wapaccess.co.nz"\nMETRIC=700\nRESOLV=0\n' > $R/etc/conf.d/n9-modem
sync
say "done"
