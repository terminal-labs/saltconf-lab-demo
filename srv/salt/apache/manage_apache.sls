manage_apache_conf:
  file.managed:
    - name: /etc/apache2/apache2.conf
    - source: salt://files/apache2.conf
