# Lab Procedure

This lab procedure will discuss the following:
- Using a built in beacon / reactor to restore a modified apache config
- Using a (pre-made) custom beacon to monitor for high packet rates on port 80, 
and sending a text message to a sys admin
- Using the same custom beacon to provide firewall remediation of the potential DDOS attack

## Part 1: Built-in inotify beacon

For this part we will use Apache web server for demonstration. Let's install and configure the service using salt.

The ```file_roots``` parameter in the master config (/etc/salt/master) is where salt will look for states, modules, and/or other files.
By default this is ```/srv/salt``` for the base environment

Let's make the directory and create a state to install apache.

```
mkdir /srv/salt
cd /srv/salt
```


```
mkdir apache
touch apache/init.sls
mkdir apache/files
```

```
# /srv/salt/apache/init.sls

install_apache:
  pkg.installed:
    - name: apache2

manage_apache_conf:
  file.managed:
    - name: /etc/apache2/apache2.conf
    - source: salt://apache/files/apache2.conf
    - require:
      - install_apache

run_apache:
  service.running:
    - name: apache2
    - enable: True
    - require:
      - install_apache
    - watch:
      - manage_apache_conf

```

Notice that the above ```manage_apache_conf``` id block requires the apache config to be served salt://apache/files/apache2.conf (i.e. located in /srv/salt/apache/files/apache2.conf). You can download this file from [here](https://github.com/terminal-labs/saltconf-lab-demo/blob/master/lab_files/salt/apache/files/apache2.conf)

```
wget https://raw.githubusercontent.com/terminal-labs/saltconf-lab-demo/master/lab_files/salt/apache/files/apache2.conf -O /srv/salt/apache/files/apache2.conf
```

Now apply the state to the master
```
salt \*master state.apply apache
```

Test ensure the standard apache landing page is being served on port 80
```
curl localhost | grep "It works!"
```

Before we go much further, let's enable and configure ufw. We will be using this program later for DDOS attack remediation

Create another folder for the ufw state
```
mkdir ufw
touch ufw/init.sls
```
```
# /srv/salt/ufw/init.sls

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

allow_ssh:
  cmd.run:
    - name: ufw allow ssh
```

This will ensure ufw is installed, enabled and allowing the appropriate ports.

Now apply this to the master
```
salt \*master state.apply ufw
```

Let's see if we can reach this page from the minions.
First identify the master's private ip. To do this we can use salt's ```network``` module

```
salt \*master network.ipaddrs
```

Then utilize salt's ```cmd.run``` to curl that ip on all minions:
```
salt \* cmd.run "curl <ip-address> | grep 'It works'"
```

We can also make use of a highstate by creating a top file which applies these two states we created.

```
# /srv/salt/top.sls

base:
  '*master':
    - apache
    - ufw
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
More on that in a minute, but first, let's set up the inotify beacon.

For more info on beacons see the docs [here](https://docs.saltstack.com/en/develop/topics/beacons/)

Beacons are configured via the minion config. Let's write a salt state to do this utilizing ```file.managed```. We will be using the final beacon configuration located [here](https://github.com/terminal-labs/saltconf-lab-demo/blob/master/lab_files/salt/conf/minion/beacons.conf) which includes both beacons we will use throughout this procedure. 

Notice the form of the configuration for the inotify beacon: 
```
beacons:
  inotify:
    - files:
        /etc/apache2/apache2.conf:
          mask:
            - modify
    - disable_during_state_run: True

```

__Note__ ```disable_during_state_run: True``` is very important here to avoid loops, since our reactor will replace this file with the correct version (thus modifying it again)

__Note__ ```inotify``` and ```pyinotify``` must be installed to use the ```inotify``` beacon.

Since we will need pip to install pyinotify let's create a ```core``` state to install pip and apply it to our topfile

```
# /srv/salt/core.sls

install_pip:
  pkg.installed:
    - name: python-pip
```
```
# /srv/salt/top.sls

base:
  '*':
    - core
  '*master':
    - apache
    - ufw
```

And apply it
```
salt \* state.apply
```

Now let's create a directory ```enable_beacons``` which we can use to include a state for each beacon we setup.

First we will write the state for enabling the ```inotify``` beacon so let's put this in ```enable_beacons/inotify.sls```

```
mkdir enable_beacons
```
```
# /srv/salt/enable_beacons/inotify.sls

apply_inotify_beacon_config:
  file.managed:
    - name: /etc/salt/minion.d/beacons.conf
    - source: salt://conf/minion/beacons.conf

install_inotify_tools:
  pkg.installed:
    - name: inotify-tools

install_pyinotify:
  pip.installed:
    - name: pyinotify
    - require:
      - install_inotify_tools

restart_minion:
  cmd.run:
    - name: systemctl restart salt-minion
    - bg: True

```

Make sure we have the the [conf file](https://github.com/terminal-labs/saltconf-lab-demo/blob/master/lab_files/salt/conf/minion/beacons.conf) served from ```salt://conf/minion/beacons.conf``` (i.e. stored in /srv/salt/conf/minion/beacons.conf) for the configuration to be applied successfuly in the above state.

```
mkdir -p /srv/salt/conf/minion
wget https://raw.githubusercontent.com/terminal-labs/saltconf-lab-demo/master/lab_files/salt/conf/minion/beacons.conf -O /srv/salt/conf/minion/beacons.conf
```

and apply it:
```
salt \*master state.apply enable_beacons.inotify
```

__Try it__ Modify /etc/apache2/apache2.conf and you should be able to see the event on the master event bus using ```salt-run state.event pretty=True``` 

### _Configuring the reactor_

Reactors can be configured via /etc/salt/master or in the /etc/salt/master.d directory, but again let's write a state to manage this.

```
# /srv/salt/enable_reactors/init.sls
apply_reactor_config:
  file.managed:
    - name: /etc/salt/master.d/reactor.conf
    - source: salt://conf/master/reactor.conf

restart_master:
  cmd.run:
    - name: systemctl restart salt-master
    - bg: True
```

Be sure to download reactors.conf from [here](https://github.com/terminal-labs/saltconf-lab-demo/blob/master/lab_files/salt/conf/master/reactor.conf) and store it in the location served by salt://conf/master/reactor.conf. This file contains the reactors used throughout this lab procedure.

Take a look at the reactor config for the inotify event
```
reactor:
  - salt/beacon/*/inotify//etc/apache2/apache2.conf:
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
      - apache

```

This orchestration will instruct the minion to apply the manage_apache state we wrote earlier to the tgt specified by the event data's id key.

After including the appropriate files enable the reactors
```
salt \*master state.apply enable_reactors
```

__Try it__ View the event bus while modifying apache2.conf. The file will be replaced with the one being served by salt://files/apache2.conf faster than you can say thorium salt reactor!

## Part 2: Custom beacon to monitor traffic and send text message

Salt's event system can be easily extended with custom beacons! For more information on _how_ to write custom beacons see the doc section [here](https://docs.saltstack.com/en/develop/topics/beacons/#writing-beacon-plugins). For the purpose of this lab session, 
we will use a pre-written custom beacon module.

Create a ```_beacons``` directory in /srv/salt and download the file hosted [here](https://github.com/terminal-labs/saltconf-lab-demo/blob/master/lab_files/salt/_beacons/pcap_watch.py)

```
mkdir _beacons
cd _beacons
wget https://raw.githubusercontent.com/terminal-labs/saltconf-lab-demo/master/lab_files/salt/_beacons/pcap_watch.py -O pcap_watch.py
```

And we can cache the beacon modules on the minions with the following command
```
salt \* saltutil.sync_beacons
```

This beacon will monitor a pcap file for packets and will send an event if the packet rate exceeds the limit specified for each ip, respectively. It assumes we have configured packet filtering accordingly.

For our purposes, we will use tshark and the following command:
```
tshark -i eth0 -F libpcap -t u -f 'tcp dst port 80' -w /var/tmp/tshark.pcap
```

This will setup monitoring on the eth0 interface, writing the packets to /var/tmp/tshark.pcap using the libpcap library.
It specifies UTC as the timestamp and sets up a filter for tcp packets with destination port 80.

Let's make a state to install required packages, enable the beacon, and start the required tshark process in the background

```
# /srv/salt/enable_beacons/pcap_watch.sls
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
  
```

and apply it
```
salt \*master state.apply enable_beacons.pcap_watch
```

Take a look at the pcap_watch beacon configuration. Notice that the pcap_file from the tshark process is specified here
```
beacons:
  ...
  pcap_watch:
    - pcap_file: /var/tmp/tshark.pcap
    - rate_limit: 100  # packets / sec
    - pcap_period: 1   # sec of pcap data to use every beacon interval

```

### _Twilio text (optional)_

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
      - {{ opts['twilio_from_phone'] }}

```

The ```enable_reactors``` state we already made will configure the twilio reactor. Notice this section in ```reactors.conf```
```
reactor:
  ...
  - salt/beacon/*/pcap_watch:
    - /srv/salt/reactors/twilio_text.sls
```

The ```enable_reactors``` state will also restart the master, needed to apply the twilio information we applied in the master config.

We will also need the python twilio module. Let's add this to the enable_reactors state and re-run it.
```
# /srv/salt/enable_reactors/init.sls

install_twilio:
  pip.installed:
    - name: twilio

...

```
```
salt \*master state.apply enable_reactors
```

We can refresh the pillar data for the twilio module with the following command:
```
salt \* saltutil.refresh_pillar
```

Almost ready to test! Let's add apache bench (ab) as a requirement for all minions.

```
# /srv/salt/core.sls
...

install_apache_bench:
  pkg.installed:
    - name: apache2-utils
```

Then, run another highstate:
```
salt \* state.apply
```

Now, let's send loads of traffic to our apache host (using the private ip from earlier) using apache bench on the red minion

```
salt \*minion-red cmd.run "ab -n 5000 http://<ip-goes-here>/"
```

You should now see the text message indicating the infringing ip and rate detected by the pcap_watch beacon!

## Part 3: Auto-remediation via firewall

Instead of a mere text message, we may desire auto remediation via firewall. Let's write a salt reactor to block the infringing ip automatically with a firewall rule.

We already enabled ufw before. Now let's create a reactor to block the infringing ip

```
# /srv/salt/reactors/block_ip.sls

block_ip:
  local.cmd.run:
    - tgt: '*master'
    - arg:
      - "ufw insert 1 deny from {{ data['src_ip'] }} to any port 80"
```

The following is already included in our reactor config from earlier:
```
reactor:
  ...
  - salt/beacon/*/pcap_watch/:
    ...
    - /srv/salt/reactors/block_ip.sls
```

__Try it!__

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
salt \*minion\* cmd.run "curl -m 5 <master-ip> | grep 'It works'"
```

You can view the updated firewall rules by executing the following command on the master:
```
ufw status
```
and delete the added rule with
```
ufw delete 1
```
