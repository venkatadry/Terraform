If you want to access the web app **only from the private subnet**, there are a couple of approaches you can follow. A common pattern in this situation is to:

1. **Place the web application in the private subnet**, meaning it will not be directly accessible from the internet.
2. **Use a Bastion Host** in the public subnet (which is accessible from the internet) to SSH into the private subnet, or
3. **Use a Load Balancer** to route traffic from the public subnet to the private subnet.

For this solution, I will modify the code so that:

- The **web server EC2 instance** is placed in the **private subnet**.
- The **Bastion Host** is placed in the **public subnet**, allowing you to SSH into the private subnet.
- Security group rules are configured to allow **SSH access from the Bastion Host** and **HTTP access from the Bastion Host** to the web server in the private subnet.

### Modified Code for Private Subnet Access Only

#### 1. **VPC, Subnets, and Route Tables**
We will keep the same VPC and subnet configuration, but update the route tables for better clarity.

```hcl
provider "aws" {
  region = "us-east-1"
}

resource "aws_vpc" "example_vpc" {
  cidr_block = "10.0.0.0/16"
  tags = {
    Name = "VPC-Example"
  }
}

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
    Name = "Vpc-Example-private-subnet"
  }
}

resource "aws_internet_gateway" "example_igw" {
  vpc_id = aws_vpc.example_vpc.id
  tags = {
    Name = "Vpc-Example-IG"
  }
}

# Route table for the public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.example_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.example_igw.id
  }
  tags = {
    Name = "Vpc-Example-rt-public"
  }
}

resource "aws_route_table_association" "public_rt_association" {
  subnet_id      = aws_subnet.public_subnet.id
  route_table_id = aws_route_table.public_rt.id
}

# Route table for the private subnet (uses NAT Gateway for outbound traffic)
resource "aws_route_table" "private_rt" {
  vpc_id = aws_vpc.example_vpc.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.example_nat.id
  }

  tags = {
    Name = "Vpc-Example-rt-private"
  }
}

resource "aws_route_table_association" "private_rt_association" {
  subnet_id      = aws_subnet.private_subnet.id
  route_table_id = aws_route_table.private_rt.id
}

# Elastic IP for NAT Gateway
resource "aws_eip" "nat_eip" {
  vpc = true
}

# NAT Gateway for private subnet outbound internet access
resource "aws_nat_gateway" "example_nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public_subnet.id
  tags = {
    Name = "Vpc-Example-Nat-Gateway"
  }
}
```

#### 2. **Security Groups**

We will configure security groups so that:
- The **Web Server EC2 instance** is accessible from the **private subnet**.
- The **Bastion Host** is the only way to SSH into the private subnet.

```hcl
resource "aws_security_group" "allow_bastion" {
  name        = "allow_bastion_ssh"
  description = "Allow SSH from anywhere to Bastion Host"
  vpc_id      = aws_vpc.example_vpc.id
  
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Open for SSH from anywhere (modify to restrict to your IP in production)
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_bastion"
  }
}

resource "aws_security_group" "allow_web" {
  name        = "allow_web_traffic"
  description = "Allow HTTP inbound traffic from Bastion Host"
  vpc_id      = aws_vpc.example_vpc.id
  
  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_subnet.cidr_block]  # Allow traffic from the Bastion Host
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

resource "aws_security_group" "allow_private_subnet" {
  name        = "allow_private_subnet"
  description = "Allow access from the Bastion Host to Web Server"
  vpc_id      = aws_vpc.example_vpc.id
  
  ingress {
    description = "HTTP from Bastion Host"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [aws_subnet.public_subnet.cidr_block]  # Allow traffic from Bastion Host
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "allow_private_subnet"
  }
}
```

#### 3. **EC2 Instances (Web Server and Bastion Host)**

- **Bastion Host**: This is placed in the **public subnet** to allow SSH access from the internet. It can then access the web server in the private subnet.
- **Web Server**: This is placed in the **private subnet**, where it is not directly accessible from the internet.

```hcl
# Bastion Host in the public subnet (to SSH into the private subnet)
resource "aws_instance" "bastion_host" {
  ami                        = "ami-084568db4383264d4"  # Replace with an appropriate AMI
  instance_type              = "t2.micro"
  subnet_id                  = aws_subnet.public_subnet.id
  vpc_security_group_ids     = [aws_security_group.allow_bastion.id]
  associate_public_ip_address = true
  key_name                   = "aws-key-all"  # Replace with your key pair name
  tags = {
    Name = "bastion-host"
  }
}

# Web Server in the private subnet
resource "aws_instance" "web_server" {
  ami                        = "ami-084568db4383264d4"  # Replace with an appropriate AMI
  instance_type              = "t2.micro"
  subnet_id                  = aws_subnet.private_subnet.id
  vpc_security_group_ids     = [aws_security_group.allow_private_subnet.id]
  associate_public_ip_address = false  # No public IP, it's in the private subnet
  key_name                   = "aws-key-all"  # Replace with your key pair name
  user_data = <<-EOF
              #!/bin/bash
              yum update -y
              yum install -y httpd
              systemctl start httpd
              systemctl enable httpd
              echo "<h1>Hello World from $(hostname -f)</h1>" > /var/www/html/index.html
              EOF
  tags = {
    Name = "web-server"
  }
}
```

### Key Changes:
1. **Web Server in Private Subnet**: The web server is placed in the **private subnet** and is only accessible via the Bastion Host.
2. **Bastion Host**: The Bastion Host is in the **public subnet**, which can SSH into the private subnet and allows you to access the web server.
3. **Security Groups**: 
   - The **Bastion Host** allows SSH (port 22) from the internet.
   - The **Web Server** only allows HTTP (port 80) traffic from the **Bastion Host**.
   - The **Bastion Host** must be used to SSH into the private subnet.

### Accessing the Web Server:
1. **SSH into the Bastion Host**: First, you SSH into the **Bastion Host** (public subnet).
   ```bash
   ssh -i your-key.pem ec2-user@<bastion-host-public-ip>
   ```
2. **Access the Web Server**: Once you're in the **Bastion Host**, you can **SSH into the Web Server** (private subnet) using its private IP address.
   ```bash
   ssh ec2-user@<web-server-private-ip>
   ```

3. To access the **web application** from the **Bastion Host**:
   - You can use `curl` or a web browser (if a GUI is available on the Bastion Host) to access the web server’s private IP on port 80.
   ```bash
   curl http://<web-server-private-ip>
   ```

This configuration restricts direct internet access to the web app, but you can access it from the **private subnet** via the Bastion Host.
