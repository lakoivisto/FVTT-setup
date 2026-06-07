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
    description = "HTTP (Lets Encrypt challenge + redirect to HTTPS)"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

data "aws_iam_policy_document" "fvtt_backup_assume_role" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "fvtt_backup" {
  name               = "fvtt-backup-role"
  assume_role_policy = data.aws_iam_policy_document.fvtt_backup_assume_role.json
}

data "aws_iam_policy_document" "fvtt_backup_s3" {
  statement {
    actions   = ["s3:ListBucket"]
    resources = ["arn:aws:s3:::${var.foundrydata_backup_bucket}"]
  }

  statement {
    actions   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
    resources = ["arn:aws:s3:::${var.foundrydata_backup_bucket}/*"]
  }
}

resource "aws_iam_role_policy" "fvtt_backup_s3" {
  name   = "fvtt-backup-s3-access"
  role   = aws_iam_role.fvtt_backup.id
  policy = data.aws_iam_policy_document.fvtt_backup_s3.json
}

resource "aws_iam_instance_profile" "fvtt_backup" {
  name = "fvtt-backup-profile"
  role = aws_iam_role.fvtt_backup.name
}

resource "aws_instance" "fvtt" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.fvtt.key_name
  vpc_security_group_ids = [aws_security_group.fvtt.id]
  iam_instance_profile   = aws_iam_instance_profile.fvtt_backup.name

  root_block_device {
    volume_size = 8
  }

  tags = {
    Name = "fvtt"
  }
}

resource "aws_eip" "fvtt" {
  instance = aws_instance.fvtt.id
  domain   = "vpc"

  tags = {
    Name = "fvtt"
  }
}
