# /srv/salt/pip/init.sls

install_dpkt:
  pip.installed:
    - name: dpkt

install_twilio:
  pip.installed:
    - name: twilio

install_pyinotify:
  pip.installed:
    - name: pyinotify
