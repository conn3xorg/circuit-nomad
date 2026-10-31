variable "servers" {
  type        = any
  description = "Server nodes, by name: a map of names to addresses, or to host objects with an address and optional host_key, user, port, private_key_file, jump_hosts or advertise. Give an odd number."

  validation {
    condition     = length(var.servers) % 2 == 1
    error_message = "Give an odd number of servers, such as 1, 3 or 5. Raft needs a majority to elect a leader, so an even number adds a machine without letting the cluster lose one more."
  }
}

variable "clients" {
  type        = any
  default     = {}
  description = "Client nodes, which run your jobs, by name, in the same form as servers. A name can't be both a server and a client."

  validation {
    condition     = length(setintersection(keys(var.servers), keys(var.clients))) == 0
    error_message = "A name can't be both a server and a client."
  }
}

variable "gossip_key" {
  type        = string
  ephemeral   = true
  sensitive   = true
  description = "Key that encrypts the servers' gossip traffic: 32 bytes in base64, from nomad operator gossip keyring generate or openssl rand -base64 32. Pass it at run time with -var or TF_VAR_gossip_key; it never reaches state or the plan."

  validation {
    condition     = can(regex("^[A-Za-z0-9_+/-]{43}=?$", var.gossip_key))
    error_message = "gossip_key must be 32 bytes in base64, such as the output of nomad operator gossip keyring generate."
  }
}

variable "join_addresses" {
  type        = list(string)
  default     = null
  description = "Addresses nodes use to find the servers. When null, each server's advertise address, or else its address. Set it when Conn3x reaches the servers on a different address from the one the nodes use."
}

variable "acl_enabled" {
  type        = bool
  default     = true
  description = "Turn on Nomad's ACLs. Until you run nomad acl bootstrap, nobody can do anything through the API. Without ACLs, anyone who reaches port 4646 can run jobs on your clients."
}

variable "datacenter" {
  type        = string
  default     = "dc1"
  description = "Datacenter the nodes belong to."

  validation {
    condition     = can(regex("^[a-zA-Z0-9_-]+$", var.datacenter))
    error_message = "datacenter may use letters, digits, - and _."
  }
}

variable "server_config" {
  type        = any
  default     = {}
  description = "More agent settings for the servers, written to /etc/nomad.d/50-extra.json, such as { tls = { http = true, rpc = true } }. Nomad merges this over the circuit's own settings."
}

variable "client_config" {
  type        = any
  default     = {}
  description = "More agent settings for the clients, written to /etc/nomad.d/50-extra.json, such as { client = { node_pool = \"gpu\" } }. Nomad merges this over the circuit's own settings."
}

variable "nomad_version" {
  type        = string
  default     = "2.1.1"
  description = "Nomad release to install, without the v. Change it together with checksums."

  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.nomad_version))
    error_message = "nomad_version must look like 2.1.1. Enterprise builds aren't supported."
  }
}

variable "checksums" {
  type        = map(string)
  description = "SHA-256 of the Nomad zip for each architecture, from the release's SHA256SUMS file. Change these with nomad_version."
  default = {
    amd64 = "073084f7690fdaea756ff1eff8b669b25c3a6c17778f19ae0c47606973ed3f39"
    arm64 = "ed7222af2f9b924262a8c4e053688ad9e7a7c82fa9485d6d147261072b3b8d50"
  }
}

variable "ssh_user" {
  type        = string
  default     = "root"
  description = "User to log in as."
}

variable "ssh_port" {
  type        = number
  default     = 22
  description = "SSH port."
}

variable "ssh_private_key_file" {
  type        = string
  default     = null
  description = "Path to a private key. When null, Conn3x uses the SSH agent."
}

variable "ssh_known_hosts_file" {
  type        = string
  default     = null
  description = "known_hosts file to check host keys against. When null, ~/.ssh/known_hosts."
}

variable "ssh_become" {
  type        = bool
  default     = false
  description = "Run commands as root through sudo."
}
