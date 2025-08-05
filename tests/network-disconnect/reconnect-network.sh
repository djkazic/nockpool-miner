#!/bin/bash

# Network Reconnection Script
# Reconnects the network for the isolated namespace

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

reconnect_network() {
    # Try to determine which method was used for disconnection
    local method="${DISCONNECT_METHOD:-route}"
    
    case "$method" in
        "route")
            log_info "Reconnecting network using route restoration method..."
            # Restore default route in namespace
            ip netns exec "$NAMESPACE" ip route add default via "$HOST_IP" 2>/dev/null || {
                log_warn "Default route may already exist"
            }
            ;;
        "interface")
            log_info "Reconnecting network using interface up method..."
            # Bring up the veth interface in namespace
            ip netns exec "$NAMESPACE" ip link set "$VETH_NS" up 2>/dev/null || {
                log_warn "Interface $VETH_NS may already be up"
            }
            # Also restore the route in case it was removed
            ip netns exec "$NAMESPACE" ip route add default via "$HOST_IP" 2>/dev/null || true
            ;;
        "iptables")
            log_info "Reconnecting network using iptables unblock method..."
            # Remove blocking rules
            iptables -D INPUT -i "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -D OUTPUT -o "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -D FORWARD -i "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -D FORWARD -o "$VETH_HOST" -j DROP 2>/dev/null || true
            ;;
        *)
            log_warn "Unknown disconnect method '$method', trying all restoration methods..."
            # Try all methods
            ip netns exec "$NAMESPACE" ip link set "$VETH_NS" up 2>/dev/null || true
            ip netns exec "$NAMESPACE" ip route add default via "$HOST_IP" 2>/dev/null || true
            iptables -D INPUT -i "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -D OUTPUT -o "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -D FORWARD -i "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -D FORWARD -o "$VETH_HOST" -j DROP 2>/dev/null || true
            ;;
    esac
    
    # Clean the disconnect method from config
    sed -i '/^DISCONNECT_METHOD=/d' /tmp/netns-config
}

test_reconnection() {
    log_info "Testing network reconnection..."
    
    # Wait a moment for network to stabilize
    sleep 1
    
    # Test if network is reconnected
    if ip netns exec "$NAMESPACE" timeout 5 ping -c 1 8.8.8.8 &>/dev/null; then
        log_info "✓ Network successfully reconnected"
        return 0
    else
        log_error "✗ Network reconnection failed!"
        return 1
    fi
}

force_reconnect() {
    log_info "Performing force reconnection (trying all methods)..."
    
    # Ensure interface is up
    ip netns exec "$NAMESPACE" ip link set "$VETH_NS" up 2>/dev/null || true
    
    # Ensure route exists
    ip netns exec "$NAMESPACE" ip route add default via "$HOST_IP" 2>/dev/null || true
    
    # Remove any blocking iptables rules
    iptables -D INPUT -i "$VETH_HOST" -j DROP 2>/dev/null || true
    iptables -D OUTPUT -o "$VETH_HOST" -j DROP 2>/dev/null || true
    iptables -D FORWARD -i "$VETH_HOST" -j DROP 2>/dev/null || true
    iptables -D FORWARD -o "$VETH_HOST" -j DROP 2>/dev/null || true
    
    # Ensure forwarding is enabled
    echo 1 > /proc/sys/net/ipv4/ip_forward
}

show_usage() {
    echo "Usage: $0 [--force]"
    echo
    echo "Options:"
    echo "  --force   - Force reconnection using all methods"
    echo
    echo "This script automatically detects the disconnection method used"
    echo "and applies the appropriate reconnection method."
}

main() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    check_root
    load_config
    check_namespace_exists
    
    if [[ "$1" == "--force" ]]; then
        force_reconnect
    else
        reconnect_network
    fi
    
    if test_reconnection; then
        log_info "✓ Network reconnection complete"
    else
        log_warn "Network reconnection failed, trying force method..."
        force_reconnect
        if test_reconnection; then
            log_info "✓ Network reconnection complete (using force method)"
        else
            log_error "Network reconnection failed completely"
            log_info "Try running ./cleanup.sh and ./setup-isolation.sh to recreate the setup"
            exit 1
        fi
    fi
}

main "$@"