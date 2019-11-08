install_inotify:
  pkg.installed:
    - name: inotify-tools

install_pyinotify:
  pip.installed:
    - name: pyinotify

install_tshark:
  pkg.installed:
    - name: tshark

install_libpcap:
  pkg.installed:
    - name: libpcap-dev

install_dpkt:
  pip.installed:
    - name: dpkt

install_twilio:
  pip.installed:
    - name: twilio
