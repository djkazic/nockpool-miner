use anyhow::{anyhow, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};

// SUPABASE_URL is now configurable via Config
const SUPABASE_ANON_KEY: &str = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im5hcHV4YnBpZmVvb3Fkamt3bXZiIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NTI5NjU2ODIsImV4cCI6MjA2ODU0MTY4Mn0.iRpHFRr9o0wTpfllJeOnwwZMZh1D2HmgCjNI4j7xp_g";

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

        let response = self
            .client
            .post(&api_url)
            .header("Authorization", format!("Bearer {}", account_token))
            .header("Content-Type", "application/json")
            .json(&request)
            .send()
            .await?;

        if !response.status().is_success() {
            let status = response.status();
            let error_text = response.text().await?;
            
            match status.as_u16() {
                401 => return Err(anyhow!("Invalid or expired account token")),
                403 => return Err(anyhow!("Account token does not have permission to create mining tokens")),
                404 => return Err(anyhow!("Mining token creation endpoint not found - this feature may not be available yet")),
                429 => return Err(anyhow!("Rate limit exceeded - please try again later")),
                _ => return Err(anyhow!("Mining token creation failed ({}): {}", status, error_text)),
            }
        }

        let response_data: MiningTokenResponse = response.json().await?;
        Ok(response_data.mining_token)
    }

    pub async fn get_or_create_mining_token(&self, account_token: &str, device_nickname: Option<String>, api_base_url: &str) -> Result<String> {
        tracing::info!("Creating mining token using account token...");
        let mining_token = self.create_mining_token(account_token, device_nickname, api_base_url).await?;
        tracing::info!("Successfully created mining token");
        Ok(mining_token)
    }
}