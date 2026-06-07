variable "aws_region" {
  default = "eu-north-1"
}

variable "instance_type" {
  default = "t3.micro"
}

variable "whitelist" {
  description = "Whitelisted IP in CIDR notation (e.g. 1.2.3.4/32) to restrict SSH access"
  type        = string
}

variable "ssh_public_key_path" {
  description = "Path to the SSH public key to install on the instance"
  type        = string
  default     = "~/.ssh/id_ed25519.pub"
}
