#https://medium.com/@a-dem/create-a-private-public-vpc-in-aws-with-terraform-1d8e1b8118d2
provider "aws" {
  region = "us-east-1"
}
resource "aws_vpc" "example_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "VPC-Example"
  }
}

# Retrieve the default subnet ID in the default VPC


resource "aws_subnet" "public_subnet" {
  vpc_id     = aws_vpc.example_vpc.id
  cidr_block = "10.0.1.0/24"
  tags = {
    Name = "Vpc-Example-public-subnet"
  }
}
resource "aws_subnet" "private_subnet" {
  vpc_id     = aws_vpc.example_vpc.id
  cidr_block = "10.0.2.0/24"
  tags = {
    Name = "Vpc-Example-Private-subnet"
  }
}
resource "aws_internet_gateway" "example_igw" {
  vpc_id = aws_vpc.example_vpc.id
  tags = {
    Name = "Vpc-Example-IG"
  }
}
resource "aws_route_table" "example_rt" {
  vpc_id = aws_vpc.example_vpc.id
route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example_igw.id
  }
  tags = {
    Name = "Vpc-Example-rt-IG"
  }
}
resource "aws_route_table_association" "public_rt_association" {
subnet_id = aws_subnet.public_subnet.id
route_table_id = aws_route_table.example_rt.id
}

resource "aws_eip" "nat_eip" {
  vpc = true
}

resource "aws_nat_gateway" "example_nat" {
  allocation_id = aws_eip.nat_eip.id
subnet_id = aws_subnet.public_subnet.id
tags = {
    Name = "Vpc-Example-Nat-Gw"
  }
}
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.example_vpc.id

route {
  cidr_block = "0.0.0.0/0"
  nat_gateway_id = aws_nat_gateway.example_nat.id
}
tags = {
    Name = "Vpc-Example-Priate-Nat"
  }
}

resource "aws_route_table_association" "private_rt_association" {
subnet_id = aws_subnet.private_subnet.id
route_table_id = aws_route_table.private_rt.id
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow SSH and HTTP inbound traffic"
  vpc_id      = aws_vpc.example_vpc.id
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Restrict to your IP in production
  }

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_web"
  }
}

# Launch EC2 instance in public subnet
resource "aws_instance" "web_server" {
  ami           = "ami-084568db4383264d4" # Amazon Linux 2 AMI
  instance_type = "t2.micro"
  subnet_id     = aws_subnet.public_subnet.id
  vpc_security_group_ids = [aws_security_group.allow_web.id]
  associate_public_ip_address = true
  key_name      = "aws-key-all" # Replace with your key pair name
  user_data = <<-EOF
              #!/bin/bash
              apt-get update -y
              apt-get install -y apache2
              systemctl start apache2
              systemctl enable apache2
              echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html
              EOF
tags = {
    Name = "web-server"
       }
                         }
