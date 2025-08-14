#!/usr/bin/env bash

set -eux

AWS_PROFILE="infrahouse-cicd-admin"
AWS_DEFAULT_REGION="$(cat ../Makefile | grep -w "^TEST_REGION" | awk -F = '{ print $2 }' | sed 's/"//g')"
export AWS_DEFAULT_REGION

eval "$(ih-aws --aws-region "$AWS_DEFAULT_REGION" --aws-profile "$AWS_PROFILE" credentials -e)"

AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq -r .Account)

#exit 0

aws ecr get-login-password --region "$AWS_DEFAULT_REGION" \
  | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com"
docker buildx build \
  --platform linux/amd64 \
  -t "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/portal:latest" \
  --push \
  .

aws ecs update-service --cluster openvpn-portal --service openvpn-portal --force-new-deployment > /dev/null
echo "Restarting the portal service. Please wait..."
aws ecs wait services-stable --cluster openvpn-portal --services openvpn-portal
echo "done"
