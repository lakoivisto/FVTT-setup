output "public_dns" {
  value = aws_instance.fvtt.public_dns
}

output "public_ip" {
  value = aws_instance.fvtt.public_ip
}

output "sslip_hostname" {
  description = "Hostname for HTTPS via sslip.io, derived from EC2 public IP"
  value       = "fvtt.${replace(aws_instance.fvtt.public_ip, ".", "-")}.sslip.io"
}
