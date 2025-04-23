#!/bin/bash

# Function to encrypt a value using KMS
encrypt_value() {
    local value=$1
    aws kms encrypt \
        --key-id alias/freqtrade-env \
        --plaintext fileb://<(echo -n "$value") \
        --output text \
        --query CiphertextBlob
}

# Read the entire file content
file_content=$(cat "${1}")

# Encrypt the entire content as one value
encrypted=$(encrypt_value "$file_content")
echo "$encrypted"
