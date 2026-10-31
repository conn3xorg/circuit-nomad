# A batch job that prints a line and exits, to prove a client ran it.
job "hello" {
  type        = "batch"
  datacenters = ["*"]

  group "hello" {
    task "hello" {
      driver = "exec"

      config {
        command = "/bin/sh"
        args    = ["-c", "echo hello from $NOMAD_ALLOC_ID"]
      }

      resources {
        cpu    = 50
        memory = 32
      }
    }
  }
}
