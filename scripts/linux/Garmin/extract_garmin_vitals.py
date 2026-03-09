#!/usr/bin/env python3
"""
Garmin Vital Data Extractor
============================
Extracts key health and fitness metrics from a Garmin Connect data export.

Usage:
    python extract_garmin_vitals.py --data-dir /path/to/garmin/export --output-dir ./garmin_output

Expected folder structure (standard Garmin export):
    DI_CONNECT/
      DI-Connect-Aggregator/   → Hydration logs, UDS daily summaries
      DI-Connect-Fitness/      → Activities, personal records
      DI-Connect-Metrics/      → VO2 Max, Training Load, Endurance, Hill scores
      DI-Connect-Wellness/     → Sleep, HR zones, biometrics, blood pressure, ECG events
      DI-Connect-User/         → User profile
"""

import argparse
import csv
import json
import os
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path


# ──────────────────────────────────────────────────────────────
# Helpers
# ──────────────────────────────────────────────────────────────

def load_json(path: Path):
    """Load a JSON file, returning None on error."""
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception as e:
        print(f"  [WARN] Could not read {path.name}: {e}")
        return None


def glob_sorted(directory: Path, pattern: str):
    """Glob files matching pattern, sorted by name (chronological for date-named files)."""
    return sorted(directory.glob(pattern))


def write_csv(output_dir: Path, filename: str, rows: list, fieldnames: list):
    """Write a list of dicts to a CSV file."""
    if not rows:
        print(f"  [SKIP] No data for {filename}")
        return
    output_dir.mkdir(parents=True, exist_ok=True)
    path = output_dir / filename
    with open(path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames, extrasaction="ignore")
        writer.writeheader()
        writer.writerows(rows)
    print(f"  [OK]   {path}  ({len(rows)} rows)")


def fmt_duration(seconds):
    """Format seconds as HH:MM:SS."""
    if seconds is None:
        return ""
    h = int(seconds) // 3600
    m = (int(seconds) % 3600) // 60
    s = int(seconds) % 60
    return f"{h:02d}:{m:02d}:{s:02d}"


def ms_to_min_sec(ms):
    """Convert milliseconds pace to MM:SS string."""
    if not ms:
        return ""
    total_sec = ms / 1000
    m = int(total_sec) // 60
    s = int(total_sec) % 60
    return f"{m}:{s:02d}"


# ──────────────────────────────────────────────────────────────
# Extractors
# ──────────────────────────────────────────────────────────────

def extract_user_profile(connect_dir: Path) -> dict:
    """Extract basic user profile info."""
    profile_path = connect_dir / "DI-Connect-User" / "user_profile.json"
    data = load_json(profile_path)
    if not data:
        return {}
    bio = data.get("userBioData", data)  # structure varies
    return {
        "displayName": data.get("displayName", ""),
        "fullName":    data.get("fullName", ""),
        "email":       data.get("email", ""),
        "gender":      bio.get("gender", data.get("gender", "")),
        "birthdate":   bio.get("birthdate", data.get("birthdate", "")),
        "weight_kg":   bio.get("weight", ""),
        "height_cm":   bio.get("height", ""),
    }


def extract_biometrics(wellness_dir: Path, output_dir: Path):
    """Extract weight, body fat, and other biometric measurements over time."""
    rows = []
    fields = ["date", "weight_kg", "weight_lbs", "bmi", "bodyFat_pct",
              "bodyWater_pct", "boneMass_kg", "muscleMass_kg",
              "physiqueRating", "visceralFat", "metabolicAge"]

    for fname in ["4460427_userBioMetrics.json"]:
        path = wellness_dir / fname
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("bioMetrics", [data])
        for entry in entries:
            raw_weight = entry.get("weight")
            # weight can be a plain number OR a dict like {"value": 75.0, "unit": "kg"}
            if isinstance(raw_weight, dict):
                weight_kg = raw_weight.get("value")
            else:
                weight_kg = raw_weight
            rows.append({
                "date":           entry.get("measurementTimestamp", entry.get("date", "")),
                "weight_kg":      weight_kg,
                "weight_lbs":     round(weight_kg * 2.20462, 1) if weight_kg else "",
                "bmi":            entry.get("bmi"),
                "bodyFat_pct":    entry.get("bodyFat"),
                "bodyWater_pct":  entry.get("bodyWater"),
                "boneMass_kg":    entry.get("boneMass"),
                "muscleMass_kg":  entry.get("muscleMass"),
                "physiqueRating": entry.get("physiqueRating"),
                "visceralFat":    entry.get("visceralFat"),
                "metabolicAge":   entry.get("metabolicAge"),
            })

    # Also check the latest biometrics snapshot
    latest_path = wellness_dir / "4460427_bioMetrics_latest.json"
    latest = load_json(latest_path)
    if latest:
        # This file often contains a single snapshot
        entries = latest if isinstance(latest, list) else [latest]
        for entry in entries:
            raw_weight = entry.get("weight")
            weight_kg = raw_weight.get("value") if isinstance(raw_weight, dict) else raw_weight
            rows.append({
                "date":           entry.get("measurementTimestamp", entry.get("date", "latest")),
                "weight_kg":      weight_kg,
                "weight_lbs":     round(weight_kg * 2.20462, 1) if weight_kg else "",
                "bmi":            entry.get("bmi"),
                "bodyFat_pct":    entry.get("bodyFat"),
                "bodyWater_pct":  entry.get("bodyWater"),
                "boneMass_kg":    entry.get("boneMass"),
                "muscleMass_kg":  entry.get("muscleMass"),
                "physiqueRating": entry.get("physiqueRating"),
                "visceralFat":    entry.get("visceralFat"),
                "metabolicAge":   entry.get("metabolicAge"),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "biometrics.csv", rows, fields)


def extract_blood_pressure(wellness_dir: Path, output_dir: Path):
    """Extract blood pressure readings."""
    rows = []
    fields = ["timestamp", "systolic_mmhg", "diastolic_mmhg", "pulse_bpm", "notes"]

    for path in glob_sorted(wellness_dir, "BloodPressureFile_*.json"):
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("bloodPressureReadings", [])
        for entry in entries:
            rows.append({
                "timestamp":       entry.get("measurementTimestamp", entry.get("startTimestampLocal", "")),
                "systolic_mmhg":   entry.get("systolic"),
                "diastolic_mmhg":  entry.get("diastolic"),
                "pulse_bpm":       entry.get("pulse"),
                "notes":           entry.get("notes", ""),
            })

    rows.sort(key=lambda r: str(r.get("timestamp") or ""))
    write_csv(output_dir, "blood_pressure.csv", rows, fields)


def extract_sleep(wellness_dir: Path, output_dir: Path):
    """Extract nightly sleep summaries."""
    rows = []
    fields = ["date", "total_sleep_hours", "deep_sleep_min", "light_sleep_min",
              "rem_sleep_min", "awake_min", "avg_resting_hr", "avg_hrv",
              "avg_spo2_pct", "sleep_score", "avg_stress"]

    for path in glob_sorted(wellness_dir, "*_sleepData.json"):
        data = load_json(path)
        if not data:
            continue
        nights = data if isinstance(data, list) else data.get("sleepData", [data])
        for night in nights:
            summary = night.get("dailySleepDTO", night)
            total_s = summary.get("sleepTimeSeconds")
            rows.append({
                "date":              summary.get("calendarDate", summary.get("sleepStartTimestampLocal", "")),
                "total_sleep_hours": round(total_s / 3600, 2) if total_s else "",
                "deep_sleep_min":    round(summary.get("deepSleepSeconds", 0) / 60, 1),
                "light_sleep_min":   round(summary.get("lightSleepSeconds", 0) / 60, 1),
                "rem_sleep_min":     round(summary.get("remSleepSeconds", 0) / 60, 1),
                "awake_min":         round(summary.get("awakeSleepSeconds", 0) / 60, 1),
                "avg_resting_hr":    summary.get("averageRestingHeartRate", summary.get("avgSleepingHeartRate")),
                "avg_hrv":           summary.get("averageHrvScore", summary.get("avgHrv")),
                "avg_spo2_pct":      summary.get("averageSpO2Value"),
                "sleep_score":       summary.get("sleepScores", {}).get("overall", summary.get("overallScore")),
                "avg_stress":        summary.get("avgSleepStress"),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "sleep.csv", rows, fields)


def extract_heart_rate(wellness_dir: Path, output_dir: Path):
    """Extract abnormal heart rate events (high/low HR alerts)."""
    rows = []
    fields = ["timestamp", "event_type", "heart_rate_bpm", "duration_min"]

    for path in glob_sorted(wellness_dir, "*_AbnormalHrEvents.json"):
        data = load_json(path)
        if not data:
            continue
        events = data if isinstance(data, list) else data.get("abnormalHRAlerts", [])
        for event in events:
            duration_s = event.get("durationInMilliseconds", 0) / 1000
            rows.append({
                "timestamp":     event.get("startTimestampLocal", event.get("timestamp", "")),
                "event_type":    event.get("alertType", "UNKNOWN"),
                "heart_rate_bpm": event.get("heartRate"),
                "duration_min":   round(duration_s / 60, 2),
            })

    rows.sort(key=lambda r: str(r.get("timestamp") or ""))
    write_csv(output_dir, "abnormal_heart_rate_events.csv", rows, fields)


def extract_hr_zones(wellness_dir: Path, output_dir: Path):
    """Extract heart rate zone definitions."""
    path = wellness_dir / "4460427_heartRateZones.json"
    data = load_json(path)
    if not data:
        return
    rows = []
    fields = ["zone", "name", "low_bpm", "high_bpm"]
    zones = data if isinstance(data, list) else data.get("heartRateZones", [])
    for z in zones:
        rows.append({
            "zone":     z.get("zone"),
            "name":     z.get("zoneName", z.get("name", "")),
            "low_bpm":  z.get("lowBpm", z.get("low")),
            "high_bpm": z.get("highBpm", z.get("high")),
        })
    write_csv(output_dir, "heart_rate_zones.csv", rows, fields)


def extract_vo2max(metrics_dir: Path, output_dir: Path):
    """Extract VO2 Max history."""
    rows = []
    fields = ["date", "vo2max", "fitness_age", "activity_type"]

    for path in glob_sorted(metrics_dir, "ActivityVo2Max_*.json"):
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("vo2MaxEntries", [data])
        for entry in entries:
            rows.append({
                "date":          entry.get("calendarDate", entry.get("timestamp", "")),
                "vo2max":        entry.get("vo2MaxValue", entry.get("vo2Max")),
                "fitness_age":   entry.get("fitnessAge"),
                "activity_type": entry.get("sport", entry.get("activityType", "")),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "vo2max.csv", rows, fields)


def extract_endurance(metrics_dir: Path, output_dir: Path):
    """Extract Endurance Score history."""
    rows = []
    fields = ["date", "endurance_score", "endurance_descriptor"]

    for path in glob_sorted(metrics_dir, "EnduranceScore_*.json"):
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("enduranceScoreData", [data])
        for entry in entries:
            rows.append({
                "date":                 entry.get("calendarDate", entry.get("timestamp", "")),
                "endurance_score":      entry.get("overallEnduranceScore", entry.get("score")),
                "endurance_descriptor": entry.get("descriptor"),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "endurance_score.csv", rows, fields)


def extract_training_readiness(metrics_dir: Path, output_dir: Path):
    """Extract Training Readiness scores."""
    rows = []
    fields = ["date", "readiness_score", "readiness_level",
              "hrv_status", "sleep_score", "recovery_time_hrs"]

    for path in glob_sorted(metrics_dir, "TrainingReadinessDTO_*.json"):
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("trainingReadinessDTO", [data])
        for entry in entries:
            rows.append({
                "date":              entry.get("calendarDate", entry.get("timestamp", "")),
                "readiness_score":   entry.get("score"),
                "readiness_level":   entry.get("level"),
                "hrv_status":        entry.get("hrvStatus"),
                "sleep_score":       entry.get("sleepScore"),
                "recovery_time_hrs": entry.get("recoveryTime"),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "training_readiness.csv", rows, fields)


def extract_training_load(metrics_dir: Path, output_dir: Path):
    """Extract Acute Training Load (ATL) data."""
    rows = []
    fields = ["date", "acute_load", "chronic_load", "training_load_feedback"]

    for path in glob_sorted(metrics_dir, "MetricsAcuteTrainingLoad_*.json"):
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("acuteTrainingLoadList", [data])
        for entry in entries:
            rows.append({
                "date":                  entry.get("calendarDate", entry.get("timestamp", "")),
                "acute_load":            entry.get("acuteLoad", entry.get("atl")),
                "chronic_load":          entry.get("chronicLoad", entry.get("ctl")),
                "training_load_feedback": entry.get("trainingLoadFeedback"),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "training_load.csv", rows, fields)


def extract_activities(fitness_dir: Path, output_dir: Path):
    """Extract summarized activity history."""
    rows = []
    fields = [
        "date", "activity_type", "name", "duration_hms",
        "distance_km", "distance_miles", "avg_hr_bpm", "max_hr_bpm",
        "calories", "avg_pace_min_km", "avg_speed_kmh",
        "elevation_gain_m", "avg_power_w", "avg_cadence",
        "avg_stress", "training_effect_aerobic", "training_effect_anaerobic",
    ]

    for path in glob_sorted(fitness_dir, "*_summarizedActivities.json"):
        data = load_json(path)
        if not data:
            continue
        activities = data if isinstance(data, list) else data.get("summarizedActivitiesExport", [])
        for act in activities:
            dist_m = act.get("distance", 0) or 0
            duration_s = act.get("duration", act.get("elapsedDuration", 0)) or 0
            avg_pace_ms = act.get("avgPace")

            rows.append({
                "date":              act.get("startTimeLocal", act.get("startTimestampLocal", "")),
                "activity_type":     act.get("activityType", {}).get("typeKey", act.get("activityType", "")),
                "name":              act.get("activityName", ""),
                "duration_hms":      fmt_duration(duration_s),
                "distance_km":       round(dist_m / 1000, 3) if dist_m else "",
                "distance_miles":    round(dist_m / 1609.344, 3) if dist_m else "",
                "avg_hr_bpm":        act.get("averageHR", act.get("avgHr")),
                "max_hr_bpm":        act.get("maxHR", act.get("maxHr")),
                "calories":          act.get("calories", act.get("activeCaloies")),
                "avg_pace_min_km":   ms_to_min_sec(avg_pace_ms),
                "avg_speed_kmh":     round(act.get("averageSpeed", 0) * 3.6, 2) if act.get("averageSpeed") else "",
                "elevation_gain_m":  act.get("elevationGain"),
                "avg_power_w":       act.get("avgPower"),
                "avg_cadence":       act.get("averageRunCadence", act.get("avgCadence")),
                "avg_stress":        act.get("avgStrenuousScore", act.get("avgStress")),
                "training_effect_aerobic":   act.get("aerobicTrainingEffect"),
                "training_effect_anaerobic": act.get("anaerobicTrainingEffect"),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "activities.csv", rows, fields)


def extract_personal_records(fitness_dir: Path, output_dir: Path):
    """Extract personal records (PRs)."""
    path = fitness_dir / "ecloaiza_personalRecord.json"
    data = load_json(path)
    if not data:
        return
    rows = []
    fields = ["activity_type", "record_type", "value", "date", "activity_id"]
    records = data if isinstance(data, list) else data.get("personalRecords", [])
    for rec in records:
        rows.append({
            "activity_type": rec.get("activityType", ""),
            "record_type":   rec.get("typeKey", rec.get("prTypeLabelKey", "")),
            "value":         rec.get("value", rec.get("prValue")),
            "date":          rec.get("prStartTimeLocal", rec.get("date", "")),
            "activity_id":   rec.get("activityId"),
        })
    write_csv(output_dir, "personal_records.csv", rows, fields)


def extract_hydration(aggregator_dir: Path, output_dir: Path):
    """Extract daily hydration logs."""
    rows = []
    fields = ["date", "total_intake_ml", "goal_ml", "pct_of_goal"]

    for path in glob_sorted(aggregator_dir, "HydrationLogFile_*.json"):
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("hydrationLogs", [])
        for entry in entries:
            total = entry.get("valueInML", entry.get("sweatLoss"))
            goal  = entry.get("goalInML", entry.get("goal"))
            rows.append({
                "date":          entry.get("calendarDate", entry.get("date", "")),
                "total_intake_ml": total,
                "goal_ml":         goal,
                "pct_of_goal":     round(total / goal * 100, 1) if total and goal else "",
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "hydration.csv", rows, fields)


def extract_daily_summary(aggregator_dir: Path, output_dir: Path):
    """Extract User Daily Summary (UDS) — steps, stress, calories, HR."""
    rows = []
    fields = [
        "date", "total_steps", "step_goal", "total_distance_m",
        "active_calories", "resting_calories", "total_calories",
        "avg_resting_hr", "min_hr", "max_hr",
        "avg_stress", "max_stress", "rest_stress_duration_min",
        "floors_ascended", "floors_descended",
        "moderate_intensity_min", "vigorous_intensity_min",
        "body_battery_highest", "body_battery_lowest",
    ]

    for path in glob_sorted(aggregator_dir, "UDSFile_*.json"):
        data = load_json(path)
        if not data:
            continue
        entries = data if isinstance(data, list) else data.get("dailySummaries", [data])
        for entry in entries:
            rows.append({
                "date":                      entry.get("calendarDate", entry.get("summaryDay", "")),
                "total_steps":               entry.get("totalSteps"),
                "step_goal":                 entry.get("stepGoal"),
                "total_distance_m":          entry.get("totalDistanceMeters"),
                "active_calories":           entry.get("activeKilocalories"),
                "resting_calories":          entry.get("bmrKilocalories"),
                "total_calories":            entry.get("totalKilocalories"),
                "avg_resting_hr":            entry.get("restingHeartRate"),
                "min_hr":                    entry.get("minHeartRate"),
                "max_hr":                    entry.get("maxHeartRate"),
                "avg_stress":                entry.get("averageStressLevel"),
                "max_stress":                entry.get("maxStressLevel"),
                "rest_stress_duration_min":  round(entry.get("restStressDuration", 0) / 60, 1),
                "floors_ascended":           entry.get("floorsAscended"),
                "floors_descended":          entry.get("floorsDescended"),
                "moderate_intensity_min":    entry.get("moderateIntensityMinutes"),
                "vigorous_intensity_min":    entry.get("vigorousIntensityMinutes"),
                "body_battery_highest":      entry.get("highlyActiveSeconds"),  # may vary
                "body_battery_lowest":       entry.get("bodyBatteryLowest"),
            })

    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "daily_summary.csv", rows, fields)


def extract_fitness_age(wellness_dir: Path, output_dir: Path):
    """Extract Fitness Age data."""
    path = wellness_dir / "4460427_fitnessAgeData.json"
    data = load_json(path)
    if not data:
        return
    rows = []
    fields = ["date", "fitness_age", "chronological_age", "vo2max"]
    entries = data if isinstance(data, list) else data.get("fitnessAgeData", [data])
    for entry in entries:
        rows.append({
            "date":               entry.get("calendarDate", entry.get("date", "")),
            "fitness_age":        entry.get("fitnessAge"),
            "chronological_age":  entry.get("chronologicalAge"),
            "vo2max":             entry.get("vo2Max"),
        })
    rows.sort(key=lambda r: str(r.get("date") or ""))
    write_csv(output_dir, "fitness_age.csv", rows, fields)


def generate_summary_report(profile: dict, output_dir: Path):
    """Write a plain-text summary report."""
    lines = [
        "=" * 60,
        "  GARMIN VITAL DATA EXTRACTION REPORT",
        f"  Generated: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}",
        "=" * 60,
        "",
        "USER PROFILE",
        "-" * 40,
    ]
    for k, v in profile.items():
        if v:
            lines.append(f"  {k:<20}: {v}")

    lines += [
        "",
        "EXTRACTED DATA FILES",
        "-" * 40,
    ]

    csv_files = sorted(output_dir.glob("*.csv"))
    for f in csv_files:
        with open(f, "r", encoding="utf-8") as fh:
            row_count = sum(1 for _ in fh) - 1  # subtract header
        lines.append(f"  {f.name:<40} {row_count:>6} records")

    lines += [
        "",
        "DATA CATEGORIES",
        "-" * 40,
        "  daily_summary.csv       → Steps, calories, HR, stress, body battery (daily)",
        "  sleep.csv               → Nightly sleep stages, HRV, SpO2, sleep score",
        "  biometrics.csv          → Weight, BMI, body fat, muscle mass over time",
        "  blood_pressure.csv      → Systolic / diastolic / pulse readings",
        "  abnormal_heart_rate.csv → High/low HR alert events",
        "  heart_rate_zones.csv    → Your HR zone definitions",
        "  vo2max.csv              → VO2 Max history (aerobic fitness)",
        "  fitness_age.csv         → Garmin Fitness Age history",
        "  endurance_score.csv     → Endurance score history",
        "  training_readiness.csv  → Daily training readiness",
        "  training_load.csv       → Acute & chronic training load",
        "  activities.csv          → All recorded workouts/activities",
        "  personal_records.csv    → Your all-time PRs",
        "  hydration.csv           → Daily fluid intake vs. goal",
        "",
    ]

    report_path = output_dir / "extraction_report.txt"
    with open(report_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"\n  [OK]   {report_path}")


# ──────────────────────────────────────────────────────────────
# Main
# ──────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Extract vital health data from a Garmin Connect data export."
    )
    parser.add_argument(
        "--data-dir", "-d",
        required=True,
        help="Root directory of your Garmin data export (contains DI_CONNECT, INREACH, etc.)"
    )
    parser.add_argument(
        "--output-dir", "-o",
        default="./garmin_vitals_output",
        help="Directory to write extracted CSV files (default: ./garmin_vitals_output)"
    )
    args = parser.parse_args()

    data_dir   = Path(args.data_dir).expanduser().resolve()
    output_dir = Path(args.output_dir).expanduser().resolve()

    if not data_dir.exists():
        print(f"ERROR: Data directory not found: {data_dir}")
        sys.exit(1)

    # Standard Garmin export paths
    connect_dir    = data_dir / "DI_CONNECT"
    aggregator_dir = connect_dir / "DI-Connect-Aggregator"
    fitness_dir    = connect_dir / "DI-Connect-Fitness"
    metrics_dir    = connect_dir / "DI-Connect-Metrics"
    wellness_dir   = connect_dir / "DI-Connect-Wellness"

    print(f"\nGarmin Vital Data Extractor")
    print(f"  Source : {data_dir}")
    print(f"  Output : {output_dir}")
    print()

    output_dir.mkdir(parents=True, exist_ok=True)

    print("── User Profile ─────────────────────────────")
    profile = extract_user_profile(connect_dir)
    for k, v in profile.items():
        if v:
            print(f"  {k}: {v}")

    print("\n── Wellness / Health ────────────────────────")
    extract_biometrics(wellness_dir, output_dir)
    extract_blood_pressure(wellness_dir, output_dir)
    extract_sleep(wellness_dir, output_dir)
    extract_heart_rate(wellness_dir, output_dir)
    extract_hr_zones(wellness_dir, output_dir)
    extract_fitness_age(wellness_dir, output_dir)

    print("\n── Fitness Metrics ──────────────────────────")
    extract_vo2max(metrics_dir, output_dir)
    extract_endurance(metrics_dir, output_dir)
    extract_training_readiness(metrics_dir, output_dir)
    extract_training_load(metrics_dir, output_dir)

    print("\n── Activities ───────────────────────────────")
    extract_activities(fitness_dir, output_dir)
    extract_personal_records(fitness_dir, output_dir)

    print("\n── Daily Aggregates ─────────────────────────")
    extract_daily_summary(aggregator_dir, output_dir)
    extract_hydration(aggregator_dir, output_dir)

    print("\n── Summary Report ───────────────────────────")
    generate_summary_report(profile, output_dir)

    print(f"\nDone! All files written to: {output_dir}\n")


if __name__ == "__main__":
    main()