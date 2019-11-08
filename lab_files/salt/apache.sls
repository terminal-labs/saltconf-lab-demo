install_apache:
  pkg.installed:
    - name: apache2

run_apache:
  service.running:
    - name: apache2
