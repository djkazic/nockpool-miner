# Network Namespace Isolation System

A complete system for testing software behavior during network disconnections using Linux network namespaces.

## Quick Start

```bash
# 1. Set up the isolated network environment
sudo ./setup-isolation.sh

# 2. Run your software in the isolated namespace
sudo ./run-in-namespace.sh "./your-mining-software"

# 3. In another terminal, disconnect the network
sudo ./disconnect-network.sh

# 4. Reconnect the network
sudo ./reconnect-network.sh

# 5. Clean up when done
sudo ./cleanup.sh
```

## Scripts Overview

### `setup-isolation.sh`
Creates an isolated network namespace with internet connectivity:
- Auto-detects your default network interface
- Creates a network namespace called `testnet`
- Sets up veth pair for host-namespace communication
- Configures NAT and routing for internet access
- Uses IP range `192.168.100.0/24`

### `run-in-namespace.sh`
Runs software in the isolated namespace:
- Interactive shell mode (default)
- Command execution mode
- Network monitoring mode
- Status checking mode

**Usage examples:**
```bash
# Interactive shell
sudo ./run-in-namespace.sh

# Run a specific command
sudo ./run-in-namespace.sh "ping google.com"

# Run with network monitoring
sudo ./run-in-namespace.sh -m "./your-miner"

# Check network status
sudo ./run-in-namespace.sh -s
```

### `disconnect-network.sh`
Disconnects network connectivity for the namespace using various methods:
- `route` - Remove default route (default, safest)
- `interface` - Bring down veth interface
- `iptables` - Block traffic with firewall rules

**Usage:**
```bash
# Use default method (route deletion)
sudo ./disconnect-network.sh

# Use specific method
sudo ./disconnect-network.sh interface
sudo ./disconnect-network.sh iptables
```

### `reconnect-network.sh`
Restores network connectivity:
- Automatically detects the disconnection method used
- Applies appropriate restoration
- Includes force mode for difficult cases

**Usage:**
```bash
# Automatic reconnection
sudo ./reconnect-network.sh

# Force reconnection (try all methods)
sudo ./reconnect-network.sh --force
```

### `cleanup.sh`
Removes all created resources:
- Kills processes in the namespace
- Removes namespace and interfaces
- Cleans up iptables rules
- Removes configuration files

**Usage:**
```bash
# Standard cleanup
sudo ./cleanup.sh

# Force cleanup with verification
sudo ./cleanup.sh --force --verify
```

## Testing Your Miner

### Basic Test
```bash
# Set up
sudo ./setup-isolation.sh

# Run your miner
sudo ./run-in-namespace.sh "./target/debug/nockpool-miner --server-address your-server --key your-key"

# In another terminal, test disconnection
sudo ./disconnect-network.sh

# Watch the miner's behavior, then reconnect
sudo ./reconnect-network.sh

# Clean up
sudo ./cleanup.sh
```

### Advanced Testing with Monitoring
```bash
# Run with network monitoring
sudo ./run-in-namespace.sh -m "./target/debug/nockpool-miner --server-address your-server --key your-key"
```

This will show periodic connectivity status while your miner runs.

### Interactive Testing
```bash
# Start interactive shell in namespace
sudo ./run-in-namespace.sh

# In the namespace shell, you can:
ping google.com
curl http://google.com
./your-miner-binary

# In another terminal, control connectivity:
sudo ./disconnect-network.sh
sudo ./reconnect-network.sh
```

## Network Architecture

```
Host System (192.168.1.x)
    │
    ├── veth-host (192.168.100.1)
    │   │
    │   └── NAT/Forwarding Rules
    │
    └── testnet namespace
        └── veth-ns (192.168.100.2)
            └── Your Software
```

## Troubleshooting

### Permission Issues
All scripts require root privileges. Use `sudo`.

### "Namespace already exists"
```bash
sudo ./cleanup.sh --force
sudo ./setup-isolation.sh
```

### "Network still connected after disconnect"
```bash
# Try different disconnect method
sudo ./disconnect-network.sh iptables
```

### "Cannot reconnect network"
```bash
# Force reconnection
sudo ./reconnect-network.sh --force

# Or restart from scratch
sudo ./cleanup.sh --force
sudo ./setup-isolation.sh
```

### Check namespace status
```bash
# List namespaces
ip netns list

# Check interfaces
sudo ./run-in-namespace.sh -s

# Check routing
sudo ./run-in-namespace.sh "ip route"
```

## Configuration

The system saves configuration to `/tmp/netns-config`. You can modify these values:

- `NAMESPACE="testnet"` - Namespace name
- `VETH_HOST="veth-host"` - Host-side interface name
- `VETH_NS="veth-ns"` - Namespace-side interface name
- `NS_IP="192.168.100.2"` - Namespace IP
- `HOST_IP="192.168.100.1"` - Host bridge IP
- `SUBNET="192.168.100.0/24"` - Subnet range

## Requirements

- Linux with network namespace support
- Root access (sudo)
- iptables
- iproute2 package (`ip` command)

Tested on Ubuntu/Debian systems. Should work on most modern Linux distributions.