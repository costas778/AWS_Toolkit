
#!/bin/bash
set -e
# Create the key and save its ID
KEY_ID=$(aws kms create-key \
  --description "FreqTrade environment variables encryption key" \
  --tags TagKey=Environment,TagValue=Production \
  --query 'KeyMetadata.KeyId' \
  --output text)

# Create an alias for easier reference
aws kms create-alias \
  --alias-name alias/freqtrade-env \
  --target-key-id $KEY_ID

echo "Created KMS key with ID: $KEY_ID"
