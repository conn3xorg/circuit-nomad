# Two servers, which validate must refuse. CI checks that it does.
module "nomad" {
  source = "../.."

  servers    = { s1 = "192.0.2.1", s2 = "192.0.2.2" }
  gossip_key = "Yo8Lxr3Qk0V8yq6mS2vI2u4x1Hc9oZbqP7sTfNwKe0Q="
}
