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
cdk bootstrap aws://${ACCOUNT_ID}/${AWS_REGION}

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