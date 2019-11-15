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
