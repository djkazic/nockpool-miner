## Nockpool by SWPSCo

<img width="624" height="206" alt="Nockpool logo" src="https://github.com/user-attachments/assets/cab9f6bd-0279-4d17-9c90-485954464394" />

This repo includes code and binaries necessary to participate in [Nockpool](https://nockpool.com), the premier [Nockchain](https://nockchain.org) mining pool, with your Linux or Apple Silicon machines.

### Install

You can download the prebuilt binaries in the release tab. The macOS bins are codesigned and the Linux bins are SLSA3 attested -- we recommend [verifying](https://github.com/slsa-framework/slsa-verifier).

### Run


```
miner-linux-x86_64 --key nockpool_yourapikeyhere123  --max-threads 12
```

### Building

Clone repo:

```
git clone https://github.com/SWPSCO/nockpool-miner
```

Install rust nightly:

```
curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh
rustup override set nightly

```


Build:

```bash
cargo build --release
```