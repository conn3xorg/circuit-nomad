# Three servers and a client, in the four containers CI starts on ports 2221
# to 2224. CI passes the servers' addresses on the Podman network.
variable "join_addresses" {
  type = list(string)
}

variable "gossip_key" {
  type      = string
  ephemeral = true
  sensitive = true
  default   = "Yo8Lxr3Qk0V8yq6mS2vI2u4x1Hc9oZbqP7sTfNwKe0Q="
}

module "nomad" {
  source = "../.."

  servers = {
    s1 = { address = "127.0.0.1", port = 2221 }
    s2 = { address = "127.0.0.1", port = 2222 }
    s3 = { address = "127.0.0.1", port = 2223 }
  }
  clients        = { c1 = { address = "127.0.0.1", port = 2224 } }
  join_addresses = var.join_addresses
  gossip_key     = var.gossip_key
  # See examples/local: Arm virtual machines report no CPU clock.
  client_config        = { client = { cpu_total_compute = 2000 } }
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}
