#!/bin/bash

# TAS Quickstart Script
# A unified script to manage TAS setup, start, test, and cleanup

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# Global variables
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
TAS_DIR="$SCRIPT_DIR"  # TAS code is in the same directory as the script
VENV_DIR="$TAS_DIR/venv"
PID_FILE="$TAS_DIR/.tas.pid"
ENV_FILE="$TAS_DIR/.env.demo"
LOG_FILE="$TAS_DIR/tas.log"

# Print functions
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "\n${GREEN}==>${NC} ${BLUE}$1${NC}\n"
}

print_header() {
    echo -e "${CYAN}=========================================="
    echo -e "  $1"
    echo -e "==========================================${NC}"
    echo ""
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check prerequisites
check_prerequisites() {
    print_step "Checking prerequisites..."
    
    local missing_deps=()
    
    # Check Python
    if command_exists python3; then
        PYTHON_CMD="python3"
        PYTHON_VERSION=$(python3 --version 2>&1 | awk '{print $2}')
        print_success "Python found: $PYTHON_VERSION"
    elif command_exists python; then
        PYTHON_CMD="python"
        PYTHON_VERSION=$(python --version 2>&1 | awk '{print $2}')
        print_success "Python found: $PYTHON_VERSION"
    else
        print_error "Python not found"
        missing_deps+=("python3")
    fi
    
    # Check pip
    if ! command_exists pip && ! command_exists pip3; then
        print_error "pip not found"
        missing_deps+=("python3-pip")
    else
        print_success "pip found"
    fi
    
    # Check Redis
    if ! command_exists redis-server; then
        print_error "redis-server not found"
        missing_deps+=("redis-server")
    else
        print_success "redis-server found"
    fi
    
    # Check git
    if ! command_exists git; then
        print_error "git not found"
        missing_deps+=("git")
    else
        print_success "git found"
    fi
    
    # Check jq
    if ! command_exists jq; then
        print_error "jq not found"
        missing_deps+=("jq")
    else
        print_success "jq found"
    fi
    
    # Check openssl
    if ! command_exists openssl; then
        print_error "openssl not found"
        missing_deps+=("openssl")
    else
        print_success "openssl found"
    fi
    
    if [ ${#missing_deps[@]} -ne 0 ]; then
        print_error "Missing dependencies: ${missing_deps[*]}"
        echo ""
        print_info "Please install missing dependencies:"
        echo ""
        
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian)
                    echo "  sudo apt update"
                    echo "  sudo apt install -y ${missing_deps[*]}"
                    ;;
                rhel|centos|fedora)
                    echo "  sudo dnf install -y ${missing_deps[*]}"
                    ;;
                *)
                    echo "  Please install: ${missing_deps[*]}"
                    ;;
            esac
        elif [[ "$OSTYPE" == "darwin"* ]]; then
            echo "  brew install ${missing_deps[*]}"
        else
            echo "  Please install: ${missing_deps[*]}"
        fi
        echo ""
        return 1
    fi
    
    print_success "All prerequisites satisfied!"
    return 0
}

# Check and start Redis
check_redis() {
    print_step "Checking Redis status..."
    
    if redis-cli ping >/dev/null 2>&1; then
        print_success "Redis is already running"
        return 0
    else
        print_info "Redis is not running. Starting Redis..."
        
        if redis-server --daemonize yes >/dev/null 2>&1; then
            sleep 2
            if redis-cli ping >/dev/null 2>&1; then
                print_success "Redis started successfully"
                return 0
            fi
        fi
        
        if command_exists systemctl; then
            print_info "Trying to start Redis via systemctl..."
            if sudo systemctl start redis 2>/dev/null; then
                sleep 2
                if redis-cli ping >/dev/null 2>&1; then
                    print_success "Redis started successfully via systemctl"
                    return 0
                fi
            fi
        fi
        
        print_error "Failed to start Redis. Please start it manually:"
        echo "  redis-server --daemonize yes"
        echo "  OR"
        echo "  sudo systemctl start redis"
        return 1
    fi
}

# Setup virtual environment
setup_venv() {
    print_step "Setting up Python virtual environment..."
    
    cd "$TAS_DIR"
    
    if [ -d "venv" ]; then
        print_warning "Virtual environment already exists. Skipping creation."
    else
        print_info "Creating virtual environment..."
        $PYTHON_CMD -m venv venv
        print_success "Virtual environment created"
    fi
    
    print_info "Activating virtual environment..."
    source "$VENV_DIR/bin/activate"
    print_success "Virtual environment activated"
}

# Install SNP tools
install_snp_tools() {
    print_step "Installing SNP verification tools..."
    
    cd "$TAS_DIR"
    
    if [ -d "snp_pytools" ]; then
        print_warning "snp_pytools directory already exists. Skipping clone."
    else
        print_info "Cloning snp_pytools repository..."
        git clone https://github.com/TEE-Attestation/snp_pytools.git
        print_success "snp_pytools cloned"
    fi
    
    print_info "Installing snp_pytools..."
    cd snp_pytools
    pip install --quiet . || pip install .
    cd "$TAS_DIR"
    print_success "snp_pytools installed"
}

# Install TAS dependencies
install_dependencies() {
    print_step "Installing TAS dependencies..."
    
    cd "$TAS_DIR"
    
    if [ ! -f "requirements.txt" ]; then
        print_error "requirements.txt not found in $TAS_DIR"
        return 1
    fi
    
    print_info "Installing from requirements.txt..."
    pip install --quiet -r requirements.txt || pip install -r requirements.txt
    print_success "TAS dependencies installed"
}

# Setup environment variables
setup_environment() {
    print_step "Setting up environment variables..."
    
    cd "$TAS_DIR"
    
    export TAS_API_KEY="$(openssl rand -hex 32)"
    print_success "Generated TAS_API_KEY"
    
    export TAS_KBM_PLUGIN="tas_kbm_mock"
    print_success "Set TAS_KBM_PLUGIN=tas_kbm_mock"
    
    export TAS_KBM_CONFIG_FILE="config/mock_secrets.yaml"
    print_success "Set TAS_KBM_CONFIG_FILE=config/mock_secrets.yaml"
    
    if [ ! -f "config/mock_secrets.yaml" ]; then
        print_info "Creating mock secrets configuration..."
        mkdir -p config
        cat > config/mock_secrets.yaml << EOF
secrets:
  test-key-1: "test-secret-value"
  demo-key: "demo-secret-value"
  example-key: "example-secret-value"
EOF
        print_success "Mock secrets configuration created"
    else
        print_warning "config/mock_secrets.yaml already exists. Skipping creation."
    fi
    
    cat > "$ENV_FILE" << EOF
# TAS Demo Environment Variables
# Source this file to restore the environment: source .env.demo

export TAS_API_KEY="$TAS_API_KEY"
export TAS_KBM_PLUGIN="$TAS_KBM_PLUGIN"
export TAS_KBM_CONFIG_FILE="$TAS_KBM_CONFIG_FILE"
EOF
    print_success "Environment variables saved to $ENV_FILE"
}

# Setup and sign policy
setup_policy() {
    print_step "Creating and signing demo policy..."
    
    cd "$TAS_DIR/certs/policy"
    
    if [ ! -f "demo_signer.py" ]; then
        print_error "demo_signer.py not found in certs/policy/"
        return 1
    fi
    
    if [ ! -f "example_policy.json" ]; then
        print_error "example_policy.json not found in certs/policy/"
        return 1
    fi
    
    print_info "Signing example policy..."
    $PYTHON_CMD demo_signer.py ./example_policy.json
    
    print_info "Combining policy and signature..."
    jq -s '.[0] * .[1]' example_policy.json example_policy.json.sig > example_policy_signed.json
    
    cd "$TAS_DIR"
    print_success "Policy signed and saved to certs/policy/example_policy_signed.json"
}

# Install function (complete setup)
do_install() {
 
    # Verify we're in the right directory by checking for key files
    if [ ! -f "$TAS_DIR/app.py" ]; then
        print_error "app.py not found in $TAS_DIR"
        print_info "Please run this script from the TAS root directory"
        return 1
    fi
    
    if [ ! -f "$TAS_DIR/requirements.txt" ]; then
        print_error "requirements.txt not found in $TAS_DIR"
        print_info "Please run this script from the TAS root directory"
        return 1
    fi
    
    check_prerequisites || return 1
    check_redis || return 1
    setup_venv || return 1
    install_snp_tools || return 1
    install_dependencies || return 1
    setup_environment || return 1
    setup_policy || return 1
    
    echo ""
    print_header "Installation Complete!"
    print_success "TAS is ready to start"
    echo ""
    print_info "Next steps:"
    echo "  • Start TAS:  ./quickstart.sh start"
    echo "  • Run tests:  ./quickstart.sh test"
    echo "  • Full demo:  ./quickstart.sh demo"
    echo ""
}

# Start TAS server
do_start() {
    
    # Check if virtual environment exists
    if [ ! -d "$VENV_DIR" ]; then
        print_error "Virtual environment not found. Please run: ./quickstart.sh install"
        return 1
    fi
    
    # Check if .env.demo exists
    if [ ! -f "$ENV_FILE" ]; then
        print_error ".env.demo not found. Please run: ./quickstart.sh install"
        return 1
    fi
    
    # Check if TAS is already running
    if [ -f "$PID_FILE" ]; then
        OLD_PID=$(cat "$PID_FILE")
        if ps -p $OLD_PID > /dev/null 2>&1; then
            print_warning "TAS is already running (PID: $OLD_PID)"
            print_info "To stop it, run: ./quickstart.sh exit"
            return 1
        else
            print_warning "Stale PID file found. Removing..."
            rm "$PID_FILE"
        fi
    fi
    
    # Activate virtual environment
    source "$VENV_DIR/bin/activate"
    
    # Load environment variables
    source "$ENV_FILE"
    
    # Check Redis
    print_info "Checking Redis..."
    if ! redis-cli ping >/dev/null 2>&1; then
        print_info "Redis is not running. Starting Redis..."
        redis-server --daemonize yes
        sleep 2
        if ! redis-cli ping >/dev/null 2>&1; then
            print_error "Failed to start Redis"
            return 1
        fi
    fi
    print_success "Redis is running"
    
    # Start TAS in background
    print_info "Starting TAS server in background..."
    cd "$TAS_DIR"
    nohup python app.py > "$LOG_FILE" 2>&1 &
    TAS_PID=$!
    
    # Save PID
    echo $TAS_PID > "$PID_FILE"
    
    # Wait a moment and check if it's still running
    sleep 3
    if ps -p $TAS_PID > /dev/null 2>&1; then
        print_success "TAS server started successfully (PID: $TAS_PID)"
        echo ""
        print_info "Server details:"
        echo "  • URL: http://localhost:5000"
        echo "  • PID: $TAS_PID"
        echo "  • Logs: $LOG_FILE"
        echo "  • API Key: $TAS_API_KEY"
        echo ""
        print_info "Useful commands:"
        echo "  • View logs:  tail -f $LOG_FILE"
        echo "  • Run tests:  ./quickstart.sh test"
        echo "  • Stop TAS:   ./quickstart.sh exit"
        echo ""
        return 0
    else
        print_error "TAS server failed to start. Check $LOG_FILE for details"
        rm "$PID_FILE"
        return 1
    fi
}

# Run tests
do_test() {
 
    # Load environment variables
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
    else
        print_error ".env.demo not found. Please run: ./quickstart.sh install"
        return 1
    fi
    
    TAS_URL="${TAS_URL:-http://localhost:5000}"
    
    # Wait for TAS to be ready
    print_info "Waiting for TAS to be ready..."
    MAX_RETRIES=10
    RETRY_COUNT=0
    while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
        if curl -s -f -H "X-API-KEY: $TAS_API_KEY" "$TAS_URL/version" >/dev/null 2>&1; then
            break
        fi
        RETRY_COUNT=$((RETRY_COUNT + 1))
        if [ $RETRY_COUNT -eq $MAX_RETRIES ]; then
            print_error "TAS server is not responding after $MAX_RETRIES attempts"
            print_info "Check if TAS is running: cat $PID_FILE"
            print_info "Check logs: tail -f $LOG_FILE"
            return 1
        fi
        sleep 1
    done
    
    echo ""
    print_info "Running tests against $TAS_URL"
    echo ""
    
    TESTS_PASSED=0
    TESTS_FAILED=0
    
    # Test 1: Version endpoint
    print_info "Test 1: GET /version"
    RESPONSE=$(curl -s -H "X-API-KEY: $TAS_API_KEY" "$TAS_URL/version")
    if echo "$RESPONSE" | jq -e '.version' >/dev/null 2>&1; then
        VERSION=$(echo "$RESPONSE" | jq -r '.version')
        print_success "✓ Version endpoint working. TAS version: $VERSION"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "✗ Version endpoint failed"
        echo "Response: $RESPONSE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    echo ""
    
    # Test 2: Get nonce
    print_info "Test 2: GET /kb/v0/get_nonce"
    RESPONSE=$(curl -s -H "X-API-KEY: $TAS_API_KEY" "$TAS_URL/kb/v0/get_nonce")
    if echo "$RESPONSE" | jq -e '.nonce' >/dev/null 2>&1; then
        NONCE=$(echo "$RESPONSE" | jq -r '.nonce')
        print_success "✓ Nonce endpoint working. Nonce: ${NONCE:0:32}..."
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "✗ Nonce endpoint failed"
        echo "Response: $RESPONSE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    echo ""
    
    # Test 3: List policies
    print_info "Test 3: GET /policy/v0/list"
    RESPONSE=$(curl -s -H "X-API-KEY: $TAS_API_KEY" "$TAS_URL/policy/v0/list")
    if echo "$RESPONSE" | jq -e '.' >/dev/null 2>&1; then
        POLICY_COUNT=$(echo "$RESPONSE" | jq '. | length')
        print_success "✓ Policy list endpoint working. Policies found: $POLICY_COUNT"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "✗ Policy list endpoint failed"
        echo "Response: $RESPONSE"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    echo ""
    
    # Test 4: Invalid API key
    print_info "Test 4: Testing authentication (invalid API key)"
    RESPONSE=$(curl -s -w "\n%{http_code}" -H "X-API-KEY: invalid-key" "$TAS_URL/version")
    HTTP_CODE=$(echo "$RESPONSE" | tail -n1)
    if [ "$HTTP_CODE" = "401" ] || [ "$HTTP_CODE" = "403" ]; then
        print_success "✓ Authentication working correctly (rejected invalid key)"
        TESTS_PASSED=$((TESTS_PASSED + 1))
    else
        print_error "✗ Authentication test failed (expected 401/403, got $HTTP_CODE)"
        TESTS_FAILED=$((TESTS_FAILED + 1))
    fi
    
    echo ""
    echo "=========================================="
    echo "  Test Results"
    echo "=========================================="
    echo ""
    print_success "Tests passed: $TESTS_PASSED"
    if [ $TESTS_FAILED -gt 0 ]; then
        print_error "Tests failed: $TESTS_FAILED"
    else
        print_info "Tests failed: $TESTS_FAILED"
    fi
    echo ""
    
    if [ $TESTS_FAILED -eq 0 ]; then
        print_success "All tests passed! ✓"
        echo ""
        print_info "TAS is ready to use!"
    else
        print_warning "Some tests failed. Check the output above for details."
        echo ""
    fi
    
    print_warning "Note: The /kb/v0/get_secret endpoint requires a valid TEE attestation report"
    print_info "To test that endpoint, you'll need to generate an attestation report from a TEE-enabled platform"
    echo ""
    
    return $TESTS_FAILED
}

# Stop TAS server
do_exit() {
    print_header "Shutting Down TAS"
    
    # Check if PID file exists
    if [ ! -f "$PID_FILE" ]; then
        print_warning "No PID file found. TAS may not be running."
        print_info "Checking for any running TAS processes..."
        
        # Try to find TAS process by name
        TAS_PIDS=$(pgrep -f "python.*app.py" 2>/dev/null || true)
        
        if [ -n "$TAS_PIDS" ]; then
            print_warning "Found TAS process(es) running: $TAS_PIDS"
            read -p "Do you want to stop these processes? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                for pid in $TAS_PIDS; do
                    print_info "Stopping process $pid..."
                    kill $pid 2>/dev/null || true
                done
                sleep 2
                print_success "Processes stopped"
            fi
        else
            print_info "No TAS processes found running."
        fi
        
        return 0
    fi
    
    # Read PID from file
    TAS_PID=$(cat "$PID_FILE")
    
    # Check if process is actually running
    if ! ps -p $TAS_PID > /dev/null 2>&1; then
        print_warning "TAS server is not running (stale PID file found)"
        print_info "Cleaning up PID file..."
        rm "$PID_FILE"
        return 0
    fi
    
    # Process is running, proceed with shutdown
    print_info "Found TAS server running (PID: $TAS_PID)"
    print_info "Sending shutdown signal..."
    
    # Try graceful shutdown first
    kill $TAS_PID 2>/dev/null
    
    # Wait up to 5 seconds for graceful shutdown
    WAIT_COUNT=0
    MAX_WAIT=5
    
    while [ $WAIT_COUNT -lt $MAX_WAIT ]; do
        if ! ps -p $TAS_PID > /dev/null 2>&1; then
            print_success "TAS server stopped gracefully"
            rm "$PID_FILE"
            
            # Optional: Ask if user wants to stop Redis too
            echo ""
            read -p "Do you want to stop Redis as well? (y/n) " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                if redis-cli ping >/dev/null 2>&1; then
                    print_info "Stopping Redis..."
                    redis-cli shutdown 2>/dev/null || true
                    sleep 1
                    if ! redis-cli ping >/dev/null 2>&1; then
                        print_success "Redis stopped"
                    else
                        print_warning "Redis may still be running (might be managed by system)"
                    fi
                else
                    print_info "Redis is not running"
                fi
            fi
            
            echo ""
            print_header "TAS Shutdown Complete"
            print_info "All services stopped successfully"
            echo ""
            
            return 0
        fi
        
        sleep 1
        WAIT_COUNT=$((WAIT_COUNT + 1))
    done
    
    # If we get here, graceful shutdown failed
    print_warning "Graceful shutdown timed out. Forcing shutdown..."
    kill -9 $TAS_PID 2>/dev/null
    
    sleep 1
    
    # Verify it's stopped
    if ! ps -p $TAS_PID > /dev/null 2>&1; then
        print_success "TAS server stopped (forced)"
        rm "$PID_FILE"
        
        echo ""
        print_header "TAS Shutdown Complete"
        print_warning "Server was forcefully terminated"
        echo ""
    else
        print_error "Failed to stop TAS server (PID: $TAS_PID)"
        print_info "You may need to manually kill the process:"
        echo "  kill -9 $TAS_PID"
        return 1
    fi
}

# Uninstall TAS
do_uninstall() {
    print_header "Uninstalling TAS"
    
    # Stop TAS if running
    if [ -f "$PID_FILE" ]; then
        print_info "Stopping TAS server first..."
        do_exit
    fi
    
    echo ""
    print_warning "This will remove:"
    echo "  • Virtual environment ($VENV_DIR)"
    echo "  • SNP tools ($TAS_DIR/snp_pytools)"
    echo "  • Environment file ($ENV_FILE)"
    echo "  • Log file ($LOG_FILE)"
    echo "  • PID file ($PID_FILE)"
    echo ""
    read -p "Are you sure you want to continue? (y/n) " -n 1 -r
    echo
    
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Uninstall cancelled"
        return 0
    fi
    
    print_info "Removing virtual environment..."
    if [ -d "$VENV_DIR" ]; then
        rm -rf "$VENV_DIR"
        print_success "Virtual environment removed"
    fi
    
    print_info "Removing SNP tools..."
    if [ -d "$TAS_DIR/snp_pytools" ]; then
        rm -rf "$TAS_DIR/snp_pytools"
        print_success "SNP tools removed"
    fi
    
    print_info "Removing environment file..."
    if [ -f "$ENV_FILE" ]; then
        rm -f "$ENV_FILE"
        print_success "Environment file removed"
    fi
    
    print_info "Removing log file..."
    if [ -f "$LOG_FILE" ]; then
        rm -f "$LOG_FILE"
        print_success "Log file removed"
    fi
    
    print_info "Removing PID file..."
    if [ -f "$PID_FILE" ]; then
        rm -f "$PID_FILE"
        print_success "PID file removed"
    fi
    
    echo ""
    print_header "Uninstall Complete"
    print_info "TAS has been uninstalled. The core TAS code remains intact."
    print_info "To reinstall, run: ./quickstart.sh install"
    echo ""
}

# Demo function (install + start + test)
do_demo() {
    print_header "TAS Demo"
    
    # Step 1: Install
    print_header "Step 1: Installing TAS"
    do_install
    if [ $? -ne 0 ]; then
        print_error "Installation failed. Aborting demo."
        return 1
    fi
    
    echo ""
    sleep 2
    
    # Step 2: Start
    print_header "Step 2: Starting TAS Server"
    do_start
    if [ $? -ne 0 ]; then
        print_error "Failed to start TAS. Aborting demo."
        return 1
    fi
    
    echo ""
    sleep 2
    
    # Step 3: Test
    print_header "Step 3: Running Tests"
    do_test
    TEST_EXIT_CODE=$?
    
    echo ""
    
    # Final summary
    print_header "Demo Complete!"
    
    if [ $TEST_EXIT_CODE -eq 0 ]; then
        print_success "All tests passed! TAS is running successfully."
    else
        print_warning "Some tests failed, but TAS is running."
    fi
    
    echo ""
    print_info "TAS Server Status:"
    if [ -f "$PID_FILE" ]; then
        TAS_PID=$(cat "$PID_FILE")
        echo "  • Running in background (PID: $TAS_PID)"
        echo "  • URL: http://localhost:5000"
        echo "  • Logs: $LOG_FILE"
        
        # Load and display API key
        if [ -f "$ENV_FILE" ]; then
            source "$ENV_FILE"
            echo "  • API Key: $TAS_API_KEY"
        fi
    fi
    
    echo ""
    print_info "Useful commands:"
    echo "  • View logs:        tail -f $LOG_FILE"
    echo "  • Stop server:      ./quickstart.sh exit"
    echo "  • Run tests again:  ./quickstart.sh test"
    echo "  • Uninstall:        ./quickstart.sh uninstall"
    echo ""
    print_info "Example API calls:"
    if [ -f "$ENV_FILE" ]; then
        source "$ENV_FILE"
        echo "  • Get version:      curl -H \"X-API-KEY: $TAS_API_KEY\" http://localhost:5000/version"
        echo "  • Get nonce:        curl -H \"X-API-KEY: $TAS_API_KEY\" http://localhost:5000/kb/v0/get_nonce"
    fi
    echo ""
}

# Show usage
show_usage() {
    echo -e "${CYAN}TAS Quickstart Script${NC}"
    echo ""
    echo -e "${BLUE}Usage:${NC}"
    echo "  ./quickstart.sh [COMMAND]"
    echo ""
    echo -e "${BLUE}Commands:${NC}"
    echo -e "  ${GREEN}demo${NC}        Run complete demo (install + start + test)"
    echo -e "  ${GREEN}install${NC}     Install and setup TAS environment"
    echo -e "  ${GREEN}start${NC}       Start TAS server in background"
    echo -e "  ${GREEN}test${NC}        Run tests against running TAS server"
    echo -e "  ${GREEN}exit${NC}        Stop TAS server"
    echo -e "  ${GREEN}uninstall${NC}   Remove TAS installation (keeps core code)"
    echo -e "  ${GREEN}help${NC}        Show this help message"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  # Quick start (recommended for first time)"
    echo "  ./quickstart.sh demo"
    echo ""
    echo "  # Manual workflow"
    echo "  ./quickstart.sh install"
    echo "  ./quickstart.sh start"
    echo "  ./quickstart.sh test"
    echo "  ./quickstart.sh exit"
    echo ""
    echo "  # Clean up"
    echo "  ./quickstart.sh uninstall"
    echo ""
    echo -e "${BLUE}More Information:${NC}"
    echo "  • Logs: $LOG_FILE"
    echo "  • Environment: $ENV_FILE"
    echo "  • PID file: $PID_FILE"
    echo ""
}

# Main script logic
main() {
    # Check if we're in the right directory by looking for app.py
    if [ ! -f "$TAS_DIR/app.py" ]; then
        print_error "app.py not found in $TAS_DIR"
        print_info "Please run this script from the TAS root directory (where app.py is located)"
        print_info "Current directory: $TAS_DIR"
        exit 1
    fi
    
    # Parse command
    COMMAND="${1:-help}"
    
    case "$COMMAND" in
        demo)
            do_demo
            ;;
        install)
            do_install
            ;;
        start)
            do_start
            ;;
        test)
            do_test
            ;;
        exit|stop)
            do_exit
            ;;
        uninstall)
            do_uninstall
            ;;
        help|--help|-h)
            show_usage
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            echo ""
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
