#!/bin/bash
# expose-zipline-web.sh

set -e

# Source trading platform environment
source /home/costas778/abc/trading-platform/set-env.sh

# Set working directory
WORK_DIR="/home/costas778/abc/trading-platform"
cd $WORK_DIR

# Create a service for Zipline
cat << EOF > $WORK_DIR/k8s/zipline-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: zipline-service
spec:
  selector:
    app: zipline
  ports:
  - port: 80
    targetPort: 8000
  type: ClusterIP
EOF

# Create a ConfigMap for Zipline configuration
cat << EOF > $WORK_DIR/k8s/zipline-config.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: zipline-config
data:
  config.py: |
    import os
    import json
    import boto3
    from botocore.exceptions import ClientError

    # Function to get secrets from AWS Secrets Manager
    def get_secret(secret_name):
        region_name = "us-east-1"
        session = boto3.session.Session()
        client = session.client(
            service_name='secretsmanager',
            region_name=region_name
        )
        try:
            get_secret_value_response = client.get_secret_value(
                SecretId=secret_name
            )
        except ClientError as e:
            raise e
        else:
            if 'SecretString' in get_secret_value_response:
                return json.loads(get_secret_value_response['SecretString'])
            else:
                return None

    # Get database credentials from AWS Secrets Manager
    db_credentials = get_secret('db-credentials')

    # Zipline configuration
    config = {
        'database_uri': f"postgresql://{db_credentials['username']}:{db_credentials['password']}@{db_credentials['host']}:{db_credentials['port']}/zipline",
        'start_date': '2010-01-01',
        'end_date': '2020-01-01',
        'data_frequency': 'daily',
        'capital_base': 100000,
    }
EOF

# Check if an ALB ingress already exists for trading applications
EXISTING_INGRESS=$(kubectl get ingress -l app.kubernetes.io/name=trading-platform -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")

if [ -z "$EXISTING_INGRESS" ]; then
  echo "No existing trading platform ingress found. Creating a new one..."
  
  # Create a new ingress for Zipline
  cat << EOF > $WORK_DIR/k8s/zipline-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: trading-platform-ingress
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: trading-platform
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}, {"HTTPS": 443}]'
    alb.ingress.kubernetes.io/ssl-redirect: '443'
  labels:
    app.kubernetes.io/name: trading-platform
spec:
  rules:
  - http:
      paths:
      - path: /zipline
        pathType: Prefix
        backend:
          service:
            name: zipline-service
            port:
              number: 80
EOF

  # Apply the new ingress
  kubectl apply -f $WORK_DIR/k8s/zipline-ingress.yaml
  
else
  echo "Existing trading platform ingress found: $EXISTING_INGRESS"
  
  # Update the existing ingress to include Zipline
  echo "Adding Zipline path to existing ingress..."
  
  # Create a temporary patch file
  cat << EOF > $WORK_DIR/k8s/ingress-patch.yaml
spec:
  rules:
  - http:
      paths:
      - path: /zipline
        pathType: Prefix
        backend:
          service:
            name: zipline-service
            port:
              number: 80
EOF

  # Apply the patch to add the Zipline path
  kubectl patch ingress $EXISTING_INGRESS --patch "$(cat $WORK_DIR/k8s/ingress-patch.yaml)"
fi

# Apply the service and config
kubectl apply -f $WORK_DIR/k8s/zipline-service.yaml
kubectl apply -f $WORK_DIR/k8s/zipline-config.yaml

# Create a deployment for Zipline with AWS Secrets Manager integration
cat << EOF > $WORK_DIR/k8s/zipline-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: zipline
  labels:
    app: zipline
spec:
  replicas: 2
  selector:
    matchLabels:
      app: zipline
  template:
    metadata:
      labels:
        app: zipline
    spec:
      containers:
      - name: zipline
        image: 992382855794.dkr.ecr.us-east-1.amazonaws.com/zipline:latest
        ports:
        - containerPort: 8000
        env:
        - name: AWS_REGION
          value: "us-east-1"
        volumeMounts:
        - name: config-volume
          mountPath: /app/config
      volumes:
      - name: config-volume
        configMap:
          name: zipline-config
EOF

# Apply the deployment
kubectl apply -f $WORK_DIR/k8s/zipline-deployment.yaml

# Get the ALB address
ALB_ADDRESS=$(kubectl get ingress $EXISTING_INGRESS -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || 
              kubectl get ingress trading-platform-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null)

if [ ! -z "$ALB_ADDRESS" ]; then
  echo "Your Zipline web interface will be available at: https://$ALB_ADDRESS/zipline"
else
  echo "ALB address not available yet. Please check the ingress status later."
fi

echo "Zipline integration complete!"
