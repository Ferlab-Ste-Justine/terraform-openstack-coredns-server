# About

This module provision coredns instances on openstack.

The server is configured to to work with zonefiles which are fetched from an etcd cluster. Each domain is a key in etcd (with an optional prefix) and the zonefile (which should be compatible with the auto plugin) is the value.

The server will automatically detect any changes in the domains in the etcd backend and update the zonefiles accordingly.

Note that except for updates to zonefiles, the coredns server is decoupled from the etcd cluster and will happily keep answering dns requests with whatever zonefiles it has on hand (they just won't update until the etcd cluster is back up).

# Note About Alternatives

Coredns also has a SkyDNS compatible plugin: https://coredns.io/plugins/etcd/

Some of the perceived pros of the above plugin:
- Assuming that the cache plugin isn't used (ie, all dns requests hit etcd), the consistency level of the answer from different dns servers shortly after the change can't be matched
- From what I read in the readme, decentralisation of ip registration seems better supported out of the box (you could support it with zonefiles too, but extra logic would have to be added using something like templates)

Some of the perceived pros of our implementation:
- Full support for zonefiles to the extend the coredns auto plugin supports them (ie, fewer quirks)
- Decent consistency/performance tradeoff: The server does a watch for changes on the etcd cluster (but will not put any more stress than that etcd) and will automatically update its local zonefiles with changes. The refresh interval set in the auto plugin will determine how quickly those changes will be picked up (3 seconds by default)
- Greater decoupling from etcd: The server is only dependent on etcd for updating zonefiles. If etcd is down, it can still answer queries with the zonefiles it has. 

# Related Projects

See the following terraform module that uploads very basic zonefiles in etcd: https://github.com/Ferlab-Ste-Justine/etcd-zonefile

Also, this module expects to authentify against etcd using tls certificate authentication. The following terraform module will, taking a certificate authority as input, generate a valid key and certificate for a given etcd user: https://github.com/Ferlab-Ste-Justine/terraform-tls-client-certificate

# Usage

## Variables

This module takes the following variables as input:

- **name**: This should be a name that uniquely identifies this member in the cluster. 
- **image_source**: Source of the image to provision the bastion on. It takes the following keys (only one of the two fields should be used, the other one should be empty):
  - **image_id**: Id of the image to associate with a vm that has local storage
  - **volume_id**: Id of a volume containing the os to associate with the vm
- **flavor_id**: Id of the vm flavor to assign to the instance. See hardware recommendations to make an informed choice: https://etcd.io/docs/v3.4/op-guide/hardware/
- **network_port**: Resource of type **openstack_networking_port_v2** to assign to the vm for network connectivity
- **server_group**: Server group to assign to the node. Should be of type **openstack_compute_servergroup_v2**.
- **keypair_name**: Name of the ssh keypair that will be used to ssh against the vm.
- **etcd**: Parameters to connect to the etcd backend. It has the following keys:
  - **ca_certificate**: Tls ca certificate that will be used to validate the authenticity of the etcd cluster
  - **key_prefix**: Prefix for all the domain keys. The server will look for keys with this prefix and will remove this prefix from the key's name to get the domain.
  - **endpoints**: A list of endpoints for the etcd servers, each entry taking the ```<ip>:<port>``` format
  - **client**: Authentication parameters for the client (either certificate or username/password authentication are support). It has the following keys:
    - **certificate**: Client certificate if certificate authentication is used.
    - **key**: Client key if certificate authentication is used.
    - **username**: Client username if certificate authentication is used.
    - **password**: Client password if certificate authentication is used.
- **dns**: Parameters to customise the dns behavior. It has the following keys:
  - **zonefiles_reload_interval**: Time interval at which the **auto** plugin should poll the zonefiles for updates. Defaults to **3s** (ie, 3 seconds).
  - **load_balance_records**: In the event that an A or AAAA record yields several ips, whether to randomize the returned order or not (with clients that only take the first ip, you can achieve some dns-level load balancing this way). Defaults to **true**.
  - **alternate_dns_servers**: List of dns servers to use to answer all queries that are not covered by the zonefiles. It defaults to an empty list.
  - **forwards**: List of objects, each having a **domain_name** and **dns_servers**. It allows forwarding queries for specific domains to other dns servers. It defaults to an empty list.
  - **cache_settings**: List of objects for configuring cache for specific domains. Each object has the following keys:
    - **domains**: The domains for which caching is enabled.
    - **success_capacity**: Capacity for caching positive responses. Defines the maximum number of entries in the cache for successful responses for this domain.
    - **prefetch**: Number of requests before prefetching the cache entry. Allows prefetching popular items before they expire.
- **chrony**: Optional chrony configuration for when you need a more fine-grained ntp setup on your vm. It is an object with the following fields:
  - **enabled**: If set to false (the default), chrony will not be installed and the vm ntp settings will be left to default.
  - **servers**: List of ntp servers to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#server)
  - **pools**: A list of ntp server pools to sync from with each entry containing two properties, **url** and **options** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#pool)
  - **makestep**: An object containing remedial instructions if the clock of the vm is significantly out of sync at startup. It is an object containing two properties, **threshold** and **limit** (see: https://chrony.tuxfamily.org/doc/4.2/chrony.conf.html#makestep)
- **fluentbit**: Optional fluent-bit configuration to securely route logs to a fluend/fluent-bit node using the forward plugin. Alternatively, configuration can be 100% dynamic by specifying the parameters of an etcd store or git repo to fetch the configuration from. It has the following keys:
  - **enabled**: If set to false (the default), fluent-bit will not be installed.
  - **metrics**: Configuration for metrics fluentbit exposes.
    - **enabled**: Whether to enable the metrics or not
    - **port**: Port to expose the metrics on
  - **coredns_tag**: Tag to assign to logs coming from coredns
  - **coredns_updater_tag**: Tag to assign to logs coming from the coredns zonefiles updater
  - **node_exporter_tag** Tag to assign to logs coming from the prometheus node exporter
  - **forward**: Configuration for the forward plugin that will talk to the external fluend/fluent-bit node. It has the following keys:
    - **domain**: Ip or domain name of the remote fluend node.
    - **port**: Port the remote fluend node listens on
    - **hostname**: Unique hostname identifier for the vm
    - **shared_key**: Secret shared key with the remote fluentd node to authentify the client
    - **ca_cert**: CA certificate that signed the remote fluentd node's server certificate (used to authentify it)
- **fluentbit_dynamic_config**: Optional configuration to update fluent-bit configuration dynamically either from an etcd key prefix or a path in a git repo.
  - **enabled**: Boolean flag to indicate whether dynamic configuration is enabled at all. If set to true, configurations will be set dynamically. The default configurations can still be referenced as needed by the dynamic configuration. They are at the following paths:
    - **Global Service Configs**: /etc/fluent-bit-customization/default-config/service.conf
    - **Default Variables**: /etc/fluent-bit-customization/default-config/default-variables.conf
    - **Systemd Inputs**: /etc/fluent-bit-customization/default-config/inputs.conf
    - **Forward Output For All Inputs**: /etc/fluent-bit-customization/default-config/output-all.conf
    - **Forward Output For Default Inputs Only**: /etc/fluent-bit-customization/default-config/output-default-sources.conf
  - **source**: Indicates the source of the dynamic config. Can be either **etcd** or **git**.
  - **etcd**: Parameters to fetch fluent-bit configurations dynamically from an etcd cluster. It has the following keys:
    - **key_prefix**: Etcd key prefix to search for fluent-bit configuration
    - **endpoints**: Endpoints of the etcd cluster. Endpoints should have the format `<ip>:<port>`
    - **ca_certificate**: CA certificate against which the server certificates of the etcd cluster will be verified for authenticity
    - **client**: Client authentication. It takes the following keys:
      - **certificate**: Client tls certificate to authentify with. To be used for certificate authentication.
      - **key**: Client private tls key to authentify with. To be used for certificate authentication.
      - **username**: Client's username. To be used for username/password authentication.
      - **password**: Client's password. To be used for username/password authentication.
  - **git**: Parameters to fetch fluent-bit configurations dynamically from an git repo. It has the following keys:
    - **repo**: Url of the git repository. It should have the ssh format.
    - **ref**: Git reference (usually branch) to checkout in the repository
    - **path**: Path to sync from in the git repository. If the empty string is passed, syncing will happen from the root of the repository.
    - **trusted_gpg_keys**: List of trusted gpp keys to verify the signature of the top commit. If an empty list is passed, the commit signature will not be verified.
    - **auth**: Authentication to the git server. It should have the following keys:
      - **client_ssh_key** Private client ssh key to authentication to the server.
      - **server_ssh_fingerprint**: Public ssh fingerprint of the server that will be used to authentify it.
- **install_dependencies**: Whether cloud-init should install external dependencies (should be set to false if you already provide an image with the external dependencies built-in).

# Gotcha

To safeguard against potential outage, changes to the server's user data will be ignored without reprovisioning.

To change most parameters in coredns, you should explicitly reprovision the nodes.