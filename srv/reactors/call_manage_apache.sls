call_manage_apache:
  local.state.apply:
    - tgt: {{ data['id'] }}
    - arg:
      - manage_apache
