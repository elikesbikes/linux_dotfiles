import json
import glob
import os

# Configuration
data_path = '/home/ecloaiza/Downloads/garmin/DI_CONNECT/DI-Connect-Wellness'
output_file = '/home/ecloaiza/scripts/linux/garmin_sleep_summary.txt'

def format_seconds(seconds):
    if not seconds: return "0h 0m"
    hours = int(seconds // 3600)
    minutes = int((seconds % 3600) // 60)
    return f"{hours}h {minutes}m"

# Search for all sleep JSON files
json_files = glob.glob(os.path.join(data_path, "*_sleepData.json"))

all_sleep_records = []

print(f"Found {len(json_files)} sleep data files. Processing...")

for file_path in json_files:
    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
            # Garmin JSON is usually a list of daily sleep objects
            all_sleep_records.extend(data)
        except Exception as e:
            print(f"Skipping {file_path} due to error: {e}")

# Sort records by date
all_sleep_records.sort(key=lambda x: x.get('calendarDate', ''))

# Generate Report
with open(output_file, 'w') as f:
    f.write("GARMIN CONSOLIDATED SLEEP REPORT\n")
    f.write("===============================\n\n")
    f.write(f"{'Date':<12} | {'Deep':<8} | {'REM':<8} | {'Light':<8} | {'Total'}\n")
    f.write("-" * 55 + "\n")

    for day in all_sleep_records:
        date = day.get('calendarDate', 'N/A')
        # Garmin uses seconds for these fields
        deep = day.get('deepSleepSeconds', 0)
        rem = day.get('remSleepSeconds', 0)
        light = day.get('lightSleepSeconds', 0)
        total = day.get('unmeasurableSeconds', 0) + deep + rem + light + day.get('awakeSleepSeconds', 0)
        
        f.write(f"{date:<12} | {format_seconds(deep):<8} | {format_seconds(rem):<8} | {format_seconds(light):<8} | {format_seconds(total)}\n")

print(f"Done! Summary saved to {output_file}")