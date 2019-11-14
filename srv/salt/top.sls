# /srv/salt/top.sls

base:
  '*master':
    - pkg
    - pip
    - ufw
    - apache
    - manage_apache
  '*':
    - apache_bench
