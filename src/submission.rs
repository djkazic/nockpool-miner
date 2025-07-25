use async_trait::async_trait;
use tokio::sync::{watch, Mutex};
use anyhow::Result;
use tracing::info;
use std::sync::Arc;

use quiver::types::{Submission, SubmissionResponse};
use quiver::submission::{SubmissionProvider, SubmissionResponseHandler};

#[derive(Clone, Debug)]
pub struct NockPoolSubmissionProvider {
    pub submission_rx: Arc<Mutex<watch::Receiver<Submission>>>,
}

impl NockPoolSubmissionProvider {
    pub fn new(submission_rx: watch::Receiver<Submission>) -> Self {
        Self {
            submission_rx: Arc::new(Mutex::new(submission_rx)),
        }
    }
}

#[async_trait]
impl SubmissionProvider for NockPoolSubmissionProvider {
    async fn submit(&self) -> Result<Submission> {
        // Lock the mutex to get exclusive access to the single, shared receiver.
        let mut guard = self.submission_rx.lock().await;

        // Wait for the value to change from what the receiver has last seen.
        // This mutates the guarded receiver's internal "seen" state.
        // If the channel is closed, this will return an error.
        guard.changed().await?;

        // After a change has been received, borrow the new value and return it.
        // The mutex lock is released when `guard` goes out of scope here.
        let submission = guard.borrow().clone();
        Ok(submission)
    }
}

#[derive(Clone, Debug)]
pub struct NockPoolSubmissionResponseHandler {}

impl NockPoolSubmissionResponseHandler {
    pub fn new() -> Self {
        Self {}
    }
}

#[async_trait]
impl SubmissionResponseHandler for NockPoolSubmissionResponseHandler {
    async fn handle(&self, response: SubmissionResponse) -> Result<()> {
        info!("{:?}", response);
        Ok(())
    }
}
