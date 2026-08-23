# Garmin Data Tools

Python scripts to parse and extract health/fitness data from a [Garmin Connect data export](https://www.garmin.com/en-US/account/datamanagement/).

## Scripts

### `extract_garmin_vitals.py`

Full-featured extractor that processes all categories from a Garmin Connect export and writes CSV files.

**Usage:**
```bash
python extract_garmin_vitals.py --data-dir /path/to/garmin/export --output-dir ./garmin_output
```

**Arguments:**
| Flag | Short | Description |
|------|-------|-------------|
| `--data-dir` | `-d` | Root directory of your Garmin export (required) |
| `--output-dir` | `-o` | Output directory for CSV files (default: `./garmin_vitals_output`) |

**Output files:**
| File | Contents |
|------|----------|
| `daily_summary.csv` | Steps, calories, HR, stress, body battery (daily) |
| `sleep.csv` | Nightly sleep stages, HRV, SpO2, sleep score |
| `biometrics.csv` | Weight, BMI, body fat, muscle mass over time |
| `blood_pressure.csv` | Systolic / diastolic / pulse readings |
| `abnormal_heart_rate_events.csv` | High/low HR alert events |
| `heart_rate_zones.csv` | HR zone definitions |
| `vo2max.csv` | VO2 Max history |
| `fitness_age.csv` | Garmin Fitness Age history |
| `endurance_score.csv` | Endurance score history |
| `training_readiness.csv` | Daily training readiness |
| `training_load.csv` | Acute & chronic training load |
| `activities.csv` | All recorded workouts/activities |
| `personal_records.csv` | All-time personal records |
| `hydration.csv` | Daily fluid intake vs. goal |
| `extraction_report.txt` | Summary report with record counts |

---

### `parse_garmin_sleep.py`

Simpler script focused on sleep data. Reads all `*_sleepData.json` files and produces a single consolidated text report.

**Configuration** (edit variables at the top of the script):
```python
data_path   = '/path/to/DI_CONNECT/DI-Connect-Wellness'
output_file = '/path/to/garmin_sleep_summary.txt'
```

**Run:**
```bash
python parse_garmin_sleep.py
```

**Output:** A plain-text table with columns: `Date | Deep | REM | Light | Total`.

---

## Getting Your Garmin Export

1. Log in to [Garmin Connect](https://connect.garmin.com)
2. Go to **Account Settings → Data Management → Export Your Data**
3. Request and download the ZIP archive
4. Extract it — the root folder should contain `DI_CONNECT/`

Expected folder structure:
```
DI_CONNECT/
  DI-Connect-Aggregator/   # Hydration logs, daily summaries
  DI-Connect-Fitness/      # Activities, personal records
  DI-Connect-Metrics/      # VO2 Max, Training Load, Endurance scores
  DI-Connect-Wellness/     # Sleep, HR zones, biometrics, blood pressure
  DI-Connect-User/         # User profile
```

## Requirements

- Python 3.7+
- No third-party dependencies (standard library only)
