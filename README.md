# 🌊 NockPool by SWPSCo

<img width="624" height="206" alt="Nockpool logo" src="https://github.com/user-attachments/assets/cab9f6bd-0279-4d17-9c90-485954464394" />

This repo includes code and binaries necessary to participate in [Nockpool](https://nockpool.com), the premier [Nockchain](https://nockchain.org) mining pool, with your Linux or Apple Silicon machines.

### Install

You can download the prebuilt binaries in the release tab. The macOS bins are codesigned and the Linux bins are SLSA3 attested -- we recommend [verifying](https://github.com/slsa-framework/slsa-verifier).


### Run


```
miner-linux-x86_64 --key nockpool_yourdevicekeyhere123  --max-threads 12
```

---

## FAQ

#### Where do I get a device key?

Create an account at [nockpool.com](https://nockpool.com) to create device keys.

#### How many threads should I use?

Logical cores times two minus 4 is a good rule of thumb. E.g., if you have a 16 core Ryzen capable of 32 threads, 28 would be a good target.

#### How much memory do I need?

As much as you can get! Recommended 8GB + 2.5 per thread.

#### How do I use custom jets?

Just swap out the `zkvm-jetpack` dependency in `Cargo.toml`.

--- 

### Building

Clone repo:

```
git clone https://github.com/SWPSCO/nockpool-miner
```

Build:

```bash
cargo build --release
```

Run: 

```
target/release/miner --key nockpool_yourdevicekeyhere123
```

| Flag | Environment Variable | Default | Description |
|---|---|---|---|
| `--key` | `KEY` | (required) | The device key for authentication with the nockpool server. |
| `--max-threads` | `MAX_THREADS` | (all available threads - 2) | Set the maximum number of threads to use for mining. |
| `--server-address` | `SERVER_ADDRESS` | `quiver.nockpool.com:27016` | The `ip:port` of the nockpool server. |
| `--client-address` | `CLIENT_ADDRESS` | `0.0.0.0:27017` | The `ip:port` of the quiver client. Not necessary to set it. |
| `--network-only` | `NETWORK_ONLY` | `false` | If we only want to mine for network shares, set this to true. |
| `--insecure` | `INSECURE` | `false` | If we want to use an insecure connection to the nockpool server, set this to true. |
| `--benchmark` | `BENCHMARK` | `false` | Run benchmarking tool to test the performance of the miner. This flag will ignore all other arguments. |
