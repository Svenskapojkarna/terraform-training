# Variables

variable "aws_access_key" {}
variable "aws_secret_key" {}
variable "private_key_path" {}
variable "key_name" {}

variable "region" {
    default = "eu-central-1"
}

variable "network_address_space" {
    default = "10.1.0.0/16"
}

variable "subnet1_address_space" {
    default = "10.1.0.0/24"
}

variable "subnet2_address_space" {
    default = "10.1.1.0/24"
}

# Provider

provider "aws" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  region        = var.region
}

# Data

data "aws_availability_zones" "available" {}

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

## Networking

resource "aws_vpc" "vpc" {
    cidr_block              = var.network_address_space
    enable_dns_hostnames    = true
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc.id
}

resource "aws_subnet" "subnet1" {
    cidr_block              = var.subnet1_address_space
    vpc_id                  = aws_vpc.vpc.id
    map_public_ip_on_launch = true
    availability_zone       = data.aws_availability_zones.available.names[0]
}

resource "aws_subnet" "subnet2" {
    cidr_block              = var.subnet2_address_space
    vpc_id                  = aws_vpc.vpc.id
    map_public_ip_on_launch = true
    availability_zone       = data.aws_availability_zones.available.names[1]
}

## Routing

resource "aws_route_table" "rtb" {
    vpc_id = aws_vpc.vpc.id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
}

resource "aws_route_table_association" "rta-subnet1" {
    subnet_id       = aws_subnet.subnet1.id
    route_table_id  = aws_route_table.rtb.id
}

resource "aws_route_table_association" "rta-subnet2" {
    subnet_id       = aws_subnet.subnet2.id
    route_table_id  = aws_route_table.rtb.id
}

## Security groups

resource "aws_security_group" "elb-sg" {
    name          = "elb_sg"
    vpc_id        = aws_vpc.vpc.id
  
    # HTTP access
    ingress {
        from_port     = 80
        to_port       = 80
        protocol      = "tcp"
        cidr_blocks   = ["0.0.0.0/0"]
    }

    # outbound internet access
    egress {
        from_port     = 0
        to_port       = 0
        protocol      = -1
        cidr_blocks   = ["0.0.0.0/0"]
    }
}


resource "aws_security_group" "nginx-sg" {
    name          = "nginx_sg"
    vpc_id        = aws_vpc.vpc.id

    # SSH access
    ingress {
        from_port     = 22
        to_port       = 22
        protocol      = "tcp"
        cidr_blocks   = ["0.0.0.0/0"]
    }
  
    # HTTP access
    ingress {
        from_port     = 80
        to_port       = 80
        protocol      = "tcp"
        cidr_blocks   = [var.network_address_space]
    }

    # outbound internet access
    egress {
        from_port     = 0
        to_port       = 0
        protocol      = -1
        cidr_blocks   = ["0.0.0.0/0"]
    }
}

## Load balancer

resource "aws_elb" "web" {
    name            = "nginx-elb"
    subnets         = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
    security_groups = [aws_security_group.elb-sg.id]
    instances       = [aws_instance.nginx1.id, aws_instance.nginx2.id]

    listener {
        instance_port       = 80
        instance_protocol   = "http"
        lb_port             = 80
        lb_protocol         = "http"
    }
}

## Instances

resource "aws_instance" "nginx1" {
  ami                       = data.aws_ami.aws-linux.id
  instance_type             = "t2.micro"
  subnet_id                 = aws_subnet.subnet1.id
  key_name                  = var.key_name
  vpc_security_group_ids    = [aws_security_group.nginx-sg.id]

  connection {
      type          = "ssh"
      host          = self.public_ip
      user          = "ec2-user"
      private_key   = file(var.private_key_path)
  }

  provisioner "remote-exec" {
      inline = [
          "sudo amazon-linux-extras enable nginx1",
          "sudo yum -y install nginx",
          "sudo systemctl start nginx"
      ]
  }
}

resource "aws_instance" "nginx2" {
  ami                       = data.aws_ami.aws-linux.id
  instance_type             = "t2.micro"
  subnet_id                 = aws_subnet.subnet2.id
  key_name                  = var.key_name
  vpc_security_group_ids    = [aws_security_group.nginx-sg.id]

  connection {
      type          = "ssh"
      host          = self.public_ip
      user          = "ec2-user"
      private_key   = file(var.private_key_path)
  }

  provisioner "remote-exec" {
      inline = [
          "sudo amazon-linux-extras enable nginx1",
          "sudo yum -y install nginx",
          "sudo systemctl start nginx"
      ]
  }
}

# Output

output "aws_instance_public_dns" {
    value = aws_elb.web.dns_name
}
