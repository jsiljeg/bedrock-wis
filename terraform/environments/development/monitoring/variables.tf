variable "host"                 { type = string }
variable "user"                 { type = string }
variable "ssh_private_key_path" { type = string }
variable "deploy_path"          { type = string }
variable "healthcheck_url"      { type = string }
variable "alert_env"            { type = string }
variable "send_test_alert"      {
  type = bool
  default = true

}

variable "vault_password_file" {
  type        = string
  default     = "~/.vault_pass.txt"
  description = "Path to Ansible vault password file on the machine running Terraform"
}
