variable "region" {
  default = "us-west-1"
}

provider "aws" {
  region = "${var.region}"
}

data "aws_ami" "ubuntu" {
  most_recent = true

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-bionic-18.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["099720109477"]
}

resource "aws_vpc" "tf_network" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_hostnames = true
}

resource "aws_internet_gateway" "gateway" {
  vpc_id = "${aws_vpc.tf_network.id}"
}

resource "aws_subnet" "subnet_a" {
  vpc_id                  = "${aws_vpc.tf_network.id}"
  cidr_block              = "10.0.0.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "${var.region}b"
  depends_on              = ["aws_internet_gateway.gateway"]
}

resource "aws_subnet" "subnet_b" {
  vpc_id                  = "${aws_vpc.tf_network.id}"
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}c"
  map_public_ip_on_launch = true
  depends_on              = ["aws_internet_gateway.gateway"]
}

resource "aws_route_table" "public_rt" {
  vpc_id = "${aws_vpc.tf_network.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.gateway.id}"
  }
}

resource "aws_route_table_association" "public_route_assoc_a" {
  subnet_id      = "${aws_subnet.subnet_a.id}"
  route_table_id = "${aws_route_table.public_rt.id}"
}

resource "aws_route_table_association" "public_route_assoc_b" {
  subnet_id      = "${aws_subnet.subnet_b.id}"
  route_table_id = "${aws_route_table.public_rt.id}"
}

resource "aws_key_pair" "edgenda_key" {
    key_name = "ssh_key"
    public_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC5u7ZUpjWvShNInKjFrsbqV+I75rY/R9sQwdGHWe48TYm8/OetNczmgxRDGGGHIVfRSvEfJv3+soQZk1YjfaWpIOCm96cLO4m3VWAHI3C1IRBBdetwBDpSoKwweVN3457DMgFlGPj+s7KgA9DiVi3Un0q69G/xexlIdmsZYDGvBSbXpSZSh4AO5Bvi+2/EWbQpaTehVL5CSw93AL/4AdGiEXl9Z5iajab2BZWMN+mkA3TmU4UtjG6fKTw51ntO4fDjZDsekONRVoM2FIUXEs2yxoP3B9ZWmE09+csWcPor782ui7mdD2Hr/E2vKE7MkPYqbFAG6WOLZUcqRFmO/Sz1 spark-user@baseImage"
}

resource "aws_security_group" "ensure_ssh_ipv4" {
  vpc_id = "${aws_vpc.tf_network.id}"
  name   = "Ensure_SSH_Allow_All_IPV4"

  ingress {
    to_port     = 22
    from_port   = 22
    protocol    = "TCP"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_http" {
  vpc_id = "${aws_vpc.tf_network.id}"
  name   = "allow_http"

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_https" {
  vpc_id = "${aws_vpc.tf_network.id}"
  name   = "allow_https"

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "allow_all_out_ipv4" {
  vpc_id = "${aws_vpc.tf_network.id}"
  name   = "Allow_All_Out_IPV4"

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "nginxproxy" {
  ami           = "${data.aws_ami.ubuntu.id}"
  key_name      = "${aws_key_pair.edgenda_key.key_name}"
  instance_type = "t2.micro"

  subnet_id                   = "${aws_subnet.subnet_a.id}"
  associate_public_ip_address = "true"

  vpc_security_group_ids = [
    "${aws_security_group.ensure_ssh_ipv4.id}",
    "${aws_security_group.allow_all_out_ipv4.id}",
    "${aws_security_group.allow_http.id}",
    "${aws_security_group.allow_https.id}",
  ]

  provisioner "remote-exec" {
    connection {
      user        = "ubuntu"
      private_key = "${file("~/.ssh/id_rsa")}"
      host 	  = "${self.public_ip}"
    }

    inline = [
      "sudo apt install -y python",
    ]
  }
}
resource "aws_instance" "jenkins" {
  ami           = "${data.aws_ami.ubuntu.id}"
  key_name      = "${aws_key_pair.edgenda_key.key_name}"
  instance_type = "t2.micro"

  subnet_id                   = "${aws_subnet.subnet_b.id}"
  associate_public_ip_address = "true"

  vpc_security_group_ids = [
    "${aws_security_group.ensure_ssh_ipv4.id}",
    "${aws_security_group.allow_all_out_ipv4.id}",
    "${aws_security_group.allow_http.id}",
    "${aws_security_group.allow_https.id}",
  ]

  provisioner "remote-exec" {
    connection {
      user        = "ubuntu"
      private_key = "${file("~/.ssh/id_rsa")}"
      host 	  = "${self.public_ip}"
    }

    inline = [
      "sudo apt install -y python",
    ]
  }
}

resource "ansible_host" "default" {
  count              = 1
  inventory_hostname = "${aws_instance.nginxproxy.id}"

  vars = {
    ansible_user = "ubuntu"
    ansible_host = "${aws_instance.nginxproxy.public_ip}"
  }
}