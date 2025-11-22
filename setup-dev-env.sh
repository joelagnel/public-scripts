#!/bin/bash
# Bootstrap script for setting up development environment
# Installs ansible and clones joel-snips repository

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running on Ubuntu/Debian
if ! command -v apt &> /dev/null; then
    log_error "This script requires apt package manager (Ubuntu/Debian)"
    exit 1
fi

# Check if running as root
if [ "$EUID" -eq 0 ]; then
    log_error "Please run this script as a regular user with sudo privileges, not as root"
    exit 1
fi

# Check if user has sudo privileges
if ! sudo -n true 2>/dev/null; then
    log_info "This script requires sudo privileges. You may be prompted for your password."
fi

log_info "Updating package manager..."
sudo apt update

log_info "Installing ansible..."
if ! command -v ansible &> /dev/null; then
    sudo apt install -y ansible
    log_info "Ansible installed successfully"
else
    log_info "Ansible is already installed"
fi

# Create ~/repo directory if it doesn't exist
REPO_DIR="$HOME/repo"
if [ ! -d "$REPO_DIR" ]; then
    log_info "Creating $REPO_DIR directory..."
    mkdir -p "$REPO_DIR"
fi

# Check if joel-snips already exists
SNIPS_DIR="$REPO_DIR/joel-snips"
if [ -d "$SNIPS_DIR" ]; then
    log_warn "joel-snips directory already exists at $SNIPS_DIR"
    read -p "Do you want to rename it to a backup? (y/N): " -r
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        BACKUP_NAME="joel-snips.bak.$(date +%Y%m%d_%H%M%S)"
        mv "$SNIPS_DIR" "$REPO_DIR/$BACKUP_NAME"
        log_info "Moved existing directory to $REPO_DIR/$BACKUP_NAME"
    else
        log_error "Cannot proceed with existing joel-snips directory. Exiting."
        exit 1
    fi
fi

# Prompt for GitHub PAT
log_info "GitHub Personal Access Token required to clone joel-snips repository"
echo "You can generate one at: https://github.com/settings/personal-access-tokens"
echo -n "Enter your GitHub PAT: "
read -s PAT
echo

if [ -z "$PAT" ]; then
    log_error "PAT cannot be empty"
    exit 1
fi

# Clone joel-snips repository
log_info "Cloning joel-snips repository..."
cd "$REPO_DIR"
if git clone "https://$PAT@github.com/joelagnel/joel-snips.git"; then
    log_info "joel-snips cloned successfully to $SNIPS_DIR"
else
    log_error "Failed to clone joel-snips repository. Check your PAT and try again."
    exit 1
fi

# Clear PAT from memory
unset PAT

# Check if test playbook exists and run it
TEST_PLAYBOOK="$SNIPS_DIR/test-playbook.yml"
if [ -f "$TEST_PLAYBOOK" ]; then
    log_info "Running ansible test playbook..."
    cd "$SNIPS_DIR"
    if ansible-playbook test-playbook.yml; then
        log_info "Ansible test completed successfully!"
    else
        log_warn "Ansible test failed, but setup is complete"
    fi
else
    log_warn "No test playbook found at $TEST_PLAYBOOK"
    log_info "You can create one later to test ansible functionality"
fi

log_info "Development environment setup completed!"
log_info "joel-snips is available at: $SNIPS_DIR"
log_info "You can now run: cd $SNIPS_DIR && ./rcfiles/setuprc"