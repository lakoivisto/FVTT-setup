resource "aws_key_pair" "fvtt" {
  key_name   = "fvtt-key"
  public_key = file(var.ssh_public_key_path)
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd-gp3/ubuntu-noble-24.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

resource "aws_security_group" "fvtt" {
  name        = "fvtt-sg"
  description = "SSH and FoundryVTT access"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.whitelist]
  }

  ingress {
    description = "FoundryVTT"
    from_port   = 30000
    to_port     = 30000
    protocol    = "tcp"
    cidr_blocks = [var.whitelist]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "fvtt" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.fvtt.key_name
  vpc_security_group_ids = [aws_security_group.fvtt.id]

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "fvtt"
  }
}
