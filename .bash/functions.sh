# Colormap
function colormap() {
  for i in {0..255}; do print -Pn "%K{$i}  %k%F{$i}${(l:3::0:)i}%f " ${${(M)$((i%6)):#3}:+$'\n'}; done
}

function dockerent() {
  sudo docker exec -it $1 /bin/bash
}

function dockerents() {
  sudo docker exec -it $1 /bin/sh
}

#!/bin/bash

# Function to perform Git Add, Commit, and Push.
# It requires one argument: the commit message.
#
# Usage: gacp "Your commit message here"
gacp() {
    # Check if the commit message ($1) is empty
    if [ -z "$1" ]; then
        echo "Error: You must provide a commit message."
        echo "Usage: gacp \"Your descriptive message\""
        return 1
    fi

    # 1. Add all changes
    echo "--> Running: git add ."
    git add .

    # Check if 'git add' was successful
    if [ $? -ne 0 ]; then
        echo "Error during 'git add'. Aborting."
        return 1
    fi

    # 2. Commit with the provided message
    local MESSAGE="$1"
    echo "--> Running: git commit -m \"$MESSAGE\""
    git commit -m "$MESSAGE"

    # Check if 'git commit' was successful
    if [ $? -ne 0 ]; then
        echo "Error during 'git commit'. Aborting."
        return 1
    fi

    # 3. Push to origin main
    # We use -u origin main to set the upstream, which simplifies future pushes
    echo "--> Running: git push -u origin main"
    git push -u origin main

    # Check if 'git push' was successful
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Changes committed and pushed to main."
    else
        echo "Error: Push failed. Check your connection or branch status."
        return 1
    fi
}

# Provide a helpful message when the script is sourced
echo "Function 'gacp' loaded. Use it like: gacp \"Initial commit\""

