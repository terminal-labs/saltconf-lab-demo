"""
Custom beacon to monitor network traffic from a pcap file.
If rate_limit is exceeded, the rate and the violater's src_ip will be sent with the event.

Example minion config:

# /etc/salt/minion.d/beacons.conf
beacons:
  pcap_watch:
    - pcap_file: /var/tmp/tshark.pcap
    - rate_limit: 100  # packets / sec
    - pcap_period:  1  # sec of pcap data to use every beacon interval


Make sure to launch a separate process writing to the pcap_file specified.
Example with tshark:

tshark -t u -w /var/tmp/tshark.pcap -F libpcap -i eth0 -f 'tcp dst port 80' -q &

"""
import ipaddress
import logging
import os
import time

from dpkt.pcap import Reader
from dpkt.ethernet import Ethernet

log = logging.getLogger(__name__)


def validate(config):
    _config = {}
    list(map(_config.update, config))
    if not os.path.exists(_config['pcap_file']):
        return False, "{0} file does not exist".format(_config['pcap_file'])
    try:
        float(_config['pcap_period'])
        float(_config['rate_limit'])
    except ValueError as e:
        return False, e

    return True, "pcap_watch config is valid"


def beacon(config):
    _config = {}
    list(map(_config.update, config))
    ret = []
    with open(_config['pcap_file']) as pcap_file:
        pcap_reader = Reader(pcap_file)
        packets = pcap_reader.readpkts()
    packets.sort(key=lambda x: x[0], reverse=True)
    # find number of packets within the last pcap_period, for each ip, resp.
    now = time.time()
    ip_packet_count = {}
    for timestamp, buf in packets:
        if timestamp > now - float(_config['pcap_period']):
            eth = Ethernet(buf)
            ip = ipaddress.ip_address(bytes(eth.data.src)).compressed
            if ip not in ip_packet_count.keys():
                ip_packet_count[ip] = 1
            else:
                ip_packet_count[ip] += 1
            continue
        else:
            break
    for ip in ip_packet_count.keys():
        rate = ip_packet_count[ip] / float(_config['pcap_period'])
        if rate >= _config['rate_limit']:
            ret.append({'rate': rate, 'src_ip': ip})
    return ret
