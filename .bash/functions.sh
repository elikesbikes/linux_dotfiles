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


# Function to perform Git Pull on the current branch.
# This fetches and merges changes from the remote tracking branch, refreshing the local copy.
#
# Usage: gpull
gpull() {
    echo "--> Running: git pull"
    git pull

    # Check if 'git pull' was successful
    if [ $? -eq 0 ]; then
        echo "SUCCESS: Local copy refreshed with changes from remote."
    else
        echo "Error: Pull failed. Check your connection, or you may need to resolve conflicts. Consider running 'gstash' first."
        return 1
    fi
}


# Function to perform Git Add, Commit, and then Pull.
# It requires one argument: the commit message.
# This is ideal when local changes are ready, and you need to sync before pushing.
#
# Usage: gcap "Your pre-pull commit message"
gcap() {
    echo "Starting Commit and Pull sequence (gcap)..."

    if [ -z "$1" ]; then
        echo "Error: You must provide a commit message."
        echo "Usage: gcap \"Your descriptive message\""
        return 1
    fi

    # --- 1. COMMIT LOCAL CHANGES ---
    # Add changes
    echo "--> Running: git add ."
    git add .
    if [ $? -ne 0 ]; then
        echo "Error during 'git add'. Aborting."
        return 1
    fi

    # Commit
    local MESSAGE="$1"
    echo "--> Running: git commit -m \"$MESSAGE\""
    git commit -m "$MESSAGE"
    if [ $? -ne 0 ]; then
        echo "Error during 'git commit'. Aborting pull."
        return 1
    fi
    echo "SUCCESS: Local changes committed."

    # --- 2. PULL REMOTE CHANGES ---
    echo ""
    echo "Starting Pull operation to synchronize with remote..."
    echo "--> Running: git pull"
    git pull

    if [ $? -eq 0 ]; then
        echo "SUCCESS: Remote changes pulled and merged into local branch."
    else
        echo "Warning: Pull failed after commit. You may have conflicts to resolve now. Run 'git status' for details."
        return 1
    fi
}

# Provide a helpful message when the script is sourced
echo "Git functions loaded: 'gacp' (Add, Commit, Push), 'gpull' (Pull/Refresh), and 'gcap' (Commit/Pull sequence)."
