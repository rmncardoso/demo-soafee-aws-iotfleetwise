#!/bin/bash

# deploy-stack.sh
set -e

# Configuration
STACK_NAME="deployment-environment"
TEMPLATE_FILE="deploy.yaml"
REGION="eu-central-1"
KEY_NAME="deployment-key"  # We'll create this key pair

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Starting deployment script...${NC}"

# Check if template file exists
if [ ! -f "$TEMPLATE_FILE" ]; then
    echo -e "${RED}Error: Template file $TEMPLATE_FILE not found${NC}"
    exit 1
fi

# Create key pair if it doesn't exist
if ! aws ec2 describe-key-pairs --key-names "$KEY_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo -e "${YELLOW}Creating new key pair: $KEY_NAME${NC}"
    aws ec2 create-key-pair \
        --key-name "$KEY_NAME" \
        --query 'KeyMaterial' \
        --output text \
        --region "$REGION" > "${KEY_NAME}.pem"
    
    # Secure the key file
    chmod 400 "${KEY_NAME}.pem"
    echo -e "${GREEN}Created and saved key pair to ${KEY_NAME}.pem${NC}"
fi

# Check if stack exists
if aws cloudformation describe-stacks --stack-name "$STACK_NAME" --region "$REGION" >/dev/null 2>&1; then
    echo -e "${YELLOW}Stack already exists. Creating change set...${NC}"
    
    # Create change set
    CHANGE_SET_NAME="${STACK_NAME}-$(date +%Y%m%d-%H%M%S)"
    aws cloudformation create-change-set \
        --stack-name "$STACK_NAME" \
        --template-body "file://$TEMPLATE_FILE" \
        --change-set-name "$CHANGE_SET_NAME" \
        --parameters ParameterKey=KeyPairName,ParameterValue="$KEY_NAME" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"

    # Wait for change set to be created
    echo "Waiting for change set to be created..."
    aws cloudformation wait change-set-create-complete \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --region "$REGION"

    # Execute change set
    echo -e "${YELLOW}Executing change set...${NC}"
    aws cloudformation execute-change-set \
        --stack-name "$STACK_NAME" \
        --change-set-name "$CHANGE_SET_NAME" \
        --region "$REGION"

else
    echo -e "${YELLOW}Creating new stack...${NC}"
    # Create stack
    aws cloudformation create-stack \
        --stack-name "$STACK_NAME" \
        --template-body "file://$TEMPLATE_FILE" \
        --parameters ParameterKey=KeyPairName,ParameterValue="$KEY_NAME" \
        --capabilities CAPABILITY_IAM \
        --region "$REGION"
fi

# Wait for stack operation to complete
echo -e "${YELLOW}Waiting for stack operation to complete...${NC}"
aws cloudformation wait stack-create-complete --stack-name "$STACK_NAME" --region "$REGION" || \
aws cloudformation wait stack-update-complete --stack-name "$STACK_NAME" --region "$REGION"

# Get stack outputs
echo -e "${GREEN}Stack operation completed. Fetching outputs...${NC}"
aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[*].[OutputKey,OutputValue]' \
    --output table \
    --region "$REGION"

# Get instance private IP
PRIVATE_IP=$(aws cloudformation describe-stacks \
    --stack-name "$STACK_NAME" \
    --query 'Stacks[0].Outputs[?OutputKey==`PrivateIP`].OutputValue' \
    --output text \
    --region "$REGION")

echo -e "${GREEN}Deployment completed successfully!${NC}"
echo -e "${YELLOW}Instance Private IP: ${NC}${PRIVATE_IP}"
echo -e "${YELLOW}You can connect to the instance using AWS Systems Manager Session Manager${NC}"
echo -e "To connect using Session Manager, run:"
echo -e "${GREEN}aws ssm start-session --target \$(aws ec2 describe-instances --filters \"Name=private-ip-address,Values=${PRIVATE_IP}\" --query 'Reservations[0].Instances[0].InstanceId' --output text --region ${REGION}) --region ${REGION}${NC}"

# Save connection command to a file
echo "#!/bin/bash" > connect.sh
echo "aws ssm start-session --target \$(aws ec2 describe-instances --filters \"Name=private-ip-address,Values=${PRIVATE_IP}\" --query 'Reservations[0].Instances[0].InstanceId' --output text --region ${REGION}) --region ${REGION}" >> connect.sh
chmod +x connect.sh

echo -e "${YELLOW}A 'connect.sh' script has been created to easily connect to your instance${NC}"
