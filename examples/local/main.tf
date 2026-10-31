variable "port" {
  type    = number
  default = 2222
}

variable "server_ip" {
  type        = string
  description = "The server container's address on the Podman network. up.sh writes it to terraform.tfvars."
}

variable "gossip_key" {
  type      = string
  ephemeral = true
  sensitive = true
  # An example key, for this throwaway cluster only.
  default = "Yo8Lxr3Qk0V8yq6mS2vI2u4x1Hc9oZbqP7sTfNwKe0Q="
}

module "nomad" {
  source = "../.."

  servers        = { server1 = { address = "127.0.0.1", port = var.port } }
  clients        = { client1 = { address = "127.0.0.1", port = var.port + 1 } }
  join_addresses = [var.server_ip]
  gossip_key     = var.gossip_key
  # Arm virtual machines, such as a Podman machine on a Mac, don't report a
  # CPU clock, and with no CPU to give, Nomad places nothing on the client.
  client_config        = { client = { cpu_total_compute = 2000 } }
  ssh_private_key_file = "./id_ed25519"
  ssh_known_hosts_file = "./known_hosts"
}
