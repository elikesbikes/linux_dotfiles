# Apple Health Data Tools

Scripts to parse and report on Apple Health export data.

## Prerequisites

- Python 3
- Apple Health export (`export.xml`) from the Health app

**To export:** iPhone Health app → profile icon → Export All Health Data → extract the ZIP

The scripts expect the file at:
```
~/Downloads/export/apple_health_export/export.xml
```

## Scripts

### `parse_apple_sleep.py`

Parses sleep stage data and generates a daily breakdown.

**Output:** `~/Downloads/export/apple_health_export/sleep_report.txt`

**Stages reported:**
- Deep
- REM
- Core/Light
- Awake
- InBed

**Usage:**
```bash
python3 parse_apple_sleep.py
```

**Example output:**
```
DATE: 2025-02-22
  Deep        : 1.45 hrs
  REM         : 1.80 hrs
  Core/Light  : 3.20 hrs
  Awake       : 0.25 hrs
```

---

### `parse_apple_vitals.py`

Parses Resting Heart Rate (RHR) and Heart Rate Variability (HRV) and generates a daily average summary.

**Output:** `~/Downloads/export/apple_health_export/vitals_report.txt`

**Metrics:**
- Avg RHR (BPM)
- Avg HRV (ms, SDNN)

**Usage:**
```bash
python3 parse_apple_vitals.py
```

**Example output:**
```
Date         | Avg RHR (BPM)   | Avg HRV (ms)
---------------------------------------------
2025-02-22   |          52.0   |         45.3
```

## Notes

- Both scripts use `iterparse` for memory-efficient streaming, suitable for large exports (3GB+).
- Edit the `input_file` / `output_file` paths at the top of each script to change locations.
