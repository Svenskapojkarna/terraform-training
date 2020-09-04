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

variable "bucket_name_prefix" {}
variable "billing_code_tag" {}
variable "environment_tag" {}

variable "instance_count" {
    default = 2
}

variable "subnet_count" {
    default = 2
}

# Provider

provider "aws" {
  access_key    = var.aws_access_key
  secret_key    = var.aws_secret_key
  region        = var.region
}

# Locals

locals {
    common_tags = {
        BillingCode = var.billing_code_tag
        Environment = var.environment_tag
    }
    s3_bucket_name = "${var.bucket_name_prefix}-${var.environment_tag}-${random_integer.rand.result}"
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

## Random ID

resource "random_integer" "rand" {
    min = 10000
    max = 99999
}

## Networking

resource "aws_vpc" "vpc" {
    cidr_block  = var.network_address_space
    tags        = merge(local.common_tags, {Name = "${var.environment_tag}-vpc"})
}

resource "aws_internet_gateway" "igw" {
    vpc_id = aws_vpc.vpc.id
    tags   = merge(local.common_tags, {Name = "${var.environment_tag}-igw"})
}

resource "aws_subnet" "subnet" {
    count                   = var.subnet_count
    cidr_block              = cidrsubnet(var.network_address_space, 8, count.index)
    vpc_id                  = aws_vpc.vpc.id
    map_public_ip_on_launch = true
    availability_zone       = data.aws_availability_zones.available.names[count.index]
    tags                    = merge(local.common_tags, {Name = "${var.environment_tag}-subnet${count.index + 1}"})
}

## Routing

resource "aws_route_table" "rtb" {
    vpc_id = aws_vpc.vpc.id
    tags   = merge(local.common_tags, {Name = "${var.environment_tag}-rtb"})

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.igw.id
    }
}

resource "aws_route_table_association" "rta-subnet" {
    count           = var.subnet_count
    subnet_id       = aws_subnet.subnet[count.index].id
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
    subnets         = aws_subnet.subnet[*].id
    security_groups = [aws_security_group.elb-sg.id]
    instances       = aws_instance.nginx[*].id

    listener {
        instance_port       = 80
        instance_protocol   = "http"
        lb_port             = 80
        lb_protocol         = "http"
    }
}

## S3 Bucket Config

resource "aws_iam_role" "allow_nginx_s3" {
    name                = "allow_nginx_s3"
    assume_role_policy  = <<EOF
                            {
                                "Version": "2020-09-04",
                                "Statement": [
                                    {
                                        "Action": "sts:AssumeRole",
                                        "Principal": {
                                            "Service": "ec2.amazonaws.com"
                                        },
                                        "Effect": "Allow",
                                        "Sid": ""
                                    }
                                ]
                            }
                            EOF
}

resource "aws_iam_instance_profile" "nginx_profile" {
    name = "nginx_profile"
    role = aws_iam_role.allow_nginx_s3.name
}

resource "aws_iam_role_policy" "allow_s3_all" {
    name    = "allow_s3_all"
    role    = aws_iam_role.allow_nginx_s3.name
    policy  = <<EOF
                {
                "Version": "2020-09-04",
                "Statement": [
                        {
                        "Action": [
                            "s3:*"
                        ],
                        "Effect": "Allow",
                        "Resource": [
                                    "arn:aws:s3:::${local.s3_bucket_name}",
                                    "arn:aws:s3:::${local.s3_bucket_name}/*"
                                ]
                        }
                    ]
                }
                EOF
}

resource "aws_s3_bucket" "web_bucket" {
    bucket          = local.s3_bucket_name
    acl             = "private"
    force_destroy   = true
    tags            = merge(local.common_tags, {Name = "${var.environment_tag}-web-bucket"})
}

resource "aws_s3_bucket_object" "website" {
    bucket  = aws_s3_bucket.web_bucket.bucket
    key     = "/website/index.html"
    source  = "./web/index.html"
}

resource "aws_s3_bucket_object" "graphic" {
    bucket  = aws_s3_bucket.web_bucket.bucket
    key     = "/website/Globo_logo_Vert.png"
    source  = "./web/Globo_logo_Vert.png"
}

## Instances

resource "aws_instance" "nginx" {
  count                     = var.instance_count
  ami                       = data.aws_ami.aws-linux.id
  instance_type             = "t2.micro"
  subnet_id                 = aws_subnet.subnet[count.index % var.subnet_count].id
  vpc_security_group_ids    = [aws_security_group.nginx-sg.id]
  key_name                  = var.key_name
  iam_instance_profile      = aws_iam_instance_profile.nginx_profile.name
  depends_on                = [aws_iam_role_policy.allow_s3_all]
  tags                      = merge(local.common_tags, {Name = "${var.environment_tag}-nginx${count.index + 1}"})

  connection {
      type          = "ssh"
      host          = self.public_ip
      user          = "ec2-user"
      private_key   = file(var.private_key_path)
  }

  provisioner "file" {
        content = <<EOF
                    access_key      =
                    secret_key      =
                    security_token  =
                    use_https       = True
                    bucket_location = EU
                    EOF
        destination = "/home/ec2-user/.s3cfg"
  }
  
  provisioner "file" {
        content = <<EOF
                    /var/log/nginx/*log {
                        daily
                        rotate 10
                        missingok
                        compress
                        sharedscripts
                        postrotate
                        endscript
                        lastaction
                            INSTANCE_ID='curl --silent http://169.254.169.254/latest/meta-data/instance-id'
                            sudo /usr/local/bin/s3cmd sync --config=/home/ec2-user/.s3cfg /var/log/nginx/ s3://${aws_s3_bucket.web_bucket.id}/nginx/$INSTANCE_ID/
                        endscript
                    }
                    EOF
        destination = "/home/ec2-user/nginx"
  }

  provisioner "remote-exec" {
      inline = [
          "sudo amazon-linux-extras enable nginx1",
          "sudo yum install nginx -y",
          "sudo systemctl start nginx",
          "sudo cp /home/ec2-user/.s3cfg /root/.s3cfg",
          "sudo cp /home/ec2-user/nginx /etc/logrotate.d/nginx",
          "sudo pip install s3cmd",
          "s3cmd get s3://${aws_s3_bucket.web_bucket.id}/website/index.html .",
          "s3cmd get s3://${aws_s3_bucket.web_bucket.id}/website/Globo_logo_Vert.png .",
          "sudo cp /home/ec2-user/index.html /usr/share/nginx/html/index.html",
          "sudo cp /home/ec2-user/Globo_logo_Vert.png /usr/share/nginx/html/Globo_logo_Vert.png",
          "sudo logrotate -f /etc/logrotate.conf"
      ]
  }
}

# Output

output "aws_instance_public_dns" {
    value = aws_elb.web.dns_name
}
