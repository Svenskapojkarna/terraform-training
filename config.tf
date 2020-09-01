# Variables

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}
variable "region" {
    default = "eu-central-1"
}

# Provider

provider "aws" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  region        = var.region
}

# Data

data "aws_ami" "aws-linux" {
  most_recent   = true
  owners        = ["amazon"]

  filter {
      name      = "image-id"
      values    = ["ami-0c115dbd34c69a004"]
  }

  filter {
      name      = "architecture"
      values    = ["x86_64"]
  }

  filter {
      name      = "root-device-type"
      values    = ["ebs"]
  }

  filter {
      name      = "virtualization-type"
      values    = ["hvm"]
  }
}

# Resources

resource "aws_default_vpc" "default" {}

resource "aws_security_group" "allow_ssh" {
  name          = "nginx_demo"
  description   = "Allow ports for nginx demo"
  vpc_id        = aws_default_vpc.default.id

  ingress {
      from_port     = 22
      to_port       = 22
      protocol      = "tcp"
      cidr_blocks   = ["0.0.0.0/0"]
  }
  
  ingress {
      from_port     = 80
      to_port       = 80
      protocol      = "tcp"
      cidr_blocks   = ["0.0.0.0/0"]
  }

  egress {
      from_port     = 0
      to_port       = 0
      protocol      = -1
      cidr_blocks   = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "nginx" {
  ami                       = data.aws_ami.aws-linux.id
  instance_type             = "t2.micro"
  key_name                  = var.key_name
  vpc_security_group_ids   = [aws_security_group.allow_ssh.id]

  connection {
      type          = "ssh"
      host          = "self.public_ip"
      user          = "ec2-user"
      private_key   = file(var.private_key_path)
  }

  provisioner "remote-exec" {
      inline = [
          "amazon-linux-extras install nginx1",
          "yum -y install nginx",
          "systemctl start nginx"
      ]
  }
}

# Output

output "aws_instance_public_dns" {
    value = aws_instance.nginx.public_dns
}
