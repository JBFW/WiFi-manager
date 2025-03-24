#!/bin/sh -x

PATH=/sbin:$PATH; export PATH

CONFIG_DIR=/etc/wpa_supplicant
CTL_DIR=/run/wpa_supplicant

exec >> /var/log/wpa_auto.log
exec 2>&1

check_config_file(){
  if [ -n "${CONFIG_FILE}" ] && [ ! -f "${CONFIG_FILE}" ] ; then
    (
      echo "ctrl_interface=${CTL_DIR}"
		  echo "update_config=1"
		  echo "country=US"
    ) > "${CONFIG_FILE}"
  fi
}

which iw
NO_IW=$?

if [ ${NO_IW} ] ; then
  IFACES=$(iwconfig 2>&1 | grep IEEE | awk '{ print $1 }')
else
  IFACES=$(iw dev | grep Interface | awk '{ print $2 }')
fi

for i in ${IFACES} ; do
  echo ${i}

  CONFIG_FILE=${CONFIG_DIR}/iface_${i}.conf 

  x=$(ps ax | grep -v grep | grep "${CONFIG_FILE}" | wc -l)
  if [ "$x" -eq "0" ] ; then
    echo "No wpa_supplicant for ${i} found"

    # Включим питание на всякий случай
    if [ ${NO_IW} ] ; then
      iwconfig ${i} power on
    else
      iw dev ${i} set power_save off
    fi
   
    check_config_file

    # Поднимаем интерфейс
    ip link set "${i}" up

    # Запускаем wpa_supplicant
    wpa_supplicant -i "${i}" -c "${CONFIG_FILE}" -B -C ${CTL_DIR}
    chown -R root:netdev ${CTL_DIR}

    # Запускаем wpa_cli, чтобы следить за событиями и запускать DHCP при подключении
    wpa_cli -a /etc/wpa_supplicant/wpa_dhcp.sh -i ${i} -B

  fi

done

exit



