use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tokio::time::sleep;

// API authentication for mining token creation

#[derive(Debug, Serialize)]
struct CreateMiningTokenRequest {
    device_nickname: Option<String>,
    expires_days: Option<u32>,
}

#[derive(Debug, Deserialize)]
struct MiningTokenResponse {
    mining_token: String,
}

pub struct SupabaseAuth {
    client: Client,
}

impl SupabaseAuth {
    pub fn new() -> Self {
        Self {
            client: Client::new(),
        }
    }

    pub async fn create_mining_token(&self, account_token: &str, device_nickname: Option<String>, api_base_url: &str) -> Result<String> {
        let api_url = format!("{}/api/v1/mining-tokens", api_base_url);
        
        let request = CreateMiningTokenRequest {
            device_nickname,
            expires_days: None, // Set timestamp to null
        };

        const MAX_RETRIES: u32 = 5;
        let mut retry_count = 0;

        loop {
            let response = self
                .client
                .post(&api_url)
                .header("Authorization", format!("Bearer {}", account_token))
                .header("Content-Type", "application/json")
                .json(&request)
                .send()
                .await?;

            if response.status().is_success() {
                let response_data: MiningTokenResponse = response.json().await?;
                return Ok(response_data.mining_token);
            }

            let status = response.status();
            let error_text = response.text().await?;
            
            match status.as_u16() {
                401 => return Err(anyhow!("Invalid or expired account token")),
                403 => return Err(anyhow!("Account token does not have permission to create mining tokens")),
                404 => return Err(anyhow!("Mining token creation endpoint not found - this feature may not be available yet")),
                429 => {
                    if retry_count >= MAX_RETRIES {
                        return Err(anyhow!("Rate limit exceeded - maximum retries ({}) reached", MAX_RETRIES));
                    }
                    
                    // Exponential backoff: 1, 2, 4, 8, 10 seconds (capped at 10)
                    let delay_seconds = std::cmp::min(1u64 << retry_count, 10);
                    tracing::warn!("Rate limit hit, retrying in {} seconds (attempt {}/{})", delay_seconds, retry_count + 1, MAX_RETRIES + 1);
                    
                    sleep(Duration::from_secs(delay_seconds)).await;
                    retry_count += 1;
                    continue;
                }
                _ => return Err(anyhow!("Mining token creation failed ({}): {}", status, error_text)),
            }
        }
    }

    pub async fn get_or_create_mining_token(&self, account_token: &str, device_nickname: Option<String>, api_base_url: &str) -> Result<String> {
        tracing::info!("Creating mining token using account token...");
        let mining_token = self.create_mining_token(account_token, device_nickname, api_base_url).await?;
        tracing::info!("Successfully created mining token");
        Ok(mining_token)
    }
}