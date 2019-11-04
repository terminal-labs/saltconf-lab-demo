## DDOS mitigation

Let's use Salt's event infrastructure to identify abnormal network activity, notify a system administrator, and
mitgate the problem automatically. For more info on Salt's event system see the [docs](https://docs.saltstack.com/en/latest/topics/event/index.html)

The main components we will use are called _reactors_ and _beacons_. Beacons are set up to run on an interval (default 1 sec)
to monitor system behavior and issue events. Salt comes with many built in beacons like we've seen already, but we
can also easily create our own with the help of Salt's loader system.

The full demo files are located on [github]().

Let's say we are running an Apache web server on port 80 and we want to determine if we are under DDOS attack.
To do this we will use [tshark](https://www.wireshark.org/docs/man-pages/tshark.html).
First, we will start a tshark process which will capture incoming tcp packets on port 80 and save them to a file.
Our custom beacon is written to inspect this file and determine if the packet rate is higher than the limit specified
and issue an event.

Our tshark process is launched with the following command:
```
tshark -i lo -F libpcap -t u -f 'tcp dst port 80' -w /var/tmp/tshark.pcap -q &
```

And our minion config will need the following beacon configuration:
```
# /etc/salt/minion.d/beacons.conf

beacons:
  pcap_watch:
    pcap_file: /var/tmp/tshark.pcap
    rate_limit: 100  # packets/sec
    pcap_period: 1  # sec

```

We can use apache bench to trigger the beacon.

```
ab -n 5000 http://<ip>
```

We should now see the text to the configured sys_admin_phone_number

TODO: Reactor remediation...