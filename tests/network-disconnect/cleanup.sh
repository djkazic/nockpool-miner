#!/bin/bash

# Network Namespace Cleanup Script
# Removes all resources created by the isolation system

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

load_config() {
    if [[ -f /tmp/netns-config ]]; then
        source /tmp/netns-config
        return 0
    else
        log_warn "Configuration file not found, using default values"
        # Set default values if config is missing
        NAMESPACE="testnet"
        VETH_HOST="veth-host"
        VETH_NS="veth-ns"
        SUBNET="192.168.100.0/24"
        DEFAULT_IFACE=$(ip route | grep '^default' | head -n1 | sed 's/.*dev \([^ ]*\).*/\1/' || echo "eth0")
        return 1
    fi
}

cleanup_processes() {
    log_info "Cleaning up processes in namespace..."
    
    # Kill any processes running in the namespace
    if ip netns list | grep -q "^$NAMESPACE"; then
        local pids=$(ip netns pids "$NAMESPACE" 2>/dev/null || true)
        if [[ -n "$pids" ]]; then
            log_warn "Killing processes in namespace: $pids"
            echo "$pids" | xargs -r kill -TERM || true
            sleep 2
            # Force kill if needed
            pids=$(ip netns pids "$NAMESPACE" 2>/dev/null || true)
            if [[ -n "$pids" ]]; then
                echo "$pids" | xargs -r kill -KILL || true
            fi
        fi
    fi
}

cleanup_iptables() {
    log_info "Cleaning up iptables rules..."
    
    # Remove NAT rule
    iptables -t nat -D POSTROUTING -s "$SUBNET" -o "$DEFAULT_IFACE" -j MASQUERADE 2>/dev/null || true
    
    # Remove forwarding rules
    iptables -D FORWARD -i "$VETH_HOST" -o "$DEFAULT_IFACE" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$DEFAULT_IFACE" -o "$VETH_HOST" -j ACCEPT 2>/dev/null || true
    
    # Remove any blocking rules that might have been added by disconnect script
    iptables -D INPUT -i "$VETH_HOST" -j DROP 2>/dev/null || true
    iptables -D OUTPUT -o "$VETH_HOST" -j DROP 2>/dev/null || true
    iptables -D FORWARD -i "$VETH_HOST" -j DROP 2>/dev/null || true
    iptables -D FORWARD -o "$VETH_HOST" -j DROP 2>/dev/null || true
}

cleanup_interfaces() {
    log_info "Cleaning up network interfaces..."
    
    # Remove veth pair (this will remove both ends)
    if ip link show "$VETH_HOST" &>/dev/null; then
        log_info "Removing veth interface: $VETH_HOST"
        ip link delete "$VETH_HOST" 2>/dev/null || true
    fi
}

cleanup_namespace() {
    log_info "Cleaning up network namespace..."
    
    if ip netns list | grep -q "^$NAMESPACE"; then
        log_info "Removing namespace: $NAMESPACE"
        ip netns delete "$NAMESPACE" 2>/dev/null || true
    else
        log_warn "Namespace $NAMESPACE does not exist"
    fi
}

cleanup_config() {
    log_info "Cleaning up configuration files..."
    
    if [[ -f /tmp/netns-config ]]; then
        rm -f /tmp/netns-config
        log_info "Removed configuration file"
    fi
}

verify_cleanup() {
    log_info "Verifying cleanup..."
    
    local errors=0
    
    # Check namespace
    if ip netns list | grep -q "^$NAMESPACE"; then
        log_error "✗ Namespace $NAMESPACE still exists"
        ((errors++))
    else
        log_info "✓ Namespace removed"
    fi
    
    # Check veth interface
    if ip link show "$VETH_HOST" &>/dev/null; then
        log_error "✗ Interface $VETH_HOST still exists"
        ((errors++))
    else
        log_info "✓ Veth interfaces removed"
    fi
    
    # Check config file
    if [[ -f /tmp/netns-config ]]; then
        log_error "✗ Configuration file still exists"
        ((errors++))
    else
        log_info "✓ Configuration file removed"
    fi
    
    if [[ $errors -eq 0 ]]; then
        log_info "✓ Cleanup completed successfully"
        return 0
    else
        log_warn "$errors issues found during cleanup verification"
        return 1
    fi
}

show_usage() {
    cat << EOF
Usage: $0 [OPTIONS]

Clean up the network namespace isolation system.

OPTIONS:
  -h, --help     Show this help message
  -f, --force    Force cleanup even if configuration is missing
  -v, --verify   Verify cleanup was successful

This script removes:
  - Network namespace and all processes within it
  - Veth interface pair
  - iptables rules (NAT, forwarding, blocking)
  - Configuration files

EXAMPLES:
  $0           # Standard cleanup
  $0 --force   # Force cleanup with default values
  $0 --verify  # Cleanup and verify success
EOF
}

main() {
    local force=false
    local verify=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_usage
                exit 0
                ;;
            -f|--force)
                force=true
                shift
                ;;
            -v|--verify)
                verify=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                show_usage
                exit 1
                ;;
        esac
    done
    
    check_root
    
    log_info "Starting network namespace cleanup..."
    
    if ! load_config && [[ "$force" != true ]]; then
        log_error "Configuration not found and --force not specified"
        log_info "Use --force to cleanup with default values"
        exit 1
    fi
    
    # Perform cleanup in order
    cleanup_processes
    cleanup_iptables
    cleanup_interfaces
    cleanup_namespace
    cleanup_config
    
    if [[ "$verify" == true ]]; then
        echo
        if verify_cleanup; then
            log_info "All cleanup verification checks passed"
        else
            log_warn "Some cleanup verification checks failed"
            log_info "You may need to manually remove remaining resources"
        fi
    else
        log_info "Cleanup completed"
        log_info "Use --verify option to verify cleanup was successful"
    fi
}

main "$@"