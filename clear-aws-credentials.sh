#!/bin/bash

# Color coding for output
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "Clearing AWS credentials and configuration..."

# Unset AWS environment variables
unset AWS_ACCESS_KEY_ID
unset AWS_SECRET_ACCESS_KEY
unset AWS_SESSION_TOKEN
unset AWS_SECURITY_TOKEN
unset AWS_DEFAULT_REGION
unset AWS_PROFILE

# Remove AWS config files if they exist
if [ -f ~/.aws/credentials ]; then
    rm -f ~/.aws/credentials && echo -e "${GREEN}Removed ~/.aws/credentials${NC}" || echo -e "${RED}Failed to remove ~/.aws/credentials${NC}"
fi

if [ -f ~/.aws/config ]; then
    rm -f ~/.aws/config && echo -e "${GREEN}Removed ~/.aws/config${NC}" || echo -e "${RED}Failed to remove ~/.aws/config${NC}"
fi

# Optionally remove the entire .aws directory if it exists
if [ -d ~/.aws ]; then
    rm -rf ~/.aws && echo -e "${GREEN}Removed ~/.aws directory${NC}" || echo -e "${RED}Failed to remove ~/.aws directory${NC}"
fi

# Verify environment variables are unset
echo -e "\nVerifying AWS environment variables:"
echo "AWS_ACCESS_KEY_ID: ${AWS_ACCESS_KEY_ID:-unset}"
echo "AWS_SECRET_ACCESS_KEY: ${AWS_SECRET_ACCESS_KEY:-unset}"
echo "AWS_SESSION_TOKEN: ${AWS_SESSION_TOKEN:-unset}"
echo "AWS_SECURITY_TOKEN: ${AWS_SECURITY_TOKEN:-unset}"
echo "AWS_DEFAULT_REGION: ${AWS_DEFAULT_REGION:-unset}"
echo "AWS_PROFILE: ${AWS_PROFILE:-unset}"

echo -e "\n${GREEN}AWS credentials and configuration cleared successfully!${NC}"

aws configure

