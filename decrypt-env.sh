#!/bin/bash

# Function to decrypt KMS encrypted value
decrypt_value() {
    local encrypted_value=$1
    aws kms decrypt \
        --ciphertext-blob fileb://<(echo "$encrypted_value" | base64 -d) \
        --output text \
        --query Plaintext | base64 -d
}

# Read the encrypted content
encrypted_content=$(cat "${1}")

# Decrypt the content
decrypted_content=$(decrypt_value "$encrypted_content")

# Execute the decrypted script content
eval "$decrypted_content"
