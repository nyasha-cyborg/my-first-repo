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
# GPU: Mesa tegra+nouveau segfaults on the first draw (notes/gpu.md): software rendering until fixed.
# greetd starts the greeter with a clean PAM environment, so this must be in /etc/environment (pam_env).
for kv in GBM_ALWAYS_SOFTWARE=1 LIBGL_ALWAYS_SOFTWARE=1 WLR_RENDERER=pixman; do
	grep -q "^${kv%%=*}=" $R/etc/environment 2>/dev/null || echo "$kv" >> $R/etc/environment
done
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
# kernel log that survives a hang/reset: /var/log/kmsg.log, synced every 5 s (debug period)
mkdir -p $R/etc/local.d
cat > $R/etc/local.d/n9-kmsg.start <<'EOF'
#!/bin/sh
# n9: keep the kernel log across hangs (rotates at boot, previous boot in kmsg.log.1)
[ -f /var/log/kmsg.log ] && mv /var/log/kmsg.log /var/log/kmsg.log.1
(cat /proc/kmsg >> /var/log/kmsg.log) </dev/null >/dev/null 2>&1 &
(while true; do sync /var/log/kmsg.log 2>/dev/null || sync; sleep 5; done) </dev/null >/dev/null 2>&1 &
EOF
chmod +x $R/etc/local.d/n9-kmsg.start
c rc-update add local default >/dev/null 2>&1 || true
# the Phosh greeter only once the display hang is understood: start it by hand (rc-service greetd start)
GREETD_AUTOSTART=${GREETD_AUTOSTART:-0}

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
