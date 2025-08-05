#!/bin/bash

# Network Namespace Isolation Setup Script
# Creates an isolated network namespace with internet access for testing network disconnections

set -e

NAMESPACE="testnet"
VETH_HOST="veth-host"
VETH_NS="veth-ns"
NS_IP="192.168.100.2"
HOST_IP="192.168.100.1"
SUBNET="192.168.100.0/24"

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

check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

detect_default_interface() {
    # Find the default route interface
    local default_iface=$(ip route | grep '^default' | head -n1 | sed 's/.*dev \([^ ]*\).*/\1/')
    
    if [[ -z "$default_iface" ]]; then
        log_error "Could not detect default network interface"
        exit 1
    fi
    
    log_info "Detected default interface: $default_iface"
    echo "$default_iface"
}

cleanup_existing() {
    log_info "Cleaning up any existing setup..."
    
    # Remove namespace if it exists
    if ip netns list | grep -q "^$NAMESPACE"; then
        log_warn "Namespace $NAMESPACE already exists, removing..."
        ip netns delete "$NAMESPACE" 2>/dev/null || true
    fi
    
    # Remove veth interfaces if they exist
    if ip link show "$VETH_HOST" &>/dev/null; then
        log_warn "Interface $VETH_HOST already exists, removing..."
        ip link delete "$VETH_HOST" 2>/dev/null || true
    fi
    
    # Clean up any existing iptables rules
    iptables -t nat -D POSTROUTING -s "$SUBNET" -j MASQUERADE 2>/dev/null || true
    iptables -D FORWARD -i "$VETH_HOST" -o "$DEFAULT_IFACE" -j ACCEPT 2>/dev/null || true
    iptables -D FORWARD -i "$DEFAULT_IFACE" -o "$VETH_HOST" -j ACCEPT 2>/dev/null || true
}

create_namespace() {
    log_info "Creating network namespace: $NAMESPACE"
    ip netns add "$NAMESPACE"
    
    # Enable loopback in namespace
    ip netns exec "$NAMESPACE" ip link set lo up
}

create_veth_pair() {
    log_info "Creating veth pair: $VETH_HOST <-> $VETH_NS"
    ip link add "$VETH_HOST" type veth peer name "$VETH_NS"
    
    # Move one end to the namespace
    ip link set "$VETH_NS" netns "$NAMESPACE"
    
    # Configure host side
    ip addr add "$HOST_IP/24" dev "$VETH_HOST"
    ip link set "$VETH_HOST" up
    
    # Configure namespace side
    ip netns exec "$NAMESPACE" ip addr add "$NS_IP/24" dev "$VETH_NS"
    ip netns exec "$NAMESPACE" ip link set "$VETH_NS" up
    
    # Set default route in namespace
    ip netns exec "$NAMESPACE" ip route add default via "$HOST_IP"
}

setup_nat() {
    log_info "Setting up NAT and forwarding rules"
    
    # Enable IP forwarding
    echo 1 > /proc/sys/net/ipv4/ip_forward
    
    # Add NAT rule
    iptables -t nat -A POSTROUTING -s "$SUBNET" -o "$DEFAULT_IFACE" -j MASQUERADE
    
    # Add forwarding rules
    iptables -A FORWARD -i "$VETH_HOST" -o "$DEFAULT_IFACE" -j ACCEPT
    iptables -A FORWARD -i "$DEFAULT_IFACE" -o "$VETH_HOST" -j ACCEPT
}

test_connectivity() {
    log_info "Testing network connectivity in namespace..."
    
    # Test basic connectivity
    if ip netns exec "$NAMESPACE" ping -c 1 8.8.8.8 &>/dev/null; then
        log_info "✓ Internet connectivity works in namespace"
    else
        log_error "✗ Internet connectivity failed in namespace"
        return 1
    fi
    
    # Test DNS resolution
    if ip netns exec "$NAMESPACE" nslookup google.com &>/dev/null; then
        log_info "✓ DNS resolution works in namespace"
    else
        log_warn "DNS resolution may not work (but IP connectivity is fine)"
    fi
}

save_config() {
    log_info "Saving configuration..."
    
    cat > /tmp/netns-config << EOF
NAMESPACE="$NAMESPACE"
VETH_HOST="$VETH_HOST"
VETH_NS="$VETH_NS"
NS_IP="$NS_IP"
HOST_IP="$HOST_IP"
SUBNET="$SUBNET"
DEFAULT_IFACE="$DEFAULT_IFACE"
EOF
}

main() {
    log_info "Setting up network namespace isolation system..."
    
    check_root
    
    DEFAULT_IFACE=$(detect_default_interface)
    
    cleanup_existing
    create_namespace
    create_veth_pair
    setup_nat
    
    if test_connectivity; then
        save_config
        log_info "✓ Network namespace setup complete!"
        echo
        log_info "You can now:"
        log_info "  - Run software: ./run-in-namespace.sh 'your_command'"
        log_info "  - Disconnect network: ./disconnect-network.sh"
        log_info "  - Reconnect network: ./reconnect-network.sh"
        log_info "  - Cleanup: ./cleanup.sh"
    else
        log_error "Setup failed - cleaning up..."
        ./cleanup.sh 2>/dev/null || true
        exit 1
    fi
}

main "$@"