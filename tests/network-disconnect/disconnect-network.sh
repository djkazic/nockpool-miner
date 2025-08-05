#!/bin/bash

# Network Disconnection Script
# Disconnects the network for the isolated namespace

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

disconnect_network() {
    local method="${1:-route}"
    
    case "$method" in
        "route")
            log_info "Disconnecting network using route deletion method..."
            # Remove default route in namespace
            ip netns exec "$NAMESPACE" ip route del default 2>/dev/null || {
                log_warn "Default route already removed or doesn't exist"
            }
            ;;
        "interface")
            log_info "Disconnecting network using interface down method..."
            # Bring down the veth interface in namespace
            ip netns exec "$NAMESPACE" ip link set "$VETH_NS" down 2>/dev/null || {
                log_warn "Interface $VETH_NS already down or doesn't exist"
            }
            ;;
        "iptables")
            log_info "Disconnecting network using iptables block method..."
            # Block all traffic from the namespace
            iptables -I INPUT -i "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -I OUTPUT -o "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -I FORWARD -i "$VETH_HOST" -j DROP 2>/dev/null || true
            iptables -I FORWARD -o "$VETH_HOST" -j DROP 2>/dev/null || true
            ;;
        *)
            log_error "Invalid method: $method. Use 'route', 'interface', or 'iptables'"
            exit 1
            ;;
    esac
    
    # Save the method used for reconnection
    echo "DISCONNECT_METHOD=\"$method\"" >> /tmp/netns-config
}

test_disconnection() {
    log_info "Testing network disconnection..."
    
    # Test if network is actually disconnected
    if ip netns exec "$NAMESPACE" timeout 3 ping -c 1 8.8.8.8 &>/dev/null; then
        log_error "✗ Network is still connected!"
        return 1
    else
        log_info "✓ Network successfully disconnected"
        return 0
    fi
}

show_usage() {
    echo "Usage: $0 [method]"
    echo
    echo "Methods:"
    echo "  route     - Remove default route (default, safest)"
    echo "  interface - Bring down veth interface"
    echo "  iptables  - Block traffic with iptables rules"
    echo
    echo "Examples:"
    echo "  $0              # Use default route method"
    echo "  $0 route        # Use route deletion"
    echo "  $0 interface    # Use interface down"
    echo "  $0 iptables     # Use iptables blocking"
}

main() {
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    check_root
    load_config
    check_namespace_exists
    
    local method="${1:-route}"
    disconnect_network "$method"
    
    if test_disconnection; then
        log_info "✓ Network disconnection complete using '$method' method"
        log_info "Use ./reconnect-network.sh to restore connectivity"
    else
        log_error "Network disconnection failed"
        exit 1
    fi
}

main "$@"