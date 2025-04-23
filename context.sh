#!/bin/bash
VALID_ACCOUNT="339712709499"

# Get all contexts
contexts=$(kubectl config get-contexts -o name)

# Loop through each context
for context in $contexts; do
    # If the context doesn't contain the valid account number, delete it
    if [[ ! $context =~ $VALID_ACCOUNT ]]; then
        echo "Removing context: $context"
        kubectl config delete-context "$context"
    fi
done
