#!/bin/bash
#
# Standalone Docker Test for setup-dev-env.sh
#
# Creates a fresh Ubuntu container in tmux and runs setup-dev-env
# for interactive testing with proper user permissions.
#

set -euo pipefail

# Configuration
TMUX_SESSION="setup-dev-env-test"
CONTAINER_NAME="setup-dev-env-test-container"
DOCKER_IMAGE="setup-test-env"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NO_CACHE=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

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

    # Kill tmux session if it exists
    if tmux list-sessions 2>/dev/null | grep -q "^$TMUX_SESSION:"; then
        tmux kill-session -t "$TMUX_SESSION"
        log_info "Killed tmux session: $TMUX_SESSION"
    fi

    # Remove container if it exists
    if docker ps -a | grep -q "$CONTAINER_NAME"; then
        docker rm -f "$CONTAINER_NAME" >/dev/null 2>&1
        log_info "Removed container: $CONTAINER_NAME"
    fi

    # Remove Docker image
    if docker images | grep -q "$DOCKER_IMAGE"; then
        docker rmi "$DOCKER_IMAGE" >/dev/null 2>&1
        log_info "Removed Docker image: $DOCKER_IMAGE"
    fi
}

check_prerequisites() {
    if ! command -v tmux >/dev/null 2>&1; then
        log_error "tmux is not installed. Please install tmux first."
        exit 1
    fi

    if ! command -v docker >/dev/null 2>&1; then
        log_error "docker is not installed. Please install docker first."
        exit 1
    fi
}

build_docker_image() {
    if [[ -n "$NO_CACHE" ]]; then
        log_info "Building Docker image with test user environment (--no-cache)..."
    else
        log_info "Building Docker image with test user environment..."
    fi
    if ! docker build $NO_CACHE -t "$DOCKER_IMAGE" -f "$SCRIPT_DIR/Dockerfile.setup-test" "$SCRIPT_DIR/.."; then
        log_error "Failed to build Docker image"
        exit 1
    fi
    log_success "Built Docker image: $DOCKER_IMAGE"
}

setup_test_environment() {
    log_info "Setting up test environment..."

    # Cleanup any existing test environment
    cleanup

    # Build Docker image
    build_docker_image

    # Create new tmux session
    tmux new-session -d -s "$TMUX_SESSION"
    log_success "Created tmux session: $TMUX_SESSION"

    # Start container
    tmux send-keys -t "$TMUX_SESSION" "docker run -it --name $CONTAINER_NAME -w /home/testuser/public-scripts $DOCKER_IMAGE /bin/bash" Enter
    log_success "Started container: $CONTAINER_NAME as testuser"

    # Wait for container to be ready
    sleep 3

    # Start setup-dev-env.sh
    tmux send-keys -t "$TMUX_SESSION" "./setup-dev-env.sh" Enter
    log_success "Started setup-dev-env.sh in container"
}

show_instructions() {
    echo
    echo "==============================================================================="
    echo -e "${GREEN}SETUP-DEV-ENV DOCKER TEST READY${NC}"
    echo "==============================================================================="
    echo
    echo -e "${YELLOW}Automated Test Workflow:${NC}"
    echo "1. Script will now stream the tmux session output automatically"
    echo "2. When an interactive prompt is detected, script will pause"
    echo "3. Connect to the tmux session when prompted to handle inputs"
    echo "4. Return to this terminal and press ENTER when done"
    echo "5. Script will run automated validation"
    echo
    echo -e "${YELLOW}Connection Command (when needed):${NC}"
    echo -e "   ${BLUE}tmux attach-session -t $TMUX_SESSION${NC}"
    echo
    echo -e "${YELLOW}Test Environment:${NC}"
    echo "- Container: $CONTAINER_NAME"
    echo "- Tmux Session: $TMUX_SESSION"
    echo "- Test User: testuser (with sudo)"
    echo "- Public-scripts: Cloned from GitHub"
    echo "- Joel-snips: Will be cloned by setup-dev-env"
    echo
    echo "==============================================================================="
}

stream_tmux_output() {
    log_info "Streaming tmux output (will pause when interactive prompt detected)..."
    echo "==============================================================================="

    local last_output=""
    local prompt_detected=false

    while true; do
        # Check if container is still running
        if ! docker ps | grep -q "$CONTAINER_NAME"; then
            log_warning "Container stopped. Exiting stream..."
            break
        fi

        # Check if tmux session still exists
        if ! tmux list-sessions 2>/dev/null | grep -q "^$TMUX_SESSION:"; then
            log_warning "Tmux session ended. Exiting stream..."
            break
        fi

        # Capture current tmux pane content
        local current_output
        current_output=$(tmux capture-pane -t "$TMUX_SESSION" -p 2>/dev/null || echo "")

        # Only show new content
        if [[ "$current_output" != "$last_output" ]]; then
            # Clear screen and show current output
            clear
            echo -e "${BLUE}=== TMUX SESSION OUTPUT ===${NC}"
            echo "$current_output"
            echo -e "${BLUE}=========================${NC}"

            # Check for interactive prompts
            if echo "$current_output" | grep -qE "(Enter|Input|Password|PAT|token|[Yy]/[Nn]|:\s*$|\?\s*$|\[\s*\]\s*$)"; then
                if ! $prompt_detected; then
                    echo
                    echo -e "${YELLOW}🚨 INTERACTIVE PROMPT DETECTED 🚨${NC}"
                    echo -e "${BLUE}Connect to tmux session: tmux attach-session -t $TMUX_SESSION${NC}"
                    echo -e "${BLUE}Handle the prompts, then return here and press ENTER to continue${NC}"
                    prompt_detected=true
                    break
                fi
            fi

            last_output="$current_output"
        fi

        sleep 1
    done
}

wait_for_user_prompts() {
    echo
    echo -e "${YELLOW}Waiting for you to complete interactive prompts...${NC}"
    echo -e "${BLUE}Press ENTER here when all prompts are handled and ansible is running${NC}"
    read -r
    log_success "Continuing with automated test validation..."
}

validate_test_results() {
    log_info "Validating test results..."

    # Check if joel-snips was cloned
    if tmux send-keys -t "$TMUX_SESSION" "test -d /home/testuser/joel-snips && echo 'VALIDATION: joel-snips found' || echo 'VALIDATION: joel-snips missing'" Enter; then
        sleep 2
    fi

    # Check if ansible completed successfully
    tmux send-keys -t "$TMUX_SESSION" "echo 'VALIDATION: Checking ansible completion...'" Enter
    sleep 1

    # Check if rcfiles were setup
    tmux send-keys -t "$TMUX_SESSION" "test -f /home/testuser/.bashrc && echo 'VALIDATION: bashrc found' || echo 'VALIDATION: bashrc missing'" Enter
    sleep 1

    # Check if git config was set
    tmux send-keys -t "$TMUX_SESSION" "git config --global user.name && echo 'VALIDATION: git config found' || echo 'VALIDATION: git config missing'" Enter
    sleep 2

    log_success "Test validation commands sent. Check tmux session for results."
}

wait_for_completion() {
    # Stream tmux output until interactive prompt detected
    stream_tmux_output

    # Wait for user to signal they're done with prompts
    wait_for_user_prompts

    # Run validation
    validate_test_results

    echo
    echo -e "${YELLOW}Validation complete. Press ENTER to cleanup and exit, or Ctrl-C to leave environment running.${NC}"
    read -r
}

main() {
    echo -e "${BLUE}Setup-dev-env Docker Test${NC}"
    echo

    # Check prerequisites
    check_prerequisites

    # Setup trap for cleanup on exit/interrupt
    trap cleanup EXIT
    trap cleanup SIGTERM SIGINT

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-cache)
                NO_CACHE="--no-cache"
                shift
                ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo
                echo "Standalone Docker test for setup-dev-env.sh"
                echo "Creates fresh Ubuntu container with testuser and runs setup-dev-env"
                echo
                echo "Options:"
                echo "  --no-cache    Force rebuild Docker image without using cache"
                echo "  -h, --help    Show this help"
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                echo "Use --help for usage information"
                exit 1
                ;;
        esac
    done

    # Run test
    setup_test_environment
    show_instructions
    wait_for_completion

    log_success "Test completed"
}

# Run main function
main "$@"