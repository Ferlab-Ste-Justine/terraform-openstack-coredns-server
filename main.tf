locals {
  fluentbit_updater_etcd = var.fluentbit.enabled && var.fluentbit_dynamic_config.enabled && var.fluentbit_dynamic_config.source == "etcd"
  fluentbit_updater_git  = var.fluentbit.enabled && var.fluentbit_dynamic_config.enabled && var.fluentbit_dynamic_config.source == "git"
  block_devices = var.image_source.volume_id != "" ? [{
    uuid                  = var.image_source.volume_id
    source_type           = "volume"
    boot_index            = 0
    destination_type      = "volume"
    delete_on_termination = false
  }] : []
}

module "coredns_zonefiles_updater_configs" {
  source               = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//configurations-auto-updater?ref=v0.20.0"
  install_dependencies = var.install_dependencies
  filesystem = {
    path                   = "/opt/coredns/zonefiles"
    files_permission       = "700"
    directories_permission = "700"
  }
  etcd = {
    key_prefix         = var.etcd.key_prefix
    endpoints          = var.etcd.endpoints
    connection_timeout = "10s"
    request_timeout    = "10s"
    retry_interval     = "500ms"
    retries            = 10
    auth = {
      ca_certificate     = var.etcd.ca_certificate
      client_certificate = var.etcd.client.certificate
      client_key         = var.etcd.client.key
      username           = var.etcd.client.username
      password           = var.etcd.client.password
    }
  }
  naming = {
    binary  = "coredns-zonefiles-updater"
    service = "coredns-zonefiles-updater"
  }
  user = "coredns"
}

module "coredns_configs" {
  source               = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//coredns?ref=v0.24.0"
  install_dependencies = var.install_dependencies
  dns = {
    dns_bind_addresses         = [var.network_port.all_fixed_ips.0]
    observability_bind_address = var.network_port.all_fixed_ips.0
    nsid                       = var.name
    zonefiles_reload_interval  = var.dns.zonefiles_reload_interval
    load_balance_records       = var.dns.load_balance_records
    alternate_dns_servers      = var.dns.alternate_dns_servers
    forwards                   = var.dns.forwards
    cache_settings             = var.dns.cache_settings
  }
}

module "prometheus_node_exporter_configs" {
  source               = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//prometheus-node-exporter?ref=v0.20.0"
  install_dependencies = var.install_dependencies
}

module "chrony_configs" {
  source               = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//chrony?ref=v0.20.0"
  install_dependencies = var.install_dependencies
  chrony = {
    servers  = var.chrony.servers
    pools    = var.chrony.pools
    makestep = var.chrony.makestep
  }
}

module "fluentbit_updater_etcd_configs" {
  source               = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//configurations-auto-updater?ref=v0.20.0"
  install_dependencies = var.install_dependencies
  filesystem = {
    path                   = "/etc/fluent-bit-customization/dynamic-config"
    files_permission       = "700"
    directories_permission = "700"
  }
  etcd = {
    key_prefix         = var.fluentbit_dynamic_config.etcd.key_prefix
    endpoints          = var.fluentbit_dynamic_config.etcd.endpoints
    connection_timeout = "60s"
    request_timeout    = "60s"
    retry_interval     = "4s"
    retries            = 15
    auth = {
      ca_certificate     = var.fluentbit_dynamic_config.etcd.ca_certificate
      client_certificate = var.fluentbit_dynamic_config.etcd.client.certificate
      client_key         = var.fluentbit_dynamic_config.etcd.client.key
      username           = var.fluentbit_dynamic_config.etcd.client.username
      password           = var.fluentbit_dynamic_config.etcd.client.password
    }
  }
  notification_command = {
    command = ["/usr/local/bin/reload-fluent-bit-configs"]
    retries = 30
  }
  naming = {
    binary  = "fluent-bit-config-updater"
    service = "fluent-bit-config-updater"
  }
  user = "fluentbit"
}

module "fluentbit_updater_git_configs" {
  source               = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//gitsync?ref=v0.20.0"
  install_dependencies = var.install_dependencies
  filesystem = {
    path                   = "/etc/fluent-bit-customization/dynamic-config"
    files_permission       = "700"
    directories_permission = "700"
  }
  git = var.fluentbit_dynamic_config.git
  notification_command = {
    command = ["/usr/local/bin/reload-fluent-bit-configs"]
    retries = 30
  }
  naming = {
    binary  = "fluent-bit-config-updater"
    service = "fluent-bit-config-updater"
  }
  user = "fluentbit"
}

module "fluentbit_configs" {
  source               = "git::https://github.com/Ferlab-Ste-Justine/terraform-cloudinit-templates.git//fluent-bit?ref=v0.20.0"
  install_dependencies = var.install_dependencies
  fluentbit = {
    metrics = var.fluentbit.metrics
    systemd_services = [
      {
        tag     = var.fluentbit.coredns_tag
        service = "coredns.service"
      },
      {
        tag     = var.fluentbit.coredns_updater_tag
        service = "coredns-zonefiles-updater.service"
      },
      {
        tag     = var.fluentbit.node_exporter_tag
        service = "node-exporter.service"
      }
    ]
    forward = var.fluentbit.forward
  }
  dynamic_config = {
    enabled         = var.fluentbit_dynamic_config.enabled
    entrypoint_path = "/etc/fluent-bit-customization/dynamic-config/index.conf"
  }
}

locals {
  cloudinit_templates = concat([
    {
      filename     = "base.cfg"
      content_type = "text/cloud-config"
      content = templatefile(
        "${path.module}/files/user_data.yaml.tpl",
        {
          hostname             = var.name
          install_dependencies = var.install_dependencies
        }
      )
    },
    {
      filename     = "node_exporter.cfg"
      content_type = "text/cloud-config"
      content      = module.prometheus_node_exporter_configs.configuration
    },
    {
      filename     = "coredns_zonefiles_updater.cfg"
      content_type = "text/cloud-config"
      content      = module.coredns_zonefiles_updater_configs.configuration
    },
    {
      filename     = "coredns.cfg"
      content_type = "text/cloud-config"
      content      = module.coredns_configs.configuration
    }
    ],
    var.chrony.enabled ? [{
      filename     = "chrony.cfg"
      content_type = "text/cloud-config"
      content      = module.chrony_configs.configuration
    }] : [],
    local.fluentbit_updater_etcd ? [{
      filename     = "fluent_bit_updater.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_updater_etcd_configs.configuration
    }] : [],
    local.fluentbit_updater_git ? [{
      filename     = "fluent_bit_updater.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_updater_git_configs.configuration
    }] : [],
    var.fluentbit.enabled ? [{
      filename     = "fluent_bit.cfg"
      content_type = "text/cloud-config"
      content      = module.fluentbit_configs.configuration
    }] : []
  )
}

data "cloudinit_config" "user_data" {
  gzip          = true
  base64_encode = true
  dynamic "part" {
    for_each = local.cloudinit_templates
    content {
      filename     = part.value["filename"]
      content_type = part.value["content_type"]
      content      = part.value["content"]
    }
  }
}

resource "openstack_compute_instance_v2" "coredns_server" {
  name      = var.name
  image_id  = var.image_source.image_id != "" ? var.image_source.image_id : null
  flavor_id = var.flavor_id
  key_pair  = var.keypair_name
  user_data = data.cloudinit_config.user_data.rendered

  network {
    port = var.network_port.id
  }

  dynamic "block_device" {
    for_each = local.block_devices
    content {
      uuid                  = block_device.value["uuid"]
      source_type           = block_device.value["source_type"]
      boot_index            = block_device.value["boot_index"]
      destination_type      = block_device.value["destination_type"]
      delete_on_termination = block_device.value["delete_on_termination"]
    }
  }

  scheduler_hints {
    group = var.server_group.id
  }

  lifecycle {
    ignore_changes = [
      user_data,
    ]
  }
}