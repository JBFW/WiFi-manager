#!/bin/sh

PATH=/sbin:$PATH; export PATH

exec >> /var/log/wpa_dhcp.log
exec 2>&1

INTERFACE="$1"
EVENT="$2"

echo "Event received: $EVENT on interface $INTERFACE" 

if [ "$EVENT" = "CONNECTED" ]; then
  echo "Wi-Fi connected on $INTERFACE, requesting DHCP..."
  dhclient -r "$INTERFACE"
  dhclient "$INTERFACE"
fi

