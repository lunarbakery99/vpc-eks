terraform {
  required_providers {
    aws = {
      source = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

#Create a VPC
resource "aws_vpc" "sample" {
  cidr_block = "10.50.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
  tags = {
    Name = "eks-vpc"
  }
}

#Create an IGW
resource "aws_internet_gateway" "sample" {
#Attach IGW to created VPC
#if VPC declared in same file, use following phrase
  vpc_id = aws_vpc.sample.id
  tags = {
    Name = "eks-vpc-igw"
  }
}

#Create Public Subnets
resource "aws_subnet" "pub-sub1" {
  vpc_id = aws_vpc.sample.id
  cidr_block = "10.50.10.0/24"
#Auto-assign IP settings
  map_public_ip_on_launch = true
#Enable resource name DNS A record on launch
  enable_resource_name_dns_a_record_on_launch = true
#subnet AZ
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "pub-sub1"
#if using EKS with Kubetnetes version below 1.14
    #kubernetes.io/cluster/my-cluster	= owned

#EKS with loadbalancer
    "kubernetes.io/role/elb" = 1
  }
  depends_on = [ aws_internet_gateway.sample ]
}

resource "aws_subnet" "pub-sub2" {
  vpc_id = aws_vpc.sample.id
  cidr_block = "10.50.11.0/24"
  map_public_ip_on_launch = true
  enable_resource_name_dns_a_record_on_launch = true
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "pub-sub2"
    "kubernetes.io/role/elb" = 1
  }
  depends_on = [ aws_internet_gateway.sample ]
}

#Create Private Subnets
resource "aws_subnet" "pri-sub1" {
  vpc_id = aws_vpc.sample.id
  cidr_block = "10.50.20.0/24"
  enable_resource_name_dns_a_record_on_launch = true
  availability_zone = "ap-northeast-2a"

  tags = {
    Name = "pri-sub1"
    "kubernetes.io/role/elb" = 1
  }
  depends_on = [ aws_nat_gateway.sample ]
}

resource "aws_subnet" "pri-sub2" {
  vpc_id = aws_vpc.sample.id
  cidr_block = "10.50.21.0/24"
  enable_resource_name_dns_a_record_on_launch = true
  availability_zone = "ap-northeast-2c"

  tags = {
    Name = "pri-sub2"
    "kubernetes.io/role/elb" = 1
  }
  depends_on = [ aws_nat_gateway.sample ]
}

#Allocate an Elastic IP
resource "aws_eip" "sample" {
  lifecycle {
    create_before_destroy = true
  }
}

#Create a NatGW
resource "aws_nat_gateway" "sample" {
  allocation_id = aws_eip.sample.id
  subnet_id = aws_subnet.pub-sub1.id
  tags = {
    Name = "eks-vpc-natgw"
  }
  lifecycle {
    create_before_destroy = true
  }
}

#Create a Public Subnet Routing Table
resource "aws_route_table" "pub-rt" {
  vpc_id = aws_vpc.sample.id

  route {
    cidr_block = "10.50.0.0/16"
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sample.id
  }

  tags = {
    Name = "eks-vpc-pub-rt"
  }
}

#Create a Private Subnet Routing Table
resource "aws_route_table" "pri-rt" {
  vpc_id = aws_vpc.sample.id

  route {
    cidr_block = "10.50.0.0/16"
    gateway_id = "local"
  }
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_nat_gateway.sample.id
  }

  tags = {
    Name = "eks-vpc-pri-rt"
  }
}
#Coonect RT with Public Subnets
resource "aws_route_table_association" "pub1-rt-asso" {
  subnet_id = aws_subnet.pub-sub1.id
  route_table_id = aws_route_table.pub-rt.id
}
resource "aws_route_table_association" "pub2-rt-asso" {
  subnet_id = aws_subnet.pub-sub2.id
  route_table_id = aws_route_table.pub-rt.id
}

#Coonect RT with Private Subnets
resource "aws_route_table_association" "pri1-rt-asso" {
  subnet_id = aws_subnet.pri-sub1.id
  route_table_id = aws_route_table.pri-rt.id
}
resource "aws_route_table_association" "pri2-rt-asso" {
  subnet_id = aws_subnet.pri-sub2.id
  route_table_id = aws_route_table.pri-rt.id
}

#Create Security Groups
resource "aws_security_group" "eks-vpc-pub-sg" {
  vpc_id = aws_vpc.sample.id
  name = "eks-vpc-pub-sg"
  tags = {
    Name = "eks-vpc-pub-sg"
  }
}

#SG Ingress Rules
resource "aws_security_group_rule" "eks-vpc-http-ingress" {
  type = "ingress"
  from_port = 80
  to_port = 80
  protocol = "TCP"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
      create_before_destroy = true
    }
}
resource "aws_security_group_rule" "eks-vpc-ssh-ingress" {
  type = "ingress"
  from_port = 22
  to_port = 22
  protocol = "TCP"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
      create_before_destroy = true
    }
}

#SG Egress rules
resource "aws_security_group_rule" "eks-vpc-all-egress" {
  type = "egress"
  from_port = 0
  to_port = 0
  protocol = "-1"
  cidr_blocks = ["0.0.0.0/0"]
  security_group_id = aws_security_group.eks-vpc-pub-sg.id
  lifecycle {
    create_before_destroy = true
  }
}