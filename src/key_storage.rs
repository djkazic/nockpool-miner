use anyhow::{anyhow, Result};
use directories::ProjectDirs;
use std::fs;
use std::path::PathBuf;
use tracing::{info, warn};

const APP_NAME: &str = "nockpool";
const KEY_FILENAME: &str = "mining_key.txt";

pub struct KeyStorage {
    config_dir: PathBuf,
    key_file_path: PathBuf,
}

impl KeyStorage {
    pub fn new() -> Result<Self> {
        let project_dirs = ProjectDirs::from("", "", APP_NAME)
            .ok_or_else(|| anyhow!("Could not determine config directory"))?;
        
        let config_dir = project_dirs.config_dir().to_path_buf();
        let key_file_path = config_dir.join(KEY_FILENAME);

        Ok(Self {
            config_dir,
            key_file_path,
        })
    }

    pub fn load_key(&self) -> Result<Option<String>> {
        if !self.key_file_path.exists() {
            info!("No stored mining key found at {}", self.key_file_path.display());
            return Ok(None);
        }

        match fs::read_to_string(&self.key_file_path) {
            Ok(key) => {
                let key = key.trim().to_string();
                if key.is_empty() {
                    warn!("Stored mining key file is empty");
                    return Ok(None);
                }
                info!("Loaded mining key from {}", self.key_file_path.display());
                Ok(Some(key))
            }
            Err(e) => {
                warn!("Failed to read mining key file: {}", e);
                Ok(None)
            }
        }
    }

    pub fn save_key(&self, key: &str) -> Result<()> {
        // Create config directory if it doesn't exist
        if !self.config_dir.exists() {
            fs::create_dir_all(&self.config_dir)?;
            info!("Created config directory: {}", self.config_dir.display());
        }

        // Save key to file
        fs::write(&self.key_file_path, key)?;
        info!("Saved mining key to {}", self.key_file_path.display());
        
        Ok(())
    }

    pub fn delete_key(&self) -> Result<()> {
        if self.key_file_path.exists() {
            fs::remove_file(&self.key_file_path)?;
            info!("Deleted mining key file: {}", self.key_file_path.display());
        }
        Ok(())
    }

    #[cfg(test)]
    pub fn key_exists(&self) -> bool {
        self.key_file_path.exists()
    }

    pub fn get_key_file_path(&self) -> &PathBuf {
        &self.key_file_path
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::tempdir;

    #[test]
    fn test_key_storage_operations() {
        let temp_dir = tempdir().unwrap();
        let config_dir = temp_dir.path().to_path_buf();
        let key_file_path = config_dir.join(KEY_FILENAME);
        
        let storage = KeyStorage {
            config_dir,
            key_file_path,
        };

        // Test no key initially
        assert!(!storage.key_exists());
        assert!(storage.load_key().unwrap().is_none());

        // Test save and load
        let test_key = "nock_1234567890abcdef";
        storage.save_key(test_key).unwrap();
        assert!(storage.key_exists());
        assert_eq!(storage.load_key().unwrap().unwrap(), test_key);

        // Test delete
        storage.delete_key().unwrap();
        assert!(!storage.key_exists());
    }
}