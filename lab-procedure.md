# Lab outline

This lab will expose students to the following:
- Using a built in beacon/reactor to restore a modified apache configuration file
- Installing a (pre-made) custom beacon to monitor for high packet rates over port 80
  - Leveraging said custom beacon to deliver a notification to system administrator
  - Then using the custom beacon to provide firewall remediation of a potential DDOS attack
<br>

## Part 0: Check your salt cluster
1) Login to your assigned [environment]().
If you are using windows then use these [directions]().
```
$ ssh -i [path to provided key] ubuntu@[your master instance IP address]
```

2) Ensure your salt master is running and has no errors.
```
$ systemctl status salt-master
```

3) Browse the master configuration file `/etc/salt/master`.
The listed directories under `file_roots` is where salt will look
for states, modules, and managed files.
```YAML
$ cat /etc/salt/master
file_roots:
  base:
    - /srv/salt
```

4) Check what minion keys are accepted by your master, `$ salt-key -L`,
then check that your master can connect to all listed minions.
```YAML
$ salt \* test.version
dynamic-lab000-master:
    2019.2.2
dynamic-lab000-minion-red:
    2019.2.2
dynamic-lab000-minion-blue:
    2019.2.2
```
The return will look similar to the one above. If your return looks questionable, please **request assistance**.
<br><br><br>


## Part 1: Install apache with salt
For this part we will use salt to install and start Apache web server for the demonstration.

1) Create a salt state to install apache in the `/srv/salt` directory.

```YAML
$ mkdir -p /srv/salt/apache; nano /srv/salt/apache/init.sls
# /srv/salt/apache/init.sls

install_apache:
  pkg.installed:
    - name: apache2

run_apache:
  service.running:
    - name: apache2
```

2) Now apply the state to our salt master to install and run the apache service.
```
$ salt \*master state.apply apache
```

3) Test to ensure the standard apache landing page is being served on port 80.
```
$ curl localhost | grep "It works!"
```


### Part 1.1: Manage apache with salt
To manage the (now running) apache server, we will copy its configuration file
into the salt's `file_roots` with the states used to manage apache.

1) Copy over apache's configuration file next to the salt states for apache.
```
$ cp /etc/apache2/apache2.conf /srv/salt/apache/apache2.conf
```

2) Create a new state for applying the newly copied configuration file to the apache server.
```YAML
$ nano /srv/salt/apache/manage_apache.sls
# /srv/salt/apache/manage_apache.sls

manage_apache_conf:
  file.managed:
    - name: /etc/apache2/apache2.conf
    - source: salt://files/apache2.conf
```

3) Check to ensure the state is valid and then run it.
```
$ salt \*master state.sls manage_apache test=True
$ salt \*master state.apply manage_apache
```

4) We can apply these states in one command with a highstate by creating a `top.sls` file.
When we run a highstate it will read the top file and apply the states listed.
```YAML
$ nano /srv/salt/top.sls
# /srv/salt/top.sls

base:
  '*master':
    - apache
    - manage_apache
```

5) Apply the top file with either highstate command.
```YAML
salt \*master state.apply
# or
salt \*master state.highstate
```
<br><br><br>


## Part 2: Monitor apache with salt [beacons](https://docs.saltstack.com/en/develop/topics/beacons/)
With apache running "optimally," we need to be aware of any changes to its
configuration file. We will use salt's built-in inotify beacon to watch for file
modifications, and upon detection, send a report to the salt master's event bus.

1) We can add the beacon to the minion's configuration by adding files to the
`/etc/salt/minion.d` directory.
```YAML
$ nano /etc/salt/minion.d/beacons.conf
# /etc/salt/minion.d/beacons.conf

beacons:
  inotfiy:
    - files:
        /etc/apache2/apache2.conf:
          mask:
            - modify
    - disable_during_state_run: True
```

`disable_during_state_run: True` is very important here to avoid loops, since our reactor will replace this file with the correct version (thus modifying it again)

`inotify` and `pyinotify` must be installed to use the inotify beacon.


We could install these with apt, but let's write a couple states instead and add to our topfile.

We will need pip:
```YAML
$ nano /srv/salt/pip/init.sls
# /srv/salt/pip/init.sls

install_pip:
  pkg.installed:
    - name: python-pip
```

And other packages:
```YAML
$ nano /srv/salt/inotify/init.sls
# /srv/salt/inotify/init.sls

install_inotify:
  pkg.installed:
    - name: inotify-tools

install_pyinotify:
  pip.installed:
    - name: pyinotify
```
Let's add them to our existing topfile
```YAML
$ nano /srv/salt/top.sls
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

Remember to restart the salt master/minion after making configuration changes

```
systemctl restart salt-minion
```

__Try it__ Modify apache.conf and you should be able to see the event on the master event bus using ```salt-run state.event pretty=True```

### _Configuring the reactor_

Reactors can be configured via /etc/salt/master or in the /etc/salt/master.d directory.

Let's put our reactor config in /etc/salt/master.d/reactors.conf:
```YAML
$ nano /etc/salt/master.d/reactors.conf
# /etc/salt/master.d/reactors.conf
reactor:
  - salt/beacon/*/inotify//etc/apache2/apache2.conf
    - /srv/salt/reactors/call_manage_apache.sls
```

Here we list the event tags to add a reactor for with its sublist being the set of orchestration files to be run when the event occurs. A glob ('') is being used for the minion_id which we will be able to retrieve from the event data in the orchestration
state as seen in the following.

We need to create the file referenced in the above reactor

```YAML
$ nano /srv/salt/reactors/call_manage_apache.sls
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

__Try it__ View the event bus while modifying apache2.conf. The file should be replaced with the one being served by salt://files/apache2.conf faster than you can say thorium salt reactor!

## Part 2: Custom beacon to monitor traffic and send text message

Salt's event system can be easily extended with custom beacons! For more information on _how_ to write custom beacons see the doc section [here](https://docs.saltstack.com/en/develop/topics/beacons/#writing-beacon-plugins). For the purpose of this lab session,
we will use a pre-written custom beacon module.

Create a ```_beacons``` directory in /srv/salt and download the file hosted [here](https://github.com/terminal-labs/saltconf-lab-demo/blob/master/lab_files/salt/_beacons/pcap_watch.py)

```
mkdir _beacons
cd _beacons
wget https://raw.githubusercontent.com/terminal-labs/saltconf-lab-demo/master/lab_files/salt/_beacons/pcap_watch.py -O pcap_watch.py
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

__Note__ The pcap_file from the tshark process must be specified here

Be sure to sync the beacon and restart the minion

```
salt \*master saltutil.sync_beacons
systemctl restart salt-minion
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

Remember to sync, and restart master / minion processes
```
salt \* saltutil.sync_all
systemctl restart salt-master salt-minion
```

Make sure to install the additional packages, i.e, the ```twilio``` module
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
And modify our topfile:
```
# /srv/salt/top.sls

base:
  ...
  '*':
    - install_apache_bench

```

Then, run a highstate:
```
salt \* state.apply
```

Now, let's send loads of traffic to our apache host (using the private ip from earlier) using apache bench on the red / blue minions

```
salt \*minion\* cmd.run "ab -n 5000 http://<ip-goes-here>/
```

You should now see text messages indicating the infringing ip and rate detected by the pcap_watch beacon!

## Part 3: Auto-remediation via firewall

Instead of a mere text message, we may desire auto remediation via firewall. Let's write a salt reactor to block the infringing ip automatically with a firewall rule.

Let's use ufw for this.
Make sure to open ports 4505,4506 (for salt) and port 80 (for http).
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
salt \*minion\* cmd.run "curl -m 10 <master-ip> | grep 'It works'"
```
