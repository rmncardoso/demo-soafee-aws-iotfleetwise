#!/bin/bash
set -e

sudo yum -y update
sudo yum -y install jq gettext bash-completion

# Set up AWS environment
ACCOUNT_ID=$(aws sts get-caller-identity --output text --query Account)
AWS_REGION=$(curl -s 169.254.169.254/latest/dynamic/instance-identity/document | jq -r '.region')

if [ -z "${AWS_REGION}" ]; then
    echo "Error: Could not determine AWS_REGION"
    #Fallback to default region if metadata service fails
    AWS_REGION=$(aws configure get region)
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
cat .tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".privateKey' > .tmp/private-key.key
cat .tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".certificate' > .tmp/certificate.pem
cat .tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".endpointAddress'  > .tmp/endpoint_address.txt
cat .tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".vehicleCanInterface'  > .tmp/vehicle_can_interface.txt
cat .tmp/cdk-outputs.json | jq -r '."demo-soafee-aws-iotfleetwise".vehicleName'  > .tmp/vehicle_name.txt