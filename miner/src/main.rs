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
use tracing::error;
use std::sync::Arc;
use quiver::types::{Template, Submission, Target};
use bytes::Bytes;

#[tokio::main]
async fn main() {
    tracer::init();

    let config = Config::parse();

    // --- Template Provider ---
    let (template_tx, template_rx) = watch::channel(Template::new(Bytes::new(), Bytes::new(), Bytes::new(), Bytes::new(), Bytes::new()));
    let new_job_consumer = Arc::new(NockPoolNewJobConsumer { template_tx });

    // --- Submission Provider ---
    let initial_submission = Submission::new(Target::Pool, Bytes::new(), Bytes::new(), Bytes::new());
    let (submission_tx, submission_rx) = watch::channel(initial_submission);
    let submission_provider = Arc::new(NockPoolSubmissionProvider::new(submission_rx));

    let submission_response_handler = Arc::new(NockPoolSubmissionResponseHandler::new());

    // --- Gather System Info ---
    let device_info = device::get_device_info();
    tracing::info!(
        "Starting miner with OS='{}', CPU='{}', RAM='{}'GB",
        device_info.os,
        device_info.cpu_model,
        device_info.ram_capacity_gb
    );

    // --- Run the quiver client ---
    let key = config.key.clone();
    let server_address = config.server_address.clone();
    let client_address = config.client_address.clone();
    let insecure = config.insecure.clone();
    tokio::spawn(async move {
        if let Err(e) = quiver::client::run(
            insecure,
            server_address,
            client_address,
            key,
            device_info,
            new_job_consumer,
            submission_provider,
            submission_response_handler).await {
            error!("Error running client: {}", e);
        }
    });

    // --- Run the miner ---
    if let Err(e) = miner::start(config, template_rx, submission_tx).await {
        error!("Error running miner: {}", e);
    }
} 