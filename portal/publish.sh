#!/usr/bin/env bash

export AWS_DEFAULT_REGION=us-east-2

aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 303467602807.dkr.ecr.us-east-2.amazonaws.com
docker build -t portal .
docker tag portal:latest 303467602807.dkr.ecr.us-east-2.amazonaws.com/portal:latest
docker push 303467602807.dkr.ecr.us-east-2.amazonaws.com/portal:latest


aws ecs update-service --cluster openvpn-portal --service openvpn-portal --force-new-deployment
aws ecs wait services-stable --cluster openvpn-portal --services openvpn-portal
