output "join_addresses" {
  description = "Addresses the nodes use to find the servers."
  value       = local.join
}

output "nomad_version" {
  description = "Nomad release the circuit installs."
  value       = var.nomad_version
}
