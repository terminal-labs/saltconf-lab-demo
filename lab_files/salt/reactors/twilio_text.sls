# Place this file in /srv/salt/reactors/twilio_text.sls
#
# Example master config to use this reactor upon an event from the pcap_watch beacon
#
# reactors:
#   - 'salt/beacon/*/pcap_watch/'
#     - /srv/salt/reactors/twilio_text.sls
#
# Note: This file assumes 'twilio_profile' profile has been 
#   configured correctly per the [docs](https://docs.saltstack.com/en/latest/ref/modules/all/salt.modules.twilio_notify.html)
# 
# E.g.:
#
# twilio_profile:
#   twilio.account_sid: xxxxxxxxxxxx
#   twilio.auth_token: xxxxxxxx
# 
# Furthermore, this file assumes 'sys_admin_phone_number' and 'twilio_trial_number' 
#  are defined in the master config. Modify as necessary.
#

twilio_text:
  local.twilio.send_sms:
    - tgt: {{ data['id'] }}
    - arg:
      - twilio_profile
      - "Warning: High packet rate detected from {{ data['src_ip'] }} : {{ data['rate'] }} packets/s"
      - {{ opts['sys_admin_phone'] }}
      - {{ opts['twilio_from_phone'] }}
