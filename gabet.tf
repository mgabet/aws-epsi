####PROVIDER####
provider "aws" {
    version = "~> 2.0"
    region = "us-east-1"
}

####CREATION VPC####
resource "aws_vpc" "terraform_vpc"{
    cidr_block = "10.0.0.0/16"
    
    tags = {
        name = "terraform_vpc"
    }
}

####SUBNETS####
 resource "aws_subnet" "public-a"{
     vpc_id = aws_vpc.terraform_vpc.id
     cidr_block = "10.0.1.0/24"
     
     tags = {
         Name = "public-a-tf"
     }
 }
 resource "aws_subnet" "public-b"{
     vpc_id = aws_vpc.terraform_vpc.id
     cidr_block = "10.0.2.0/24"
     
     tags = {
         Name = "public-b-tf"
     }
 }
####GATEWAY####
 resource "aws_internet_gateway" "gw"{
     vpc_id = aws_vpc.terraform_vpc.id
     
     tags = {
         Name = "igw-tf"
     }
 }
####ROUTETABLE####
 resource "aws_route_table" "r" {
  vpc_id = aws_vpc.terraform_vpc.id
  
  route{
   cidr_block = "0.0.0.0/0"
   gateway_id = aws_internet_gateway.gw.id
   }
   tags = {
   Name = "internet-tf"
  }
 }
####ROUTE TABLE ASSO####
 resource "aws_route_table_association" "a"{
  subnet_id = aws_subnet.public-a.id
  route_table_id = aws_route_table.r.id
 }
 
 resource "tls_private_key" "key_terraform" {
  algorithm   = "RSA"
  rsa_bits = 4096
}
 
 resource "aws_key_pair" "deployer"{
  key_name = "ec2-key-tf"
  public_key = tls_private_key.key_terraform.public_key_openssh
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

  owners = ["099720109477"] # Canonical 
}

resource "aws_security_group" "allow_http" {
  name        = "allow_tls"
  description = "Allow http inbound traffic"
  vpc_id      = "${aws_vpc.terraform_vpc.id}"

  ingress {
    description = "HTTP from VPC"
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
    Name = "allow_http-tf"
  }
}

resource "aws_instance" "web" {
  ami = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  subnet_id = aws_subnet.public-a.id
  key_name = aws_key_pair.deployer.id
  associate_public_ip_address = true
  user_data = file("${path.module}/postinstall.sh")
  vpc_security_group_ids = ["${aws_security_group.allow_http.id}"]

  tags = {
    Name = "HelloWorld"
  }
}

resource "aws_lb" "alb_terraform" {
  name               = "alb_terraform"
  internal           = false
  load_balancer_type = "application"
  security_groups    = ["${aws_security_group.allow_http.id}"]
  subnets            = ["${aws_subnet.public-a.id}"]

resource "aws_lb_target_group" "target_group_tf" {
  name     = "target_group_tf"
  port     = 80
  protocol = "HTTP"
  vpc_id   = aws_vpc.terraform_vpc.id
}
resource "aws_lb_target_group_attachment" "target_group_attachment_tf" {
  target_group_arn = aws_lb_target_group.target_group_tf.arn
  target_id        = aws_instance.target_group_tf.id
  port             = 80
  }
}

resource "aws_placement_group" "pl-gr" {
  name     = "pl-gr"
  strategy = "cluster"
}

resource "aws_autoscaling_group" "bar" {
  name                      = "foobar3-terraform-test"
  max_size                  = 3
  min_size                  = 2
  health_check_grace_period = 300
  health_check_type         = "ELB"
  desired_capacity          = 1
  force_delete              = true
  placement_group           = "${aws_placement_group.pl-gr.id}"
  launch_configuration      = "${aws_launch_configuration.lc_terraform.name}"
  vpc_zone_identifier       = ["${aws_subnet.public-a.id}", "${aws_subnet.public-b.id}"]

  initial_lifecycle_hook {
    name                 = "foobar"
    terraform_vpc_result       = "CONTINUE"
    heartbeat_timeout    = 2000
    lifecycle_transition = "autoscaling:EC2_INSTANCE_LAUNCHING"

    notification_metadata = <<EOF
{
  "foo": "bar"
}
EOF

    notification_target_arn = "arn:aws:sqs:us-east-1:444455556666:queue1*"
    role_arn                = "arn:aws:iam::123456789012:role/S3Access"
  }
}

resource "aws_lb_listener" "alb_listner_terraform" {
  load_balancer_arn = aws_lb.alb_terraform.arn
  port              = "80"
  protocol          = "HTTP"

  terraform_vpc_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.lb_target_group_tf.arn
  }
}

resource "aws_launch_configuration" "lc_terraform" {
  image_id = data.aws_ami.ubuntu.id
  instance_type = "t2.micro"
  security_groups = aws_security_group.allow_http.id
  user_data = file("${post_install.sh}")
}

 output "private-key"{
  value = tls_private_key.key_terraform.private_key_pem
 }

output "ami-value" {
  value = data.aws_ami.ubuntu.image_id
}

output "public-ip" {
  value = aws_instance.web.public_ip
}

####FIN FICHIER####