install_pip:
  pkg.installed:
    - name: python-pip

install_apache_bench:
  pkg.installed:
    - name: apache2-utils
