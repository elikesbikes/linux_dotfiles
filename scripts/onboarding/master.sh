#!/bin/bash

echo "Starting master installation..."

# Define the directory where child scripts are located
SCRIPT_DIR="./install-scripts"

# Check if the script directory exists
if [ ! -d "$SCRIPT_DIR" ]; then
  echo "Error: Directory $SCRIPT_DIR not found."
  echo "Please create it and add the installation scripts."
  exit 1
fi

# Loop through and execute each script in the directory
# Using 'find' is robust, even if scripts have spaces (though ours don't)
find "$SCRIPT_DIR" -type f -name "install_*.sh" | while read script; do
  # Make sure the script is executable
  if [ ! -x "$script" ]; then
    echo "Making $script executable..."
    chmod +x "$script"
  fi

  # Run the script
  echo ""
  echo "--- Running $script ---"
  "$script"
  echo "--- Finished $script ---"
done

echo ""
echo "Master installation finished."
