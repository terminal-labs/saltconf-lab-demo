# /srv/salt/tshark/init.sls

start_tshark:
  cmd.run:
    - name: "tshark -i eth0 -F libpcap -t u -f 'tcp dst port 80' -w '/var/tmp/tshark.pcap' -q"
    - bg: True