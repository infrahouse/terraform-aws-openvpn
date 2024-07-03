#!/usr/bin/env bash

set -eux

export AWS_DEFAULT_REGION=us-east-2

AWS_PROFILE="infrahouse-admin-cicd"

aws --profile $AWS_PROFILE sts get-caller-identity || aws --profile infrahouse-admin-cicd sso login

aws --profile $AWS_PROFILE ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 303467602807.dkr.ecr.us-east-2.amazonaws.com
docker build -t portal .
docker tag portal:latest 303467602807.dkr.ecr.us-east-2.amazonaws.com/portal:latest
docker push 303467602807.dkr.ecr.us-east-2.amazonaws.com/portal:latest


aws --profile $AWS_PROFILE ecs update-service --cluster openvpn-portal --service openvpn-portal --force-new-deployment > /dev/null
echo "Restarting the portal service. Please wait..."
aws --profile $AWS_PROFILE ecs wait services-stable --cluster openvpn-portal --services openvpn-portal
echo "done"
