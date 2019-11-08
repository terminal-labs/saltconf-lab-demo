# Lab Procedure

This lab procedure will walk through how to do the following:
- Using a built in beacon / reactor to restore a modified apache config
- Using a (pre-made) custom beacon to monitor for high packet rates on port 80, 
and sending a text message to a sys admin
- Using same custom beacon to instead provide firewall remediation of the potential DDOS attack

## Part 1: Built-in inotify beacon

For this part we will use Apache web server for demonstration. Let's install and configure the service using salt.

In the master config (/etc/salt/master) we see the following:
```
file_roots:
  base:
    - /srv/salt
```
Therefore, this is where salt will look for state files.

Let's make the /srv/salt directory and create a state to install apache.

```
mkdir /srv/salt
```
```
cd /srv/salt
```
```
# /srv/salt/apache.sls

install_apache:
  pkg.installed:
    - name: apache2

run_apache:
  service.running:
    - name: apache2
```

and apply the state to the master
```
salt \*master state.apply apache
```

Test ensure the standard apache landing page is being served on port 80
```
curl localhost | grep "It works!"
```

Let's also see if we can reach this page from the minions.
First identify the master's private ip. We can do this by examining the inet listed by ifconfig on eth0
or by using this fancy bash pipe
```
ifconfig eth0 | grep inet | awk '{print $2}' | cut -f2 | head -n 1
```

Then utilize salt's ```cmd.run``` to curl that ip on all minions:
```
salt \* cmd.run "curl <ip-address> | grep 'It works'"
```

### Managing apache conf

We'd like to have a source of truth for the apache configuration file (located in /etc/apache2/apache2.conf on ubuntu)
Let's make a copy of this file in our salt file_roots and include a state to manage this file with salt.

```
mkdir /srv/salt/files
cp /etc/apache2/apache2.conf /srv/salt/files/apache2.conf
```
```
# /srv/salt/manage_apache.sls

manage_apache_conf:
  file.managed:
    - name: /etc/apache2/apache2.conf
    - source: salt://files/apache2.conf
```

Let's run this state
```
salt \*master state.apply manage_apache
```

We can also make use of a highstate by creating a top file which applies these two states we created.

```
# /srv/salt/top.sls

base:
  '*master':
    - apache
    - manage_apache
```
Run it via
```
salt \*master state.apply
```
or 
```
salt \*master state.highstate
```

### _Automatic management via inotify beacon_

Suppose this apache2.conf gets modified. We may want to automatically restore the managed configuration.
This example can make use of salt's built-in inotify beacon. We can configure the beacon to watch for file modifications,
and if it detects one, fire an event to the salt master's event bus. From there we can write whatever reaction we would like to have.
More on that in a minute first let's set up the inotify beacon.

For more info on beacons see the docs [here](https://docs.saltstack.com/en/develop/topics/beacons/)

In the minion config we can include the following:
```
# /etc/salt/minion.d/beacons.conf

beacons:
  inotfiy:
    - files:
        /etc/apache2/apache2.conf:
          mask:
            - modify
    - disable_during_state_run: True

```

```disable_during_state_run: True``` is very important here to avoid loops, since our reactor will replace this file with the correct version (thus modifying it again)

```inotify``` and ```pyinotify``` must be installed to use the ```inotify``` beacon.


We could install these with apt, but let's write a couple states instead and add to our topfile.

We will need pip:
```
# /srv/salt/python_pip.sls

install_python_pip:
  pkg.installed:
    - name: python-pip
```

And other packages:
```
# /srv/salt/demo_packages.sls

install_inotify:
  pkg.installed:
    - name: inotify-tools

install_pyinotify:
  pip.installed:
    - name: pyinotify
```
Add them to our existing topfile
```
# /srv/salt/top.sls
base:
  '*master':
    - python_pip
    - demo_pkgs
    - apache
    - manage_apache
```

and run it:
```
salt \*master state.highstate
```

Remember to restart the salt master / minion after making configuration changes

```
systemctl restart salt-minion
```

__Try it__ Modify apache.conf and you should be able to see the event on the master event bus using ```salt-run state.event pretty=True``` 

_Configuring the reactor_

Reactors can be configured via /etc/salt/master or in the /etc/salt/master.d directory. 

Let's put our reactor config in /etc/salt/master.d/reactors.conf:
```
# /etc/salt/master.d/reactors.conf
reactor:
  - salt/beacon/*/inotify//etc/apache2/apache2.conf
    - /srv/salt/reactors/call_manage_apache.sls
```

Here we list the event tags to add a reactor for with its sublist being the set of orchestration files to be run when the event occurs. A glob ('*') is being used for the minion_id which we will be able to retrieve from the event data in the orchestration
state as seen in the following.

We need to create the file referenced in the above reactor

```
# /srv/salt/reactors/call_manage_apache.sls
call_manage_apache:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
      - manage_apache_conf

```

This orchestration will instruct the minion to apply the manage_apache state we wrote earlier to the tgt specified by the event data's id key.

Make sure to restart the salt master.
```
systemctl restart salt-master
```

__Try it__ View the event bus while modifying apache2.conf, the file should be replaced with the one being served by salt://files/apache2.conf faster than you can say thorium salt reactor!

## Part 2: Custom beacon to monitor traffic and send text message

Salt's event system can be easily extended with custom beacons! For more information on _how_ to write custom beacons see the doc section [here](https://docs.saltstack.com/en/develop/topics/beacons/#writing-beacon-plugins). For the purpose of this lab session, 
we will use a pre-written custom beacon module.

Create a ```_beacons``` directory in /srv/salt and download the file hosted [here](https://github.com/terminal-labs/saltconf-lab-demo/blob/master/_beacons/pcap_watch.py)

```
mkdir _beacons
cd _beacons
wget https://raw.githubusercontent.com/terminal-labs/saltconf-lab-demo/master/_beacons/pcap_watch.py -O pcap_watch.py
```

This beacon will monitor a pcap file for packets and will send an event if the packet rate exceeds the limit specified for each ip, respectively. It assumes we have configured packet filtering accordingly.

For our purposes, we will use tshark and the following command:
```
tshark -i eth0 -F libpcap -t u -f 'tcp dst port 80' -w /var/tmp/tshark.pcap
```

This will setup monitoring on the eth0 interface, writing the packets to /var/tmp/tshark.pcap using the libpcap library.
It specifies UTC as the timestamp and sets up a filter for tcp packets with destination port 80.

Let's make a state to start this process in the background
```
# /srv/salt/start_tshark_process.sls

start_tshark_process:
  cmd.run:
    - name: "tshark -i eth0 -F libpcap -t u -f 'tcp dst port 80' -w '/var/tmp/tshark.pcap'"
    - bg: True
  
```
Also, we need to make sure thsark is installed. Let's add it to the demo_pkgs state

```
# /srv/salt/demo_pkgs.sls

...

install_tshark:
  pkg.installed:
    - name: tshark

```

And apply our higstate once again:
```
salt \*master state.apply
```
Now we can run our tshark process on the master
```
salt \*master state.apply start_tshark_process
```

Alas, we will also need the [dpkt](https://github.com/kbandla/dpkt) python library and to configure the custom beacon.

First we can add dpkt to demo_pkgs.sls
```
# /srv/salt/demo_pkgs.sls

...

install_dpkt:
  pip.installed:
    - name: dpkt

```
and re-run our highstate
```
salt \*master state.apply
```

We can use the example minion config contained in the docstring of the pcap_watch.py file we alreaded downloaded
in our _beacons folder
```
# /etc/salt/minion.d/beacons.conf

beacons:
  pcap_watch:
    - pcap_file: /var/tmp/tshark.pcap
    - rate_limit: 100  # packets / sec
    - pcap_period: 1   # sec of pcap data to use every beacon interval

```

__Note__ that the pcap_file we created must be specified here

Be sure to sync the beacon and restart the minion

```
salt \*master saltutil.sync_beacons
systemctl restart salt-minion
```

_Twilio text (optional)_

We could view the event as done previously, but let's make it more interesting.
Let's up a reactor to send us a text message via twilio (skip if you don't have a twilio account)

We will need to define some configuration for the twilio module, and we will put that in the pillar.
More info on salt twilio module [here](https://docs.saltstack.com/en/latest/ref/modules/all/salt.modules.twilio_notify.html)

Let's create a pillar directory in /srv if it doesn't already exist
```
mkdir /srv/pillar
```
Let's put our twilio information here:
```
# /srv/pillar/twilio.sls

twilio_profile:
  twilio.account_sid: <insert-account-sid-here>
  twilio.auth_token: <insert-auth-token-here>
```
and apply it to the master via top.sls
```
# /srv/pillar/top.sls

base:
  '*master':
    - twilio

```

Also put the following phone number info in the master config

```
# /etc/salt/master

sys_admin_phone: <insert-your-phone-number-here>
twilio_from_phone: <insert-twilio_from-phone-number-here> 
```

and we then can create a reactor to send us the pcap_watch event details

```
# /srv/salt/reactors/twilio_text.sls

twilio_text:
  local.twilio.send_sms:
    - tgt: {{ data['id'] }}
    - arg:
      - twilio_profile
      - "Warning high packet rate detectected from {{ data['src_ip'] }} : {{ data['rate'] }} packets/s"
      - {{ opts['sys_admin_phone'] }}
      - {{ opts[twilio_from_phone'] }}

```

And setup a reactor to use it from the pcap_watch event:
```
# /etc/salt/master.d/reactors.con
reactor:
  ...
  - salt/beacon/*/pcap_watch:
    - /srv/salt/reactors/twilio_text.sls
```

When in doubt, remember to sync, and restart master / minion processes
```
salt \* saltutil.sync_all
systemctl restart salt-master salt-minion
```

This again, requires an additional package: the ```twilio``` module
```
# /srv/salt/demo_pkgs.sls

...

install_twilio:
  pip.installed:
    - name: twilio

```
```
salt \*master state.apply
```

We can refresh the pillar data for the twilio module with the following command:
```
salt \* saltutil.refresh_pillar
```

Almost ready to test! Let's add apache bench (ab) as a requirement for all minions.

```
# /srv/salt/install_apache_bench.sls

install_apache_bench:
  pkg.installed:
    - name: apache2-utils
```
And modify our top
```
# /srv/salt/top.sls

base:
  ...
  '*':
    - install_apache_bench

```

Run a highstate:
```
salt \* state.apply
```

Now, let's send loads of traffic to our apache host (using the private ip from earlier) using apache bench on the red / blue minions

```
salt \*minion\* cmd.run "ab -n 5000 http://<ip-goes-here>/
```

You should now see text messages indicating the infringing ip and rate detected by the pcap_watch beacon!

## Part 3, auto-remediation via firewall

Instead of just a text message, we may desire auto remediation via firewall.

Let's block the infringing ip automatically with a firewall rule

Let's use ufw for this
But after enabling it, make sure to open ports 4505,4506 (for salt) and port 80 (for http)
The following state will do this

```
# /srv/salt/ufw.sls

install_ufw:
  pkg.installed:
    - name: ufw

enable_ufw:
  cmd.run:
    - name: ufw enable

open_salt_port_4505:
  cmd.run:
    - name: ufw allow 4505

open_salt_port_4506:
  cmd.run:
    - name: ufw allow 4506

allow_http:
  cmd.run:
    - name: ufw allow http
```

Apply it to the master:
```
# /srv/salt/top.sls

base:
  '*master':
    - ufw
    ...
```
```
salt \* state.apply
```

Ok, now let's create our reactor to block the infringing ip

```
# /srv/salt/reactors/block_ip.sls

block_ip:
  local.cmd.run:
    - tgt: '*master'
    - arg:
      - "ufw insert 1 deny from {{ data['src_ip'] }} to any port 80"
```

and include this reaction in the master config

```
# /etc/salt/master.d/reactors.conf

reactor:
  ...
  - salt/beacon/*/pcap_watch/:
    ...
    - /srv/salt/reactors/block_ip.sls
```

Restart the salt master

```
systemctl restart salt-master
```

Let's test it!

Verify both can curl the master apache host
```
salt \*minion\* cmd.run "curl <master-ip> | grep 'It works'"
```

Then use one minion to load the server
```
salt \*minion-red cmd.run "ab -n 5000 http://<master-ip>/"
```
You should've received a text and minion-red should now be blacklisted via ufw!

```
salt \*minion\* cmd.run "curl -m 10 <master-ip> | grep 'It works'"
```