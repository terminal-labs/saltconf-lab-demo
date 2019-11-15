install_tshark:
  pkg.installed:
    - name: tshark

install_dpkt:
  pip.installed:
    - name: dpkt

manage_pcap_watch_beacon_config:
  file.managed:
    - name: /etc/salt/minion.d/beacons.conf
    - source: salt://conf/minion/beacons.conf

restart_minion_00:
  cmd.run:
    - name: systemctl restart salt-minion
    - bg: True

start_tshark_process:
  cmd.run:
    - name: "tshark -i eth0 -F libpcap -t u -f 'tcp dst port 80' -w '/var/tmp/tshark.pcap'"
    - bg: True
