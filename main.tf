terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "4.16.0"
    }
  }
}

provider "aws" {
  region = var.region
}

// Configuring a new VPC with private and public subnets and NAT gateway enabled //

data "aws_availability_zones" "available" {
  state = "available"
}

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "3.14.0"

  name = "${var.app_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = data.aws_availability_zones.available.zone_ids
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24"]

  enable_nat_gateway = true
  enable_vpn_gateway = false
}

// Configuring security groups for ALB and ASG //

resource "aws_security_group" "alb_sg" {
  name        = "alb_sg"
  description = "Security group for ALB"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "Allow HTTP packets to load balancer"
    cidr_blocks = ["0.0.0.0/0"]
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    "Name" = "${var.app_name}-alb_sg"
  }
}

resource "aws_security_group" "asg_sg" {
  name        = "asg_sg"
  description = "Security group for ASG"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description     = "Allow connections to EC2 instances from ALB"
    security_groups = [aws_security_group.alb_sg.id]
    from_port       = 0
    to_port         = 0
    protocol        = "-1"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = {
    "Name" = "${var.app_name}-asg_sg"
  }
}

// Configuring IAM role needed for ECS //

resource "aws_iam_role" "ecs-instance-role" {
  name = "ecs-instance-role"
  path = "/"

  assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["ec2.amazonaws.com"]
      },
      "Effect": "Allow"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy_attachment" "ecs-instance-role-attachment" {
  role       = aws_iam_role.ecs-instance-role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_instance_profile" "ecs_service_role" {
  role = aws_iam_role.ecs-instance-role.name
}

// Configuring autoscailing group //

data "aws_ami" "ecs_optimized_ami" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }
  owners = ["amazon"]
}

data "template_file" "init" {
  template = file("./scripts/initial_cfg.sh")
  vars = {
    cluster_name = "${var.app_name}"
  }
}

resource "aws_launch_configuration" "ecs_launch_conf" {
  name_prefix          = "ecs_launch_conf-"
  image_id             = data.aws_ami.ecs_optimized_ami.id
  instance_type        = var.ecs_instance_type
  security_groups      = [aws_security_group.asg_sg.id]
  iam_instance_profile = aws_iam_instance_profile.ecs_service_role.name
  user_data            = data.template_file.init.rendered
}

resource "aws_autoscaling_group" "ecs_asg" {
  name                 = "ecs_asg"
  min_size             = var.min_ec2_amount
  max_size             = var.max_ec2_amount
  min_elb_capacity     = 1
  launch_configuration = aws_launch_configuration.ecs_launch_conf.name
  vpc_zone_identifier  = module.vpc.private_subnets
}

// Configuring application load balancer //

resource "aws_lb" "ecs_alb" {
  name               = "ecs-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = module.vpc.public_subnets
}

resource "aws_lb_target_group" "ecs_alb_target" {
  name     = "ecs-alb-target"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.vpc.vpc_id
}

resource "aws_lb_listener" "ecs_alb_listener" {
  load_balancer_arn = aws_lb.ecs_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_alb_target.arn
  }
}

// Configuring ECS cluster ECS service //

resource "aws_ecs_cluster" "ecs_cluster" {
  name = var.app_name
}

resource "aws_ecs_task_definition" "ecs_task_defenition" {
  family = var.app_name
  container_definitions = jsonencode([
    {
      name   = "${var.app_name}"
      image  = "${var.default_docker_image}"
      cpu    = 256
      memory = 128
      portMappings = [
        {
          containerPort = 80
        }
      ]
      healthCheck : {
        command : [
          "CMD-SHELL",
          "wget --spider http://localhost/state || exit 1"
        ]
      },
    }
  ])

}

resource "aws_ecs_service" "service" {
  name                               = var.app_name
  cluster                            = aws_ecs_cluster.ecs_cluster.id
  task_definition                    = aws_ecs_task_definition.ecs_task_defenition.arn
  desired_count                      = var.containers_amount
  deployment_maximum_percent         = 150
  deployment_minimum_healthy_percent = 25
  force_new_deployment               = true
  health_check_grace_period_seconds  = 60

  load_balancer {
    target_group_arn = aws_lb_target_group.ecs_alb_target.arn
    container_name   = var.app_name
    container_port   = 80
  }

  launch_type = "EC2"
  depends_on  = [aws_lb_listener.ecs_alb_listener]
}

// Configuring cloudfront //

resource "aws_cloudfront_distribution" "distribution" {
  enabled         = true
  is_ipv6_enabled = false

  origin {

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 5
      origin_protocol_policy   = "http-only"
      origin_read_timeout      = 30
      origin_ssl_protocols = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2"
      ]
    }
    origin_id   = aws_lb.ecs_alb.dns_name
    domain_name = aws_lb.ecs_alb.dns_name
  }

  default_cache_behavior {
    allowed_methods        = ["GET", "HEAD"]
    cached_methods         = ["GET", "HEAD"]
    compress               = true
    target_origin_id       = aws_lb.ecs_alb.dns_name
    viewer_protocol_policy = "allow-all"
    forwarded_values {
      query_string = false
      cookies {
        forward = "none"
      }
    }
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
  viewer_certificate {
    cloudfront_default_certificate = true
  }
}
