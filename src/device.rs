use sysinfo::System;
use quiver::device_info::DeviceInfo;

pub fn get_device_info() -> DeviceInfo {
    let mut sys = System::new();
    sys.refresh_cpu();
    sys.refresh_memory();
    let os = System::long_os_version().unwrap_or_else(|| "Unknown OS".to_string());
    let cpu_model = sys.cpus().first().map_or("Unknown CPU".to_string(), |cpu| cpu.brand().to_string());
    // Convert from bytes to gigabytes
    let ram_capacity_gb = sys.total_memory() / (1024 * 1024 * 1024);

    DeviceInfo {
        os: os.clone().trim().to_string(),
        cpu_model: cpu_model.clone().trim().to_string(),
        ram_capacity_gb,
    }
}