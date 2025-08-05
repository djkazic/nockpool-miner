#!/bin/bash

# Namespace Execution Wrapper
# Runs arbitrary software in the isolated network namespace

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_cmd() {
    echo -e "${BLUE}[CMD]${NC} $1"
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

load_config() {
    if [[ ! -f /tmp/netns-config ]]; then
        log_error "Configuration not found. Run ./setup-isolation.sh first"
        exit 1
    fi
    source /tmp/netns-config
}

check_namespace_exists() {
    if ! ip netns list | grep -q "^$NAMESPACE"; then
        log_error "Namespace $NAMESPACE does not exist. Run ./setup-isolation.sh first"
        exit 1
    fi
}

show_network_status() {
    log_info "Network status in namespace:"
    echo "  Interfaces:"
    ip netns exec "$NAMESPACE" ip addr show | grep -E '^[0-9]+:|inet ' | sed 's/^/    /'
    echo "  Routes:"
    ip netns exec "$NAMESPACE" ip route show | sed 's/^/    /'
    echo "  Connectivity test:"
    if ip netns exec "$NAMESPACE" timeout 3 ping -c 1 8.8.8.8 &>/dev/null; then
        echo -e "    ${GREEN}✓ Internet reachable${NC}"
    else
        echo -e "    ${RED}✗ Internet not reachable${NC}"
    fi
}

run_interactive_shell() {
    log_info "Starting interactive shell in namespace $NAMESPACE"
    log_info "Use 'exit' to return to the host system"
    
    show_network_status
    echo
    
    # Set up a nice prompt that shows we're in the namespace
    export PS1="\[\033[1;32m\][$NAMESPACE]\[\033[0m\] \u@\h:\w\$ "
    
    ip netns exec "$NAMESPACE" /bin/bash --rcfile <(echo "PS1='\\[\\033[1;32m\\][$NAMESPACE]\\[\\033[0m\\] \\u@\\h:\\w\\$ '")
}

run_command() {
    local cmd="$1"
    
    log_info "Running command in namespace $NAMESPACE:"
    log_cmd "$cmd"
    echo
    
    # Execute the command in the namespace
    ip netns exec "$NAMESPACE" bash -c "$cmd"
    local exit_code=$?
    
    echo
    if [[ $exit_code -eq 0 ]]; then
        log_info "Command completed successfully (exit code: $exit_code)"
    else
        log_warn "Command completed with exit code: $exit_code"
    fi
    
    return $exit_code
}

run_with_monitoring() {
    local cmd="$1"
    
    log_info "Running command with network monitoring in namespace $NAMESPACE:"
    log_cmd "$cmd"
    echo
    
    # Start network monitoring in background
    (
        while true; do
            if ip netns exec "$NAMESPACE" timeout 1 ping -c 1 8.8.8.8 &>/dev/null; then
                echo -e "${GREEN}[$(date '+%H:%M:%S')] Network: Connected${NC}"
            else
                echo -e "${RED}[$(date '+%H:%M:%S')] Network: Disconnected${NC}"
            fi
            sleep 5
        done
    ) &
    local monitor_pid=$!
    
    # Run the actual command
    ip netns exec "$NAMESPACE" bash -c "$cmd"
    local exit_code=$?
    
    # Stop monitoring
    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true
    
    echo
    if [[ $exit_code -eq 0 ]]; then
        log_info "Command completed successfully (exit code: $exit_code)"
    else
        log_warn "Command completed with exit code: $exit_code"
    fi
    
    return $exit_code
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS] [COMMAND]

Run software in the isolated network namespace.

OPTIONS:
  -h, --help       Show this help message
  -s, --status     Show network status in namespace
  -m, --monitor    Run with network connectivity monitoring
  -i, --interactive  Start interactive shell (default if no command given)

COMMAND:
  Any shell command to execute in the namespace

EXAMPLES:
  $0                           # Start interactive shell
  $0 "ping google.com"         # Run ping command
  $0 "curl http://google.com"  # Test HTTP connectivity
  $0 "./your-miner"            # Run your mining software
  $0 -m "./your-miner"         # Run with network monitoring
  $0 -s                        # Just show network status

The namespace provides:
  - Isolated network environment
  - Internet connectivity (when connected)
  - IP address: $NS_IP (if config loaded)
  - Gateway: $HOST_IP (if config loaded)

Use disconnect-network.sh and reconnect-network.sh to control connectivity.
EOF
}

main() {
    local show_status=false
    local monitor=false
    local interactive=false
    local command=""
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -s|--status)
                show_status=true
                shift
                ;;
            -m|--monitor)
                monitor=true
                shift
                ;;
            -i|--interactive)
                interactive=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
            *)
                command="$*"
                break
                ;;
        esac
    done
    
    check_root
    load_config
    check_namespace_exists
    
    if [[ "$show_status" == true ]]; then
        show_network_status
        exit 0
    fi
    
    if [[ -z "$command" ]] || [[ "$interactive" == true ]]; then
        run_interactive_shell
    elif [[ "$monitor" == true ]]; then
        run_with_monitoring "$command"
    else
        run_command "$command"
    fi
}

main "$@"