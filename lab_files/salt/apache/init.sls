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
