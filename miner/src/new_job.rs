use async_trait::async_trait;
use tokio::sync::watch;
use anyhow::Result;

use quiver::new_job::NewJobConsumer;
use quiver::types::Template;

#[derive(Clone, Debug)]
pub struct NockPoolNewJobConsumer {
    pub template_tx: watch::Sender<Template>,
}

impl NockPoolNewJobConsumer {
    pub fn new(template_tx: watch::Sender<Template>) -> Self {
        Self { template_tx }
    }
}

#[async_trait]
impl NewJobConsumer for NockPoolNewJobConsumer {
    async fn process(&self, template: Template) -> Result<()> {
        let _ = self.template_tx.send(template);
        Ok(())
    }
}
