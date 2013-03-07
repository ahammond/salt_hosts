{{ grains['localhost'] }}:
  host.present:
    - ip: 127.0.0.1
    - names:
      - {{ grains['localhost'] }}
      - localhost
      - localhost.localdomain

{% for hostname, args in pillar['hosts'].iteritems() %}
{{ hostname }}:
  host.present:
    - ip: {{ args['ip'] }}
{% if 'names' in args %}
    - names:
{% for name in args['names'] %}
      - {{ name }}
{% endfor %}
{% endif %}
{% endfor %}
