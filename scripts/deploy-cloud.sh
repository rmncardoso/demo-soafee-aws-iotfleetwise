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
nvm install 22
nvm use 22
nvm alias default 22


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
