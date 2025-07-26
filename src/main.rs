mod tracer;
mod new_job;
mod config;
mod device;
mod miner;
mod submission;

use crate::new_job::NockPoolNewJobConsumer;
use crate::submission::{NockPoolSubmissionProvider, NockPoolSubmissionResponseHandler};
use crate::config::Config;

use clap::Parser;
use tokio::sync::watch;
use tracing::{error, info};
use std::sync::Arc;
use quiver::types::{Template, Submission, Target};
use bytes::Bytes;

#[tokio::main]
async fn main() {
    tracer::init();

    let config = Config::parse();

    if config.benchmark {
        tracing::info!("Running benchmark...");
        if let Err(e) = miner::benchmark().await {
            tracing::error!("Error running benchmark: {}", e);
        }
        tracing::info!("Benchmark completed successfully");
        return;
    }

    // --- Template Provider ---
    let (template_tx, template_rx) = watch::channel(Template::new(Bytes::new(), Bytes::new(), Bytes::new(), Bytes::new(), Bytes::new()));
    let new_job_consumer = Arc::new(NockPoolNewJobConsumer::new(template_tx));

    // --- Submission Provider ---
    let initial_submission = Submission::new(Target::Pool, Bytes::new(), Bytes::new(), Bytes::new());
    let (submission_tx, submission_rx) = watch::channel(initial_submission);
    let submission_provider = Arc::new(NockPoolSubmissionProvider::new(submission_rx));

    let submission_response_handler = Arc::new(NockPoolSubmissionResponseHandler::new());

    // --- Gather System Info ---
    let device_info = device::get_device_info();
    tracing::info!(
        "Starting miner with OS='{}', CPU='{}', RAM='{} GB'",
        device_info.os,
        device_info.cpu_model,
        device_info.ram_capacity_gb
    );

    // --- Run the quiver client ---
    let Some(key) = config.key.clone() else {
        tracing::error!("No key provided");
        return;
    };
    let server_address = config.server_address.clone();
    let client_address = config.client_address.clone();
    let insecure = config.insecure.clone();
    tokio::spawn(async move {
        let mut backoff_ms = 100_u64;
        let max_backoff_ms = 30_000_u64;
    
        loop {
            if let Err(e) = quiver::client::run(
                insecure,
                server_address.clone(),
                client_address.clone(),
                key.clone(),
                device_info.clone(),
                new_job_consumer.clone(),
                submission_provider.clone(),
                submission_response_handler.clone()).await {
                error!("Error running client: {}", e);

                // sleep for the current backoff
                info!("Sleeping for {}ms", backoff_ms);
                tokio::time::sleep(tokio::time::Duration::from_millis(backoff_ms)).await;
    
                // double, but don’t exceed max
                backoff_ms = (backoff_ms * 2).min(max_backoff_ms);
            } else {
                // success: reset backoff and immediately retry (or break/return if done)
                backoff_ms = 100;
            }
        }
    });

    // --- Run the miner ---
    if let Err(e) = miner::start(config, template_rx, submission_tx).await {
        error!("Error running miner: {}", e);
    }
} 