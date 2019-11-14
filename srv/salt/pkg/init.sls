# /srv/salt/pkg.sls

install_libpcap:
  pkg.installed:
    - name: libpcap-dev

install_ufw:
  pkg.installed:
    - name: ufw

install_tshark:
  pkg.installed:
    - name: tshark

install_pip:
  pkg.installed:
    - name: python-pip

install_inotify:
  pkg.installed:
    - name: inotify-tools

install_apache:
  pkg.installed:
    - name: apache2
