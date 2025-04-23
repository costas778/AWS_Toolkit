#!/bin/bash
set -e

# Check if repository exists
if ! aws ecr describe-repositories --region us-east-1 | grep -q freqtrade; then
  echo "Creating ECR repository for Freqtrade..."
  aws ecr create-repository --repository-name freqtrade --region us-east-1
else
  echo "ECR repository for Freqtrade already exists."
fi

# Log in to ECR
echo "Logging in to ECR..."
aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 339712995243.dkr.ecr.us-east-1.amazonaws.com

# Pull the official Freqtrade image
echo "Pulling Freqtrade image..."
docker pull freqtradeorg/freqtrade:stable

# Tag it for your ECR
echo "Tagging image for ECR..."
docker tag freqtradeorg/freqtrade:stable 339712995243.dkr.ecr.us-east-1.amazonaws.com/freqtrade:latest

# Push to your ECR
echo "Pushing image to ECR..."
docker push 339712995243.dkr.ecr.us-east-1.amazonaws.com/freqtrade:latest

echo "Freqtrade image is now available in your ECR repository."
