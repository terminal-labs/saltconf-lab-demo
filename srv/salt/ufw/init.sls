# /srv/salt/ufw/init.sls

enable_ufw:
  cmd.run:
    - name: ufw enable

open_salt_port_4505:
  cmd.run:
    - name: ufw enable 4505

open_salt_port_4506:
  cmd.run:
    - name: ufw enable 4506

allow_http:
  cmd.run:
    - name: ufw allow http

allow_ssh:
  cmd.run:
    - name: ufw allow ssh
