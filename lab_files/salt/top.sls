base:
  '*master':
    - ufw
    - python_pip
    - demo_pkgs
    - apache
    - manage_apache
  '*':
    - install_apache_bench
