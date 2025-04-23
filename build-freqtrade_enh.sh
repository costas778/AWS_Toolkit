#!/bin/bash
set -e

# Default values
NAMESPACE="default"
ENV="dev"
COLOR=""

# Function to display usage
usage() {
    echo "Usage: $0 [-e environment] [-c color] [-n namespace]"
    echo "  -e : Environment (dev/staging/prod) [default: dev]"
    echo "  -c : Color (blue/green) [optional]"
    echo "  -n : Namespace [default: default]"
    exit 1
}

# Parse command line arguments
while getopts "e:c:n:h" opt; do
    case $opt in
        e)
            ENV="$OPTARG"
            ;;
        c)
            COLOR="$OPTARG"
            ;;
        n)
            NAMESPACE="$OPTARG"
            ;;
        h)
            usage
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            ;;
    esac
done

# Validate environment
if [[ ! "$ENV" =~ ^(dev|staging|prod)$ ]]; then
    echo "Error: Environment must be dev, staging, or prod"
    exit 1
fi

# Validate color if provided
if [ -n "$COLOR" ] && [[ ! "$COLOR" =~ ^(blue|green)$ ]]; then
    echo "Error: Color must be blue or green"
    exit 1
fi

# Set namespace based on whether COLOR is provided
if [ -n "$COLOR" ]; then
    NAMESPACE="freqtrade-${ENV}-${COLOR}"
else
    NAMESPACE="freqtrade-${ENV}"
fi

echo "Building Freqtrade for namespace: $NAMESPACE"

# Create namespace if it doesn't exist
kubectl get namespace $NAMESPACE || kubectl create namespace $NAMESPACE

echo "Building Freqtrade for $ENV environment..."

# Get the directory of this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="$SCRIPT_DIR"

# Check if AWS Load Balancer Controller is installed
echo "Checking if AWS Load Balancer Controller is installed..."
if ! kubectl get deployment -n kube-system aws-load-balancer-controller &> /dev/null; then
    echo "AWS Load Balancer Controller is not installed."
    echo "Installing AWS Load Balancer Controller..."
    
    # Make sure the script is executable
    chmod +x "${SCRIPT_DIR}/install-alb-controller-for-freqtrade.sh"
    
    # Run the installation script
    "${SCRIPT_DIR}/install-alb-controller-for-freqtrade.sh"
else
    echo "AWS Load Balancer Controller is already installed."
fi

# Check if ALB IngressClass exists
echo "Checking if ALB IngressClass exists..."
if ! kubectl get ingressclass alb &> /dev/null; then
    echo "Creating ALB IngressClass..."
    cat << EOF | kubectl apply -f -
apiVersion: networking.k8s.io/v1
kind: IngressClass
metadata:
  name: alb
spec:
  controller: ingress.k8s.aws/alb
EOF
else
    echo "ALB IngressClass already exists."
fi

# Get AWS account ID and set up ECR
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
AWS_REGION=$(aws configure get region)
ECR_REPO_NAME="freqtrade"
ECR_REPO_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}"

# Create k8s directory if it doesn't exist
mkdir -p $WORK_DIR/k8s

# Create ConfigMap for Freqtrade configuration
echo "Creating Kubernetes configmap YAML..."
cat << EOF > $WORK_DIR/k8s/freqtrade-configmap.yaml
apiVersion: v1
kind: ConfigMap
metadata:
  name: freqtrade-config
  namespace: $NAMESPACE
data:
  config.json: |
    {
      "max_open_trades": 5,
      "stake_currency": "USDT",
      "stake_amount": 20,
      "tradable_balance_ratio": 0.99,
      "fiat_display_currency": "USD",
      "dry_run": true,
      "strategy": "SimpleStrategy",
      "cancel_open_orders_on_exit": false,
      "unfilledtimeout": {
        "entry": 10,
        "exit": 10,
        "exit_timeout_count": 0,
        "unit": "minutes"
      },
      "entry_pricing": {
        "price_side": "same",
        "use_order_book": true,
        "order_book_top": 1,
        "price_last_balance": 0.0,
        "check_depth_of_market": {
          "enabled": false,
          "bids_to_ask_delta": 1
        }
      },
      "exit_pricing": {
        "price_side": "same",
        "use_order_book": true,
        "order_book_top": 1
      },
      "exchange": {
        "name": "kraken",
        "key": "",
        "secret": "",
        "ccxt_config": {},
        "ccxt_async_config": {},
        "pair_whitelist": [
          "BTC/USDT",
          "ETH/USDT",
          "SOL/USDT",
          "ADA/USDT",
          "DOGE/USDT"
        ],
        "pair_blacklist": []
      },
      "bot_name": "freqtrade",
      "initial_state": "running",
      "force_entry_enable": false,
      "internals": {
        "process_throttle_secs": 5
      },
      "pairlists": [
        {
          "method": "StaticPairList",
          "config": {
            "pairs": ["BTC/USDT", "ETH/USDT", "SOL/USDT", "ADA/USDT", "DOGE/USDT"]
          }
        }
      ],
      "api_server": {
        "enabled": true,
        "listen_ip_address": "0.0.0.0",
        "listen_port": 8080,
        "verbosity": "info",
        "enable_openapi": true,
        "jwt_secret_key": "somethingrandom",
        "CORS_origins": ["*"],
        "username": "admin",
        "password": "admin"
      }
    }

  strategy.py: |
    from freqtrade.strategy import IStrategy, IntParameter
    import pandas as pd
    import talib.abstract as ta
    import numpy as np
    from pandas import DataFrame
    from freqtrade.persistence import Trade
    from datetime import datetime, timedelta
    from functools import reduce
    import talib.abstract as ta
    
    class SimpleStrategy(IStrategy):
        INTERFACE_VERSION = 3
        
        minimal_roi = {
            "0": 0.05
        }
        
        stoploss = -0.10
        timeframe = '5m'
        
        def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
            dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)
            
            # Bollinger Bands
            bollinger = ta.BBANDS(dataframe, timeperiod=20, nbdevup=2.0, nbdevdn=2.0)
            dataframe['bb_lowerband'] = bollinger['lowerband']
            dataframe['bb_middleband'] = bollinger['middleband']
            dataframe['bb_upperband'] = bollinger['upperband']
            
            return dataframe
        
        def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
            dataframe.loc[
                (
                    (dataframe['rsi'] < 30) &
                    (dataframe['close'] < dataframe['bb_lowerband'])
                ),
                'enter_long'] = 1
            
            return dataframe
        
        def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
            dataframe.loc[
                (
                    (dataframe['rsi'] > 70) |
                    (dataframe['close'] > dataframe['bb_upperband'])
                ),
                'exit_long'] = 1
            
            return dataframe
EOF



# Create Kubernetes Deployment YAML
echo "Creating Kubernetes Deployment YAML..."
cat << EOF > $WORK_DIR/k8s/freqtrade-deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: freqtrade
spec:
  replicas: 1
  selector:
    matchLabels:
      app: freqtrade
  template:
    metadata:
      labels:
        app: freqtrade
    spec:
      containers:
      - name: freqtrade
        image: ${ECR_REPO_URI}:latest
        ports:
        - containerPort: 8080
        volumeMounts:
        - name: config-volume
          mountPath: /freqtrade/user_data/config.json
          subPath: config.json
        - name: config-volume
          mountPath: /freqtrade/user_data/strategies/SimpleStrategy.py
          subPath: strategy.py
      volumes:
      - name: config-volume
        configMap:
          name: freqtrade-config
EOF


# Create Kubernetes Service YAML
echo "Creating Kubernetes Service YAML..."
cat << EOF > $WORK_DIR/k8s/freqtrade-service.yaml
apiVersion: v1
kind: Service
metadata:
  name: freqtrade
spec:
  selector:
    app: freqtrade
  ports:
    - protocol: TCP
      port: 8080
      targetPort: 8080
  type: ClusterIP
EOF

cat << EOF > $WORK_DIR/k8s/freqtrade-ingress.yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: freqtrade-ingress-${COLOR:-default}
  namespace: $NAMESPACE
  annotations:
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/group.name: "freqtrade-${ENV}"
    alb.ingress.kubernetes.io/healthcheck-path: /api/v1/ping
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTP": 80}]'
    alb.ingress.kubernetes.io/subnets: subnet-0205a48cb185bae19,subnet-0bc878f6ad871f4f9,subnet-0787621bc386612dc
spec:
  ingressClassName: alb
  rules:
  # Rule 1: Match specific hostname
  - host: ${COLOR:+$COLOR.}freqtrade-${ENV}.abc-trading-prod.42web.io
    http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: freqtrade
            port:
              number: 8080
  # Rule 2: Default rule for direct ALB access
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: freqtrade
            port:
              number: 8080
EOF


# Apply Kubernetes resources
echo "Applying Kubernetes resources..."
kubectl apply -f $WORK_DIR/k8s/freqtrade-configmap.yaml -n $NAMESPACE
kubectl apply -f $WORK_DIR/k8s/freqtrade-deployment.yaml -n $NAMESPACE
kubectl apply -f $WORK_DIR/k8s/freqtrade-service.yaml -n $NAMESPACE
kubectl apply -f $WORK_DIR/k8s/freqtrade-ingress.yaml -n $NAMESPACE

echo "Deployment complete for $ENV environment!"
if [ -n "$COLOR" ]; then
    echo "Color: $COLOR"
fi
echo "To access the API locally, use: kubectl port-forward svc/freqtrade 8080:8080"
echo ""
echo "Waiting for ALB to be provisioned (this may take a few minutes)..."
sleep 10

# Try to get the ALB address
ALB_ADDRESS=""
for i in {1..6}; do
    ALB_ADDRESS=$(kubectl get ingress -n $NAMESPACE freqtrade-ingress-${COLOR:-default} -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$ALB_ADDRESS" ]; then
        break
    fi
    echo "Waiting for ALB address... (attempt $i/6)"
    sleep 10
done

if [ -n "$ALB_ADDRESS" ]; then
    echo "Your Freqtrade application is accessible at: http://$ALB_ADDRESS"
    if [ -n "$COLOR" ]; then
        echo "Color deployment: $COLOR"
        echo "Access URL: http://${COLOR}.freqtrade-${ENV}.abc-trading-dev.com"
    else
        echo "Access URL: http://freqtrade-${ENV}.abc-trading-dev.com"
    fi
else
    echo "ALB is still being provisioned. Check the status with:"
    echo "kubectl get ingress freqtrade-ingress-${COLOR:-default} -n $NAMESPACE"
fi
