{% set nova = salt['openstack_utils.nova']() %}
{% set service_users = salt['openstack_utils.openstack_users']('service') %}
{% set openstack_parameters = salt['openstack_utils.openstack_parameters']() %}


nova_compute_conf_keystone_authtoken:
  ini.sections_absent:
    - name: "{{ nova['conf']['nova'] }}"
    - sections:
      - keystone_authtoken
    - require:
{% for pkg in nova['packages']['compute']['kvm'] %}
      - pkg: nova_compute_{{ pkg }}_install
{% endfor %}


{% set minion_ip = salt['openstack_utils.minion_ip'](grains['id']) %}
nova_compute_conf:
  ini.options_present:
    - name: {{ nova['conf']['nova'] }}
    - sections:
        DEFAULT:
          rpc_backend: rabbit
          auth_strategy: keystone
          my_ip: {{ minion_ip }}
          vnc_enabled: True
          vncserver_listen: 0.0.0.0
          vncserver_proxyclient_address: {{ minion_ip }}
          novncproxy_base_url: "http://{{ openstack_parameters['controller_public_ip'] }}:6080/vnc_auto.html"
          debug: "{{ salt['openstack_utils.boolean_value'](openstack_parameters['debug_mode']) }}"
          verbose: "{{ salt['openstack_utils.boolean_value'](openstack_parameters['debug_mode']) }}"
          network_api_class: nova.network.neutronv2.api.API
          security_group_api: neutron
          linuxnet_interface_driver: nova.network.linux_net.LinuxOVSInterfaceDriver
          firewall_driver: nova.virt.firewall.NoopFirewallDriver
        keystone_authtoken:
          auth_uri: "http://{{ openstack_parameters['controller_ip'] }}:5000"
          auth_url: "http://{{ openstack_parameters['controller_ip'] }}:35357"
          auth_plugin: "password"
          project_domain_id: "default"
          user_domain_id: "default"
          project_name: "service"
          username: "nova"
          password: "{{ service_users['nova']['password'] }}"
        glance:
          host: "{{ openstack_parameters['controller_ip'] }}"
        oslo_concurrency:
          lock_path: "{{ nova['files']['nova_tmp'] }}"
        neutron:
          url: "http://{{ openstack_parameters['controller_ip'] }}:9696"
          auth_strategy: keystone
          admin_auth_url: "http://{{ openstack_parameters['controller_ip'] }}:35357/v2.0"
          admin_tenant_name: service
          admin_username: neutron
          admin_password: "{{ service_users['neutron']['password'] }}"
        libvirt:
          virt_type: kvm
          images_type: rbd
          images_rbd_pool: vms
          images_rbd_ceph_conf: /etc/ceph/ceph.conf
          rbd_user: cinder
          rbd_secret_uuid: "{{ openstack_parameters['secret_uuid'] }}"
          disk_cachemodes: 'network=writeback'
          inject_password: false
          inject_key: false
          inject_partition: -2
          live_migration_flag: "VIR_MIGRATE_UNDEFINE_SOURCE,VIR_MIGRATE_PEER2PEER,VIR_MIGRATE_LIVE,VIR_MIGRATE_PERSIST_DEST,VIR_MIGRATE_TUNNELLED"
          cpu_mode: custom
          cpu_model: kvm64
    - require:
      - ini: nova_compute_conf_keystone_authtoken


{% for service in nova['services']['compute']['kvm'] %}
nova_compute_{{ service }}_running:
  service.running:
    - enable: True
    - name: {{ nova['services']['compute']['kvm'][service] }}
    - watch:
      - ini: nova_compute_conf
{% endfor %}

libvirt_nova:
  file.managed:
    - name: /etc/sysconfig/libvirtd
    - contents: 'LIBVIRTD_ARGS="--listen"'
    - require:
      - pkg: libvirt

libvirt_conf:
  file.managed:
    - name: /etc/libvirt/libvirt.conf
    - contents: |
        listen_tls = 0
        listen_tcp = 1
        tcp_port = "16509"
        auth_tcp = "none"

nova_compute_sqlite_delete:
  file.absent:
    - name: {{ nova['files']['sqlite'] }}
    - require:
{% for service in nova['services']['compute']['kvm'] %}
      - service: nova_compute_{{ service }}_running
{% endfor %}


nova_compute_wait:
  cmd.run:
    - name: sleep 5
    - require:
{% for service in nova['services']['compute']['kvm'] %}
      - service: nova_compute_{{ service }}_running
{% endfor %}
