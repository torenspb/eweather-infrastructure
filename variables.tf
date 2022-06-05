variable "region" {
  type        = string
  default     = "eu-north-1"
  description = "Region to deploy infrastructure in"
}

variable "app_name" {
  type        = string
  default     = "eweather"
  description = "Name of the application. Also used as a ECS cluster name"
}

variable "ecs_instance_type" {
  type        = string
  default     = "t3.micro"
  description = "Type of EC2 instance used as ECS instance"
}

variable "min_ec2_amount" {
  type        = number
  default     = 2
  description = "Minimum amount of running EC2 instances"
}

variable "max_ec2_amount" {
  type        = number
  default     = 2
  description = "Maximum amount of running EC2 instances"
}

variable "default_docker_image" {
  type        = string
  default     = "spolikarpov/eweather:latest"
  description = "Docker image name of the application last version"
}

variable "containers_amount" {
  type        = number
  default     = 8
  description = "Amount of desired ECS tasks to run"
}