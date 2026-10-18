#!/bin/sh
# busybox udhcpc lease handler for the ramdisk. It must call busybox by path:
# the applet symlinks are not installed when udhcpc runs.
B=/bin/busybox
case "$1" in
  deconfig)
    $B ip addr flush dev "$interface"
    ;;
  bound|renew)
    $B ip addr add "$ip/${mask:-24}" dev "$interface"
    [ -n "$router" ] && $B ip route replace default via "$router" dev "$interface"
    [ -n "$dns" ] && echo "nameserver $dns" > /etc/resolv.conf
    ;;
esac
