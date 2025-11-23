#!/bin/bash
#
# Interactive Docker Test for setup-dev-env.sh
#
# This script creates a fresh Ubuntu container in tmux and runs setup-dev-env
# inside it for manual testing of all prompts and functionality.
#

set -euo pipefail

# Configuration
TMUX_SESSION="setup-dev-env-test"
CONTAINER_NAME="setup-dev-env-test-container"
UBUNTU_IMAGE="ubuntu:24.04"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PUBLIC_SCRIPTS_DIR="$(dirname "$SCRIPT_DIR")"
HOST_REPO_DIR="$(dirname "$PUBLIC_SCRIPTS_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

cleanup() {
    log_info "Cleaning up test environment..."

    # Kill ALL tmux sessions that match our test pattern
    if tmux list-sessions 2>/dev/null | grep -E "(setup-dev-env-test|$TMUX_SESSION)" >/dev/null 2>&1; then
        tmux list-sessions 2>/dev/null | grep -E "(setup-dev-env-test|$TMUX_SESSION)" | cut -d: -f1 | while read session; do
            tmux kill-session -t "$session" 2>/dev/null || true
            log_info "Killed tmux session: $session"
        done
    else
        log_info "No matching tmux sessions found to clean up"
    fi

    # Remove ALL containers that match our test pattern (running and stopped)
    if docker ps -a --format "{{.Names}}" | grep -E "(setup-dev-env-test|$CONTAINER_NAME)" >/dev/null 2>&1; then
        docker ps -a --format "{{.Names}}" | grep -E "(setup-dev-env-test|$CONTAINER_NAME)" | while read container; do
            docker rm -f "$container" >/dev/null 2>&1 || true
            log_info "Removed container: $container"
        done
    else
        log_info "No matching containers found to clean up"
    fi
}

setup_test_environment() {
    log_info "Setting up fresh test environment..."

    # Cleanup any existing test environment
    cleanup

    # Create new tmux session
    tmux new-session -d -s "$TMUX_SESSION" -c "$PUBLIC_SCRIPTS_DIR"
    log_success "Created tmux session: $TMUX_SESSION"

    # Start container with volume mounts for testing
    tmux send-keys -t "$TMUX_SESSION" "docker run -it --name $CONTAINER_NAME \
        -v \"$HOST_REPO_DIR:/mnt/host-repo:ro\" \
        -w /root \
        $UBUNTU_IMAGE /bin/bash" Enter

    log_success "Started container: $CONTAINER_NAME"

    # Wait for container to be ready
    sleep 3

    # Update package list and install basic dependencies
    tmux send-keys -t "$TMUX_SESSION" "apt-get update && apt-get install -y git curl wget sudo" Enter

    # Wait for package installation
    log_info "Installing basic packages in container..."
    sleep 8

    # Copy the public-scripts to container for testing
    tmux send-keys -t "$TMUX_SESSION" "cp -r /mnt/host-repo/public-scripts /root/" Enter
    sleep 2

    # Copy joel-snips for ansible to have access to it
    tmux send-keys -t "$TMUX_SESSION" "cp -r /mnt/host-repo/joel-snips /root/repo/" Enter
    sleep 2
}

run_setup_test() {
    log_info "Starting setup-dev-env test in container..."

    # Navigate to public-scripts and run setup-dev-env
    tmux send-keys -t "$TMUX_SESSION" "cd /root/public-scripts" Enter
    tmux send-keys -t "$TMUX_SESSION" "./setup-dev-env.sh" Enter

    log_success "setup-dev-env.sh started in tmux session"
}

show_test_instructions() {
    echo
    echo "==============================================================================="
    echo -e "${GREEN}SETUP-DEV-ENV DOCKER TEST STARTED${NC}"
    echo "==============================================================================="
    echo
    echo -e "${YELLOW}Instructions:${NC}"
    echo "1. Open a new terminal window or tab"
    echo "2. Run the following command to attach to the test session:"
    echo -e "   ${BLUE}tmux attach-session -t $TMUX_SESSION${NC}"
    echo
    echo "3. In the tmux session, you'll see setup-dev-env.sh running"
    echo "4. Go through ALL the prompts and test the following:"
    echo "   - Answer questions as appropriate for testing"
    echo "   - Test both Y and N responses where applicable"
    echo "   - Verify email setup prompt (defaults to N)"
    echo "   - Watch for any errors or issues"
    echo "   - Let the ansible playbook complete"
    echo
    echo "5. When testing is complete, return to THIS window"
    echo "6. Press ANY KEY to continue with test cleanup"
    echo
    echo -e "${YELLOW}Test Environment Details:${NC}"
    echo "- Container: $CONTAINER_NAME"
    echo "- Tmux Session: $TMUX_SESSION"
    echo "- Ubuntu Image: $UBUNTU_IMAGE"
    echo "- Host repo mounted at: /mnt/host-repo"
    echo "- Testing in: /root/public-scripts"
    echo
    echo "==============================================================================="
    echo
}

wait_for_user() {
    echo -e "${YELLOW}Press ANY KEY when you've completed testing in the tmux session...${NC}"
    read -n 1 -s
    echo
}

show_test_results() {
    log_info "Gathering test results..."

    # Check if container is still running
    if docker ps | grep -q "$CONTAINER_NAME"; then
        log_success "Container is still running"

        # Show basic test validation
        echo
        echo "==============================================================================="
        echo -e "${GREEN}TEST RESULTS${NC}"
        echo "==============================================================================="

        # Check if ansible completed
        echo -e "${BLUE}Checking for ansible completion...${NC}"
        if tmux capture-pane -t "$TMUX_SESSION" -p | grep -q "PLAY RECAP"; then
            log_success "Ansible playbook appears to have completed"
        else
            log_warning "Ansible playbook may not have completed or failed"
        fi

        # Show last few lines of tmux session
        echo -e "${BLUE}Last output from test session:${NC}"
        tmux capture-pane -t "$TMUX_SESSION" -p | tail -10

    else
        log_error "Container is no longer running - check for errors"
    fi

    echo
    echo "==============================================================================="
    echo
}

main() {
    echo -e "${BLUE}Starting setup-dev-env Docker test...${NC}"
    echo

    # Check prerequisites
    if ! command -v tmux >/dev/null 2>&1; then
        log_error "tmux is not installed. Please install tmux first."
        exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "docker is not installed. Please install docker first."
        exit 1
    fi

    # Setup trap for cleanup on exit
    trap cleanup EXIT

    # Run test sequence
    setup_test_environment
    run_setup_test
    show_test_instructions
    wait_for_user
    show_test_results

    echo -e "${GREEN}Test completed. Check the results above.${NC}"
    echo -e "${YELLOW}Container and tmux session will be cleaned up automatically.${NC}"
}

# Show help if requested
if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
    echo "Usage: $0"
    echo
    echo "Interactive Docker test for setup-dev-env.sh"
    echo
    echo "This script:"
    echo "  1. Creates a fresh Ubuntu container in a tmux session"
    echo "  2. Runs setup-dev-env.sh inside the container"
    echo "  3. Waits for you to manually test all prompts"
    echo "  4. Shows test results and cleans up"
    echo
    echo "Options:"
    echo "  -h, --help    Show this help message"
    exit 0
fi

# Run main function
main "$@"