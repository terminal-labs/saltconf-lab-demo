# /srv/salt/pkg/apache_bench.sls

install_apache_bench:
  pkg.installed:
    - name: apache2-utils
