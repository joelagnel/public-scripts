#!/bin/bash
# Bootstrap script for setting up development environment
# Installs ansible, clones joel-snips repository, and runs ansible setup playbook
#
# Usage: ./setup-dev-env.sh [--help]
#
# Prerequisites:
# - Ubuntu/Debian system with sudo access
# - GitHub Personal Access Token with Contents: Read/Write permission for joel-snips repository
#
# Generate PAT at: https://github.com/settings/personal-access-tokens
# Required permissions: Contents: Read/Write (for repository access)

set -euo pipefail

# Cleanup function to remove sensitive files on exit
cleanup() {
    if [ -f "$HOME/.vault_pass" ]; then
        rm -f "$HOME/.vault_pass"
        log_info "Cleaned up vault password file"
    fi
}
trap cleanup EXIT

show_help() {
    cat << EOF
setup-dev-env.sh - Bootstrap development environment

DESCRIPTION:
    Sets up development environment by installing ansible, cloning the joel-snips repository,
    and running the ansible playbook to configure dotfiles and tools.

USAGE:
    ./setup-dev-env.sh [--help]

PREREQUISITES:
    - Ubuntu/Debian system with sudo access
    - Internet connection
    - GitHub Personal Access Token (PAT) with proper permissions

PAT REQUIREMENTS:
    You need a GitHub Personal Access Token with the following permissions:
    - Contents: Read/Write (to clone and push to the joel-snips repository)

    Generate a new PAT at: https://github.com/settings/personal-access-tokens

    For fine-grained tokens:
    1. Select "Fine-grained personal access tokens"
    2. Choose resource access for 'joelagnel/joel-snips' repository
    3. Grant "Contents" permission with "Read and write" access

    SECURITY NOTE: Delete the PAT immediately after running this script.

WHAT IT DOES:
    - Updates package manager (apt update)
    - Installs ansible if not present
    - Creates ~/repo/ directory
    - Backs up existing joel-snips directory if present
    - Clones joel-snips repository using your PAT
    - Runs ansible setup playbook to configure development environment (if available)

OPTIONS:
    --help    Show this help message

AUTHOR:
    Joel Fernandes <joel@joelfernandes.org>
EOF
}

# Check for help flag
if [[ "${1:-}" == "--help" ]]; then
    show_help
    exit 0
fi

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

echo
echo "==============================================="
echo "           CREDENTIAL COLLECTION"
echo "==============================================="
echo
log_info "All credentials will be collected upfront so you can relax while the setup runs!"
echo

# Prompt for GitHub PAT early
log_info "GitHub Personal Access Token required to clone joel-snips repository"
echo "Generate one at: https://github.com/settings/personal-access-tokens"
echo "Required permissions: Contents: Read/Write (for repository access)"
echo "For fine-grained tokens: Select 'joelagnel/joel-snips' repository access"
echo "IMPORTANT: Delete the PAT after this script completes!"
echo -n "Enter your GitHub PAT: "
read -s PAT
echo

if [ -z "$PAT" ]; then
    log_error "PAT cannot be empty"
    exit 1
fi

echo
# Prompt for Ansible Vault password early
log_info "Ansible Vault password required for decrypting SSH/GPG keys"
echo "This will be used later during the ansible setup to decrypt your key archive."
echo -n "Enter Ansible Vault password: "
read -s VAULT_PASSWORD
echo

if [ -z "$VAULT_PASSWORD" ]; then
    log_error "Vault password cannot be empty"
    exit 1
fi

# Save vault password to temporary file for ansible playbook
VAULT_PASS_FILE="$HOME/.vault_pass"
echo "$VAULT_PASSWORD" > "$VAULT_PASS_FILE"
chmod 600 "$VAULT_PASS_FILE"

# Clear vault password from memory
unset VAULT_PASSWORD

echo
echo "==============================================="
echo "         AUTOMATED SETUP BEGINNING"
echo "==============================================="
echo
log_info "All credentials collected! You can now relax while the setup completes."
log_info "Vault password saved for ansible playbook (will be deleted after setup)"
echo

log_info "Updating package manager..."
sudo apt update

log_info "Installing ansible (with full collections and Jinja2 compatibility)..."

# Check if we have a compatible ansible version
ANSIBLE_NEEDS_INSTALL=false
if ! command -v ansible &> /dev/null; then
    ANSIBLE_NEEDS_INSTALL=true
    log_info "Ansible not found, will install via pip"
else
    # Check if it's the pip version by checking location
    ANSIBLE_PATH=$(which ansible)
    if [[ "$ANSIBLE_PATH" != *"$HOME/.local/bin/ansible"* ]]; then
        log_info "Found system ansible, switching to pip version for better compatibility"
        ANSIBLE_NEEDS_INSTALL=true
    else
        log_info "Ansible pip version already installed at $ANSIBLE_PATH"
    fi
fi

if [ "$ANSIBLE_NEEDS_INSTALL" = true ]; then
    sudo apt update
    # Remove any conflicting system packages
    sudo apt remove -y ansible ansible-core 2>/dev/null || true
    # Install python3-pip if not present
    sudo apt install -y python3-pip
    # Install ansible via pip for latest version with all collections
    pip3 install --user ansible
    # Add ~/.local/bin to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc 2>/dev/null || true
    fi
    # Update PATH for current session
    export PATH="$HOME/.local/bin:$PATH"
    log_info "Ansible installed successfully via pip"
fi

# Ensure essential collections are installed
log_info "Installing/updating ansible collections..."
if command -v ansible-galaxy &> /dev/null; then
    ansible-galaxy collection install community.general --upgrade 2>/dev/null || \
        log_warn "Could not install community.general collection (may already be present)"
    ansible-galaxy collection install ansible.posix --upgrade 2>/dev/null || \
        log_warn "Could not install ansible.posix collection (may already be present)"
else
    log_warn "ansible-galaxy not available, collections may need manual installation"
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

# Clone joel-snips repository
log_info "Cloning joel-snips repository..."
cd "$REPO_DIR"
if git clone "https://$PAT@github.com/joelagnel/joel-snips.git"; then
    log_info "joel-snips cloned successfully to $SNIPS_DIR"
else
    log_error "Failed to clone joel-snips repository."
    log_error "Ensure your PAT has 'Contents: Read/Write' permission for the joel-snips repository."
    log_error "For fine-grained tokens, verify 'joelagnel/joel-snips' repository access is granted."
    exit 1
fi

# Clear PAT from memory
unset PAT

# Check if ansible playbook exists and run it
ANSIBLE_DIR="$SNIPS_DIR/rcfiles/ansible"
MAIN_PLAYBOOK="$ANSIBLE_DIR/main.yml"
if [ -d "$ANSIBLE_DIR" ] && [ -f "$MAIN_PLAYBOOK" ]; then
    log_info "Running ansible setup playbook..."
    cd "$ANSIBLE_DIR"
    if ansible-playbook main.yml; then
        log_info "Ansible setup completed successfully!"
    else
        log_warn "Ansible setup failed, but repository setup is complete"
        log_info "You can run the playbook manually later: cd $ANSIBLE_DIR && ansible-playbook main.yml"
    fi
else
    log_warn "No ansible playbook found at $ANSIBLE_DIR/main.yml"
    log_info "You can run the legacy setup instead: cd $SNIPS_DIR && ./rcfiles/setuprc"
fi

log_info "Development environment setup completed!"
log_info "joel-snips is available at: $SNIPS_DIR"
if [ -d "$ANSIBLE_DIR" ] && [ -f "$MAIN_PLAYBOOK" ]; then
    log_info "To run setup again: cd $ANSIBLE_DIR && ansible-playbook main.yml"
else
    log_info "To run legacy setup: cd $SNIPS_DIR && ./rcfiles/setuprc"
fi
echo
log_warn "SECURITY REMINDER: Delete your GitHub PAT now that the script has completed."
log_warn "Go to: https://github.com/settings/personal-access-tokens and revoke the token."
echo
log_info "Vault password file has been automatically cleaned up."
