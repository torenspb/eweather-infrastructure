# EWeather infrastructure code
This repository contains infrastructure code that is used for EWeather application deployment - https://github.com/torenspb/eweather

Terraform is used to deploy ready-to-use infrastructure on AWS along with deploying the latest version of the application itself. Since the application is "dockerized", an AWS ECS cluster with EC2 launch type is used to host the site.

The infrastructure can be presented as follows:  
![Infrastructure deployed with this code](./img/eweather-infra.png)

Auto scaling group is used to spin-up ECS-optimized EC2 instances which are then used by the ECS cluster as ECS instances. These instances are deployed in private subnets (by default in two separate availability zones).

NAT gateways are deployed in each public subnet in order for the ECS container agent to communicate with the Amazon ECS control plane.

Application load balancer is used to distribute traffic among ECS instances.

ECS service is used to distribute traffic among tasks (containers) on a single ECS instance.

Cloudfront is configured in order to deliver the website content with low latency and high transfer speeds to a larger audience across the globe.

Only incoming HTTP connections are allowed on ALB for security reasons and EC2 instances can only receive incoming traffic from ALB.

# How to deploy
To deploy the infrastructure, make sure AWS access and secret keys for your account are configured, then pull this repository, initialize terraform and apply the configuration:
```
terraform init
terraform apply
```
Terraform will output an address of the deployed web application in the end:
```
Outputs:

application_address = "http://d28ke587oqqk4b.cloudfront.net/"
```

# Scaling up
This code by default deploys two `t3.micro` EC2 instances and launches `8` ECS tasks (containers).

Following actions can be performed in order to scale the service if the application starts consuming more resources:
- change EC2 instance type and increase desired amount of tasks
```
--- a/variables.tf
+++ b/variables.tf
@@ -12,7 +12,7 @@ variable "app_name" {

 variable "ecs_instance_type" {
   type        = string
-  default     = "t3.micro"
+  default     = "t3.large"
   description = "Type of EC2 instance used as ECS instance"
 }

@@ -36,6 +36,6 @@ variable "default_docker_image" {

 variable "containers_amount" {
   type        = number
-  default     = 8
+  default     = 16
   description = "Amount of desired ECS tasks to run"
 }
```
- increase the number of EC2 instances and desired amount of tasks
```
--- a/variables.tf
+++ b/variables.tf
@@ -18,13 +18,13 @@ variable "ecs_instance_type" {

 variable "min_ec2_amount" {
   type        = number
-  default     = 2
+  default     = 4
   description = "Minimum amount of running EC2 instances"
 }

 variable "max_ec2_amount" {
   type        = number
-  default     = 2
+  default     = 4
   description = "Maximum amount of running EC2 instances"
 }

@@ -36,6 +36,6 @@ variable "default_docker_image" {

 variable "containers_amount" {
   type        = number
-  default     = 8
+  default     = 16
   description = "Amount of desired ECS tasks to run"
 }
```
- make both previously described changes together

# Monitoring
This code does not provision any custom AWS CloudFront metrics required for the application. However, metrics are automatically added for all provisioned services in AWS CloudWatch. It's recommended to monitor EC2 (e.g., `CPUUtilization`), ALB (e.g., `RequestCount`, `HTTPCode_Target_4XX_Count`) and ECS (`CPUUtilization`, `MemoryUtilization`) metrics to be sure the application works properly.  

You can also configure an alarm for any of desired metrics if you wish to get notifications on alarm occurrence (remember to pre-configure SNS topic at first).
