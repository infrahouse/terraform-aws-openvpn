#!/usr/bin/env bash

aws ecr get-login-password --region us-east-2 | docker login --username AWS --password-stdin 303467602807.dkr.ecr.us-east-2.amazonaws.com
docker build -t portal .
docker tag portal:latest 303467602807.dkr.ecr.us-east-2.amazonaws.com/portal:latest
docker push 303467602807.dkr.ecr.us-east-2.amazonaws.com/portal:latest
