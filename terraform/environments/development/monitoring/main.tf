# ---- Deploy monitoring with Ansible-in-Docker ----
resource "null_resource" "ansible_deploy_monitoring" {
  triggers = {
    env  = "development"
    host = var.host
    user = var.user
    fp   = filemd5("${path.module}/../../../../ansible/monitoring.yml")
    deploy = var.deploy_path
  }

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      REPO_ROOT  = abspath("${path.module}/../../../..")
      SSH_KEY    = pathexpand(var.ssh_private_key_path)
      VAULT_PASS = pathexpand(var.vault_password_file)
    }

    command = <<'EOT'
docker run --rm `
  -v "$env:REPO_ROOT:/workspace" `
  -v "$env:SSH_KEY:/root/.ssh/id_rsa:ro" `
  -v "$env:VAULT_PASS:/root/.vault_pass.txt:ro" `
  -w /workspace/ansible `
  -e ANSIBLE_HOST_KEY_CHECKING=False `
  alpine/ansible `
  ansible-playbook -i inventory.ini monitoring.yml `
    --extra-vars "target_host=${var.host} target_user=${var.user} deploy_path=${var.deploy_path} alert_env=${var.alert_env}" `
    --vault-password-file /root/.vault_pass.txt
EOT
  }
}

# ---- Optional smoke alert via the "smoke" tag ----
resource "null_resource" "smoke_alert" {
  triggers = {
    enabled = tostring(var.send_test_alert)
  }

  # Only run if send_test_alert = true
  count = var.send_test_alert ? 1 : 0

  depends_on = [null_resource.ansible_deploy_monitoring]

  provisioner "local-exec" {
    interpreter = ["PowerShell", "-NoProfile", "-Command"]
    environment = {
      REPO_ROOT  = abspath("${path.module}/../../../..")
      SSH_KEY    = pathexpand(var.ssh_private_key_path)
      VAULT_PASS = pathexpand(var.vault_password_file)
    }

    command = <<'EOT'
docker run --rm `
  -v "$env:REPO_ROOT:/workspace" `
  -v "$env:SSH_KEY:/root/.ssh/id_rsa:ro" `
  -v "$env:VAULT_PASS:/root/.vault_pass.txt:ro" `
  -w /workspace/ansible `
  -e ANSIBLE_HOST_KEY_CHECKING=False `
  alpine/ansible `
  ansible-playbook -i inventory.ini monitoring.yml `
    --tags smoke `
    --limit all `
    --extra-vars "target_host=${var.host} target_user=${var.user} deploy_path=${var.deploy_path} alert_env=${var.alert_env}" `
    --vault-password-file /root/.vault_pass.txt
EOT
  }
}
