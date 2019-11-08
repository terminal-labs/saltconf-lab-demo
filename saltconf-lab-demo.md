# SaltConf Lab Demo

The lab demonstration will consist of several parts. First, the students will learn the basics of the salt’s event system including reactors and beacons. Then, a simple demo will show how to set up a built-in beacon (inotify, memusage, etc.) and configure a reactor which will send the event details to a system administrator via text message using the twilio module. The second part of the demo will include writing a custom beacon to detect abnormal network traffic, which will, in turn, trigger sending an event to the salt master. The reactor will remain and report the event details via text message. Part three will include writing a reactor state to apply remediation to the abnormal network traffic event.

For official documentation on Salt’s event system see docs here: https://docs.saltstack.com/en/latest/topics/event/index.html

## Part 1: Salt Event System, Reactors, Beacons 

Topics:
- Reactor / Beacon Setup
- Using Builtin Beacons
- CLI tools

All masters and minions have their own event bus.

To view the master’s event bus in real time, use the following CLI command (on the master):
```
# salt-run state.event pretty=True
```
To fire an event on a minion to be sent to its master’s event bus use the following CLI command (on the minion):
```
# salt-call event.send <tag> <data>
```
Where ```<tag>``` is the  tag to be associated with the event for filtering purposes and ```<data>``` is a dictionary of key value pairs to be sent as data with the event.

Salt has a standard way of namespacing the tag for various events. We will need to know the form of the event tag to set up a reactor to respond to it. For more information on various events see the official documentation: https://docs.saltstack.com/en/latest/topics/event/master_events.html

Let’s set up a beacon to fire an event when our apache configuration file has been modified. We can do this with the inotify beacon. You can configure beacons via minion configuration in /etc/salt/minion, /etc/salt/minion.d or via pillar. In this example we will use /etc/salt/minion.d/beacons.conf

In /etc/salt/minion.d/beacons.conf, put the following:
```
beacons:
  inotfiy:
    - files:
        /etc/apache2/apache2.conf:
          mask:
            - modify
    - disable_during_state_run: True

```

```disable_during_state_run: True``` is very important here to avoid loops, since our reactor will replace this file with the correct version (thus modifying it again)

__Note__ ```inotify``` and ```pyinotify``` must be installed to use the ```inotify``` beacon.

Remember to restart the salt master / minion after making configuration changes

```
systemctl restart salt-minion
```

__Try it__ Modify apache.conf and you should be able to see the event on the master event bus using ```salt-run state.event pretty=True``` 

_Configuring the reactor_

Reactors can be added via /etc/salt/master or in the /etc/salt/master.d directory. Let's put our reactor config in /etc/salt/master.d/reactors.conf:
```
# /etc/salt/master.d/reactors.conf
reactor:
  - salt/beacon/<minion-id>/inotify//etc/apache2/apache2.conf
    - /srv/reactors/call_manage_apache_conf.sls
```

Here we list the event tags to add a reactor for (i.e. salt/beacon/<minion-id>/inotify//etc/apache2/apache2.conf), with its sublist being the set of orchestration files to be run when the event occurs. Remember to replace <minion-id> with the actual _minion id_ and glob expressions may also be used.

Create a directory /srv/reactors if it doesn't already exist. ```call_manage_apache_conf.sls``` is an orchestration state which will instruct the minion to call another state which replaces the apache conf file.

```
# /srv/reactors/call_manage_apache_conf.sls
call_manage_apache_conf:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
      - manage_apache_conf

```

This orchestration will instruct the minion to apply the manage_apache_conf state.

```
# /srv/salt/manage_apache_conf.sls
manage_apache_conf:
  file.managed:
    - name: /etc/apache2/apache2.conf
    - source: salt://files/apache2.conf
```

Make sure to restart the salt master

__Try it__ View the event bus while modifying apache2.conf, the file should be replaced with the one being served by salt://files/apache2.conf faster than you can say thorium salt reactor!


### Outline

#### Part 1

Topics:
- Understanding Salt's event system
- Using CLI to view and send events
- Built-in inotify beacon to manage modified apache2.conf

Salt's event system will be introduced. CLI tools to view and send events will be described. A simple demo will show how to configure a built-in beacon to send an event upon apache's configuration being modified which will trigger a reactor to call a state which restores the original apache.conf file via the file.managed module

#### Part 2

Topics:
- Custom Beacons

Students will be shown how to write your own custom beacon while taking advantage of salt's plugin system. In the vain of networ security, the custom beacon should be able to detect abnormal network traffic and fire an event to the salt master. The reactor will demonstrate the twilio module, and send event details to a sys admin via text.

#### Part 3

Topics:
- Remediation via reactor state

Students will write their own remediation state which the reactor will be configured to use. The remediation state will take necessary action due to the abnormal network activity event beacon setup in Part 2.  This will include configuring the firewall to block the infringing ip indicated by the custom beacon. We will see that the port (and webpage) will no longer be accessible from the infringing host.
