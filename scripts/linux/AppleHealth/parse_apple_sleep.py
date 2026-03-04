import xml.etree.ElementTree as ET
from collections import defaultdict
from datetime import datetime
import os

# Updated Paths
input_file = '/home/ecloaiza/Downloads/export/apple_health_export/export.xml'
output_file = '/home/ecloaiza/Downloads/export/apple_health_export/sleep_report.txt'

# Mapping both IDs and names to be safe
stage_map = {
    # String versions
    'HKCategoryValueSleepAnalysisAsleepREM': 'REM',
    'HKCategoryValueSleepAnalysisAsleepDeep': 'Deep',
    'HKCategoryValueSleepAnalysisAsleepCore': 'Core/Light',
    'HKCategoryValueSleepAnalysisAwake': 'Awake',
    'HKCategoryValueSleepAnalysisInBed': 'InBed',
    # Numeric versions (WatchOS 9+)
    '2': 'Awake',
    '3': 'Core/Light',
    '4': 'Deep',
    '5': 'REM'
}

stats = defaultdict(lambda: defaultdict(float))
found_any = False
record_count = 0

print(f"Opening {input_file}...")

if not os.path.exists(input_file):
    print(f"CRITICAL ERROR: File not found at {input_file}")
    exit()

try:
    context = ET.iterparse(input_file, events=('end',))
    
    for event, elem in context:
        if elem.tag == 'Record':
            record_type = elem.get('type')
            
            if record_type == 'HKCategoryTypeIdentifierSleepAnalysis':
                found_any = True
                record_count += 1
                
                val = elem.get('value')
                start_str = elem.get('startDate')
                end_str = elem.get('endDate')
                
                if val and start_str and end_str:
                    # Parse dates (stripping timezone for simplicity)
                    start_dt = datetime.strptime(start_str[:19], '%Y-%m-%d %H:%M:%S')
                    end_dt = datetime.strptime(end_str[:19], '%Y-%m-%d %H:%M:%S')
                    duration_mins = (end_dt - start_dt).total_seconds() / 60
                    
                    # Identify the stage
                    label = stage_map.get(val, f"Unknown({val})")
                    date_key = start_dt.strftime('%Y-%m-%d')
                    
                    stats[date_key][label] += duration_mins
        
        # Keep memory usage low
        elem.clear()

    if not found_any:
        print("!! No Sleep Records found. checking if the tag names are different...")
    else:
        print(f"Processed {record_count} sleep records.")
        with open(output_file, 'w') as f:
            f.write("APPLE HEALTH SLEEP STAGES REPORT\n")
            f.write("===============================\n\n")
            # Sort by date descending
            for date in sorted(stats.keys(), reverse=True):
                f.write(f"DATE: {date}\n")
                day_data = stats[date]
                for stage in ['Deep', 'REM', 'Core/Light', 'Awake', 'InBed']:
                    if stage in day_data:
                        f.write(f"  {stage:12}: {day_data[stage]/60:.2f} hrs\n")
                f.write("-" * 25 + "\n")
        
        print(f"SUCCESS! Report created at: {output_file}")

except Exception as e:
    print(f"An error occurred during parsing: {e}")