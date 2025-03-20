#!/bin/bash
set -e

sudo yum -y update
sudo yum -y install jq gettext bash-completion

echo "Starting Node.js installation script..."

# Install required packages
sudo yum update
sudo yum install -y curl git build-essential

# Download and install nvm
curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.5/install.sh | bash

# Load nvm (by sourcing the script)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"

# Install Node.js LTS version
nvm install 16
nvm use 16
nvm alias default 16


# Add nvm to bash profile if not already added
if ! grep -q "NVM_DIR" ~/.bashrc; then
    echo 'export NVM_DIR="$HOME/.nvm"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"' >> ~/.bashrc
    echo '[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"' >> ~/.bashrc
fi

source ~/.bashrc

# Verify installations
echo "Node.js version:"
node --version
echo "npm version:"
npm --version


echo "Installation completed successfully!"

# Set up AWS environment
if [ -z "${ACCOUNT_ID}" ]; then
    ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
fi

if [ -z "${AWS_REGION}" ]; then
    AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')
fi

if [ -z "${AWS_REGION}" ]; then
    echo "Error: Could not determine AWS_REGION"
    #Fallback to default region if metadata service fails
    AWS_REGION=$(aws configure get region)
fi

if [ -z "${AWS_REGION}" ]; then
    echo "Error: Could not determine AWS_REGION"
    exit 1
fi
if [ -z "${ACCOUNT_ID}" ]; then
    echo "Error: Could not determine ACCOUNT_ID"
    exit 1
fi

# Debug output to verify values
echo "Using AWS_REGION: ${AWS_REGION}"
echo "Using ACCOUNT_ID: ${ACCOUNT_ID}"

aws configure set region "${AWS_REGION}"
aws configure set account "${ACCOUNT_ID}"

aws iotfleetwise register-account

git config --global core.autocrlf false

# Function to check CDK bootstrap status
check_cdk_bootstrap() {
    local account_id=$1
    local region=$2
    
    # Check if CDK bootstrap stack exists
    if aws cloudformation describe-stacks --stack-name CDKToolkit --region "${region}" >/dev/null 2>&1; then
        echo "CDK bootstrap stack found in ${region}"
        return 0
    else
        echo "CDK bootstrap stack not found in ${region}"
        return 1
    fi
}

# Check and perform bootstrap if needed
if ! check_cdk_bootstrap "${ACCOUNT_ID}" "${AWS_REGION}"; then
    echo "Bootstrapping CDK in account ${ACCOUNT_ID} region ${AWS_REGION}..."
    if ! cdk bootstrap "aws://${ACCOUNT_ID}/${AWS_REGION}"; then
        echo "Error: CDK bootstrap failed"
        exit 1
    fi
    echo "Bootstrap completed successfully"
else
    echo "Account already bootstrapped, proceeding with deployment"
fi

mkdir -p .tmp
pushd ../cloud

python -m venv venv
source venv/bin/activate

python -m pip install --upgrade pip
sudo npm install -g aws-cdk

pip install -r requirements.txt
cdk deploy --require-approval never --outputs-file ../.tmp/cdk-outputs.json
popd
cat ../.tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".privateKey' > ../.tmp/private-key.key
cat ../.tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".certificate' > ../.tmp/certificate.pem
cat ../.tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".endpointAddress'  > ../.tmp/endpoint_address.txt
cat ../.tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".vehicleCanInterface'  > ../.tmp/vehicle_can_interface.txt
cat ../.tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".vehicleName'  > ../.tmp/vehicle_name.txt