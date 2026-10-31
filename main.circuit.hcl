# Facts give each host's architecture, which picks the Nomad build.
data "conn3x_host" "facts" {
  for_each = merge(var.servers, var.clients)

  ssh {
    host             = try(each.value.address, each.value)
    host_key         = try(each.value.host_key, null)
    user             = try(each.value.user, var.ssh_user)
    port             = try(each.value.port, var.ssh_port)
    private_key_file = try(each.value.private_key_file, var.ssh_private_key_file)
    jump_hosts       = try(each.value.jump_hosts, null)
    known_hosts_file = var.ssh_known_hosts_file
  }
}

locals {
  join = coalesce(var.join_addresses, [for s in var.servers : try(s.advertise, s.address, s)])

  arch = { x86_64 = "amd64", aarch64 = "arm64" }
  zip  = { for name, f in data.conn3x_host.facts : name => "nomad_${var.nomad_version}_linux_${local.arch[f.arch]}.zip" }

  # The zip stays on the host, so a plan can check its checksum without
  # downloading it again. Installing through a temporary file replaces the
  # binary even while Nomad runs from it, and install puts it where SELinux
  # labels it as a program.
  install = { for name, zip in local.zip : name => {
    command = "unzip -o -q /opt/nomad/${zip} nomad -d /opt/nomad/unpack && install -m 0755 /opt/nomad/unpack/nomad /usr/local/bin/nomad && rm -rf /opt/nomad/unpack"
    unless  = "/usr/local/bin/nomad version | grep -q '^Nomad v${var.nomad_version}$'"
  } }

  # Left alone, Nomad advertises the first private address it finds, which
  # on a host with several networks may not be one the others can reach.
  agent = { for name, h in merge(var.servers, var.clients) : name => merge({
    datacenter = var.datacenter
    data_dir   = "/opt/nomad/data"
    acl        = { enabled = var.acl_enabled }
    }, can(h.advertise) ? {
    advertise = { http = h.advertise, rpc = h.advertise, serf = h.advertise }
  } : {}) }

  # From the unit HashiCorp's packages install. The start timeout makes an
  # agent that can't start fail the apply instead of hanging it. A server
  # needs no more than its own data directory, so it runs as the nomad user.
  # A client starts your jobs, which needs root.
  unit = <<-EOT
    [Unit]
    Description=Nomad
    Documentation=https://developer.hashicorp.com/nomad/docs
    Wants=network-online.target
    After=network-online.target

    [Service]
    User=%USER%
    Group=%USER%
    Type=notify
    TimeoutStartSec=5min
    ExecReload=/bin/kill -HUP $MAINPID
    ExecStart=/usr/local/bin/nomad agent -config /etc/nomad.d
    KillMode=process
    KillSignal=SIGINT
    LimitNOFILE=65536
    LimitNPROC=infinity
    Restart=on-failure
    RestartSec=2
    TasksMax=infinity
    OOMScoreAdjust=-1000

    [Install]
    WantedBy=multi-user.target
  EOT
}

circuit "nomad_servers" {
  hosts = var.servers

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Minimal images can lack these, which the download and the install need.
  step "curl" {
    package {
      name = "curl"
    }
  }

  step "unzip" {
    package {
      name = "unzip"
    }
  }

  step "group" {
    group {
      name   = "nomad"
      system = true
    }
  }

  step "user" {
    user {
      name   = "nomad"
      group  = "nomad"
      system = true
      shell  = "/usr/sbin/nologin"
    }
  }

  step "dir" {
    directory {
      path = "/opt/nomad"
    }
  }

  step "download" {
    download {
      url    = "https://releases.hashicorp.com/nomad/${var.nomad_version}/${local.zip[each.key]}"
      sha256 = var.checksums[local.arch[data.conn3x_host.facts[each.key].arch]]
      dest   = "/opt/nomad/${local.zip[each.key]}"
    }
  }

  step "binary" {
    command {
      command = local.install[each.key].command
      unless  = local.install[each.key].unless
    }
    notify = [handler.restart]
  }

  step "data_dir" {
    directory {
      path  = "/opt/nomad/data"
      owner = "nomad"
      group = "nomad"
      mode  = "0700"
    }
  }

  step "config_dir" {
    directory {
      path  = "/etc/nomad.d"
      owner = "root"
      group = "nomad"
      mode  = "0750"
    }
  }

  step "config" {
    file {
      path = "/etc/nomad.d/10-agent.json"
      content = jsonencode(merge(local.agent[each.key], {
        server = {
          enabled          = true
          bootstrap_expect = length(var.servers)
          server_join      = { retry_join = local.join }
        }
      }))
      owner = "root"
      group = "nomad"
      mode  = "0640"
    }
    notify = [handler.restart]
  }

  step "gossip_key" {
    file {
      path       = "/etc/nomad.d/20-gossip.json"
      content_wo = jsonencode({ server = { encrypt = var.gossip_key } })
      owner      = "root"
      group      = "nomad"
      mode       = "0640"
    }
    notify = [handler.restart]
  }

  step "extra" {
    file {
      path    = "/etc/nomad.d/50-extra.json"
      content = jsonencode(var.server_config)
      owner   = "root"
      group   = "nomad"
      mode    = "0640"
    }
    notify = [handler.restart]
  }

  step "unit" {
    file {
      path    = "/etc/systemd/system/nomad.service"
      content = replace(local.unit, "%USER%", "nomad")
    }
    notify = [handler.restart]
  }

  step "running" {
    service {
      name    = "nomad"
      state   = "started"
      enabled = true
    }
  }

  step "api" {
    wait_for {
      port = 4646
    }
  }

  # One server at a time, so a change never takes the cluster below a
  # majority.
  handler "restart" {
    service {
      name   = "nomad"
      serial = true
    }
  }
}

circuit "nomad_clients" {
  hosts = var.clients

  ssh {
    user             = var.ssh_user
    port             = var.ssh_port
    private_key_file = var.ssh_private_key_file
    known_hosts_file = var.ssh_known_hosts_file
    become           = var.ssh_become
  }

  # Clients join once every server is up.
  step "curl" {
    depends_on = [conn3x_wait_for.nomad_servers__api, conn3x_service_action.nomad_servers__restart]
    package {
      name = "curl"
    }
  }

  step "unzip" {
    package {
      name = "unzip"
    }
  }

  # A client looks up its network interfaces with ip, and won't start
  # without it.
  step "iproute" {
    package {
      name = data.conn3x_host.facts[each.key].os_family == "debian" ? "iproute2" : "iproute"
    }
  }

  step "dir" {
    directory {
      path = "/opt/nomad"
    }
  }

  step "download" {
    download {
      url    = "https://releases.hashicorp.com/nomad/${var.nomad_version}/${local.zip[each.key]}"
      sha256 = var.checksums[local.arch[data.conn3x_host.facts[each.key].arch]]
      dest   = "/opt/nomad/${local.zip[each.key]}"
    }
  }

  step "binary" {
    command {
      command = local.install[each.key].command
      unless  = local.install[each.key].unless
    }
    notify = [handler.restart]
  }

  step "data_dir" {
    directory {
      path = "/opt/nomad/data"
      mode = "0711"
    }
  }

  step "config_dir" {
    directory {
      path = "/etc/nomad.d"
      mode = "0750"
    }
  }

  step "config" {
    file {
      path = "/etc/nomad.d/10-agent.json"
      content = jsonencode(merge(local.agent[each.key], {
        client = {
          enabled     = true
          server_join = { retry_join = local.join }
        }
      }))
      mode = "0640"
    }
    notify = [handler.restart]
  }

  step "extra" {
    file {
      path    = "/etc/nomad.d/50-extra.json"
      content = jsonencode(var.client_config)
      mode    = "0640"
    }
    notify = [handler.restart]
  }

  step "unit" {
    file {
      path    = "/etc/systemd/system/nomad.service"
      content = replace(local.unit, "%USER%", "root")
    }
    notify = [handler.restart]
  }

  step "running" {
    service {
      name    = "nomad"
      state   = "started"
      enabled = true
    }
  }

  handler "restart" {
    service {
      name = "nomad"
    }
  }
}
