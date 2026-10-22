#!/bin/sh
# Start the LTE data call and configure the network interface (run after mdm-boot.sh).
#   APN     access point name (required; Skinny/Spark NZ: wapaccess.co.nz)
#   DEV/IF  QMI node and its netdev (default /dev/cdc-wdm0 / wwan0)
#   METRIC  metric of the default route via LTE (default 200: an existing WiFi default route stays preferred)
#   QC      qmi-connect binary (default next to this script, else /bin/qmi-connect)
# Writes the call settings to /tmp/mdm-net.env (and /etc/resolv.conf only if RESOLV=1).  Never writes any partition.
APN=${APN:?set APN}
DEV=${DEV:-/dev/cdc-wdm0}
IF=${IF:-wwan0}
HERE=$(dirname "$0")
QC=${QC:-$HERE/qmi-connect}
[ -x "$QC" ] || QC=/bin/qmi-connect
say() { echo "mdm-net: $*"; }

# raw IP on the host side must match the modem's data format and can only change while the link is down
ip link set "$IF" down
echo Y > /sys/class/net/"$IF"/qmi/raw_ip || { say "cannot set raw_ip on $IF"; exit 1; }
OUT=$("$QC" "$DEV" "$APN") || { say "data call failed"; exit 2; }
eval "$OUT"
[ -n "$QMI_IP" ] && [ -n "$QMI_GW" ] || { say "no IP settings from the modem"; exit 3; }
echo "$OUT" > /tmp/mdm-net.env
ip addr flush dev "$IF"
ip addr add "$QMI_IP/$QMI_PREFIX" dev "$IF"
ip link set "$IF" mtu "$QMI_MTU" up
ip route add default via "$QMI_GW" dev "$IF" metric "${METRIC:-200}"
if [ "$RESOLV" = 1 ]; then
	{ [ -n "$QMI_DNS1" ] && echo "nameserver $QMI_DNS1"; [ -n "$QMI_DNS2" ] && echo "nameserver $QMI_DNS2"; } > /etc/resolv.conf
fi
say "$IF up: $QMI_IP/$QMI_PREFIX gw $QMI_GW dns $QMI_DNS1 $QMI_DNS2 mtu $QMI_MTU"
