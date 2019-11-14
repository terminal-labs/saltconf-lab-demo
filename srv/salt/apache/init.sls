# /srv/salt/apache/init.sls

run_apache:
  service.running:
    - name: apache2
