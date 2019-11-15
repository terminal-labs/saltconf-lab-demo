apply_reactor_config:
  file.managed:
    - name: /etc/salt/master.d/reactors.conf
    - source: salt://conf/master/reactors.conf

restart_master:
  cmd.run:
    - name: systemctl restart salt-master
    - bg: True
