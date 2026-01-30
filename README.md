# IPMI Sensor Data Collection Script

## Overview
`get_ipmi_sensors.sh` is a Bash script that collects hardware sensor data from all compute nodes using `ipmitool sdr list` and stores the output in structured CSV files.

The script is designed for cluster environments (e.g., PBS / HPC clusters) where multiple compute nodes need periodic monitoring of temperatures, voltages, fan speeds, power usage, CPU load, and memory statistics.
**IMPORTANT** make sure to run write_compute_nodes.sh before making get_ipmi_sensors.sh an executable as write_compute_nodes.sh retireves all the compute nodes and the master node and writes it into a file named free_nodes.txt


---

## Features
- Connects to all compute nodes listed in `free_nodes.txt`
- Executes `ipmitool sdr list` remotely via SSH
- Extracts readable sensors only:
  - Temperatures (°C)
  - Voltages (V)
  - Current (A)
  - Power (W)
  - Fan RPM
- Collects:
  - CPU Usage (%)
  - Memory Used (MB)
  - Memory Total (MB)
- Writes results into timestamped CSV files
- Automatically creates directory structure by **date** and **hour**
- Avoids duplicate headers
- Works with Bash 3.2+

---

## Output Format

### Directory Structure
```

BASE_DIR/
└── YYYY-MM-DD/
└── HH:00_to_HH+1:00/
└── <node>.csv

```

## Requirements
- Linux OS
- Bash 3.2 or later
- SSH access to compute nodes
- `ipmitool` installed on compute nodes
- `pbsnodes` (optional if auto-generating free nodes)
- Passwordless SSH recommended
### CSV  Example
```
timestamp,Ambient Temp (C),CPU 1 Temp (C),CPU 2 Temp (C),CPU 3 Temp (C),CPU 4 Temp (C),Current 1 (A),DIMM Bank A (C),DIMM Bank B (C),DIMM Bank C (C),DIMM Bank D (C),FAN 1 RPM (RPM),FAN 2 RPM (RPM),FAN 3 RPM (RPM),FAN 4 RPM (RPM),FAN 5 RPM (RPM),FAN 6 RPM (RPM),IO1 Planar Temp (C),IO2 Planar Temp (C),IOB1 Temp (C),IOB2 Temp (C),PS 1 Temp (C),PS 2 Temp (C),System Level (W),Voltage 1 (V),CPU (%),Memory Used (MB),Memory Total (MB)
2026-01-30T18:37:18Z,22,33,32,29,29,1.20,30,29,28,28,5040,5040,5160,5040,5160,5040,36,35,49,41,47,27,290,224,0.0,9501,128998
2026-01-30T18:44:46Z,22,33,32,29,30,1.20,30,29,28,28,5040,5040,5160,5040,5160,5040,36,35,48,41,47,27,290,224,0.0,9498,128998
2026-01-30T18:46:23Z,22,33,32,29,29,1.20,30,29,28,28,5040,5040,5160,5040,5160,5040,36,35,47,40,47,27,290,224,0.0,9497,128998
2026-01-30T18:50:49Z,22,34,32,29,29,1.20,30,29,28,28,5040,5040,5160,5040,5160,5040,36,35,47,40,47,27,290,224,0.0,9501,128998
2026-01-30T18:51:51Z,22,34,32,29,29,1.20,30,29,29,28,5040,5040,5160,5040,5160,5040,36,35,48,40,47,27,290,224,0.1,9504,128998
2026-01-30T18:52:55Z,22,34,32,29,28,1.20,30,29,29,28,5040,5040,5160,5040,5160,5040,36,35,48,40,47,27,290,224,0.0,9505,128998

```

## Installation
1. Copy script to a directory:
   ```bash
   /root/sensor_data_storage/
````

2. Make executable:

   ```bash
   chmod +x get_ipmi_sensors.sh
   ```

3. Ensure `free_nodes.txt` exists with node names:

   ```
   compute-0-0
   compute-0-1
   ```

---

## Usage

### Manual Run

```bash
./get_ipmi_sensors.sh
```
## Configuration Options

| Option           | Description                     |
| ---------------- | ------------------------------- |
| `--base-dir`     | Base directory for CSV storage  |
| `--tz`           | Timezone for folder naming      |
| `free_nodes.txt` | Input file containing node list |

---
