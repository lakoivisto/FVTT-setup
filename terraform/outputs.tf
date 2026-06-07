output "public_dns" {
  value = aws_instance.fvtt.public_dns
}

output "public_ip" {
  value = aws_eip.fvtt.public_ip
}

output "sslip_hostname" {
  description = "Stable hostname for HTTPS via sslip.io, derived from the Elastic IP"
  value       = "fvtt.${replace(aws_eip.fvtt.public_ip, ".", "-")}.sslip.io"
}
