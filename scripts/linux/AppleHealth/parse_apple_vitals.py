import xml.etree.ElementTree as ET
from collections import defaultdict
import os

# Paths
input_file = '/home/ecloaiza/Downloads/export/apple_health_export/export.xml'
output_file = '/home/ecloaiza/Downloads/export/apple_health_export/vitals_report.txt'

# Data structures to hold our values
rhr_data = defaultdict(list)
hrv_data = defaultdict(list)

print(f"Analyzing vitals in {input_file}...")

if not os.path.exists(input_file):
    print(f"Error: {input_file} not found.")
    exit()

try:
    # Using iterparse for the 3GB file
    context = ET.iterparse(input_file, events=('end',))
    
    for event, elem in context:
        if elem.tag == 'Record':
            record_type = elem.get('type')
            date = elem.get('startDate')[:10] # Get YYYY-MM-DD
            val = elem.get('value')

            if val:
                if record_type == 'HKQuantityTypeIdentifierRestingHeartRate':
                    rhr_data[date].append(float(val))
                elif record_type == 'HKQuantityTypeIdentifierHeartRateVariabilitySDNN':
                    hrv_data[date].append(float(val))
        
        # Memory management
        elem.clear()

    # Write the summary
    all_dates = sorted(set(list(rhr_data.keys()) + list(hrv_data.keys())), reverse=True)
    
    with open(output_file, 'w') as f:
        f.write("APPLE HEALTH VITALS REPORT (RHR & HRV)\n")
        f.write("======================================\n")
        f.write(f"{'Date':<12} | {'Avg RHR (BPM)':<15} | {'Avg HRV (ms)':<12}\n")
        f.write("-" * 45 + "\n")

        for d in all_dates:
            avg_rhr = sum(rhr_data[d])/len(rhr_data[d]) if d in rhr_data else 0
            avg_hrv = sum(hrv_data[d])/len(hrv_data[d]) if d in hrv_data else 0
            
            rhr_str = f"{avg_rhr:>13.1f}" if avg_rhr > 0 else f"{'N/A':>13}"
            hrv_str = f"{avg_hrv:>12.1f}" if avg_hrv > 0 else f"{'N/A':>12}"
            
            f.write(f"{d:<12} | {rhr_str} | {hrv_str}\n")

    print(f"Done! Report saved to {output_file}")

except Exception as e:
    print(f"An error occurred: {e}")
