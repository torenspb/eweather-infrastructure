#! /bin/bash
sudo touch /etc/ecs/ecs.config
sudo echo "ECS_CLUSTER=${cluster_name}" > /etc/ecs/ecs.config
