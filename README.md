**Simple WiFi Connection Management Program**

This is a lightweight program designed for managing WiFi connections without requiring a Desktop Environment or systemd.

### Overview
The program utilizes the standard `wpa_supplicant` for managing WiFi connections. A script is used to configure and manage networks, allowing users to create and remove connections easily. Automatic startup upon WiFi adapter connection is handled by the standard `udevd`.

Simultaneous operation with multiple WiFi adapters is supported.

### Installation
To install the necessary dependencies, execute the following command:

```sh
sudo apt install wpasupplicant libgtk3-perl isc-dhcp-client iw
```

Alternatively, `iwconfig` can be used instead of `iw` if required.

Next, copy the provided files to their appropriate locations in the file system. If a WiFi adapter is already connected or integrated, you can manually start the program with:

```sh
sudo /etc/wpa_supplicant/start_wpa_supplicant.sh
wifi_ctl.pl
```

After a system reboot, the scripts should automatically start when a WiFi adapter is connected.

### Log Files
Execution logs are available at:
- `/var/log/wpa_auto.log`
- `/var/log/wpa_dhcp.log`

These logs can be checked for debugging and monitoring purposes.


