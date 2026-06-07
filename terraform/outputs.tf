output "public_dns" {
  value = aws_instance.fvtt.public_dns
}

output "public_ip" {
  value = aws_instance.fvtt.public_ip
}
