use clap::Parser;

#[derive(Parser, Debug, Clone)]
#[command(version, about, long_about = None)]
pub struct Config {
    /// The secret key for authentication with the nockpool server.
    #[arg(long, required_unless_present = "benchmark")]
    pub key: Option<String>,

    /// Set the maximum number of threads to use for mining. Uses all available cores if not set.
    #[arg(long)]
    pub max_threads: Option<u32>,

    /// The `ip:port` of the nockpool server.
    #[arg(long, default_value = "127.0.0.1:27016")]
    pub server_address: String,

    /// The `ip:port` of the quiver client.
    #[arg(long, default_value = "0.0.0.0:27017")]
    pub client_address: String,

    /// If we only want to mine for network shares, set this to true.
    #[arg(long, default_value_t = false)]
    pub network_only: bool,

    /// If we want to use an insecure connection to the nockpool server, set this to true.
    #[arg(long, default_value_t = false)]
    pub insecure: bool,

    /// Run benchmarking tool to test the performance of the miner.
    #[arg(long, default_value_t = false)]
    pub benchmark: bool,
}
