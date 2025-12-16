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
gacp_tutorials() {
  # 1. Save current directory and go to the target directory
  # 'pushd' saves your current location to a stack and then cds
  # We send the normal output to /dev/null to keep it quiet
  pushd /home/ecloaiza/DevOps/GitHub/tutorials > /dev/null

  # 2. Run the command with all provided arguments
  # "$@" is a special variable that passes all arguments
  # (e.g., your commit message) to the 'gacp' command
  gacp "$@"

  # 3. Return to the original directory
  # 'popd' takes you back to the directory 'pushd' saved
  popd > /dev/null
}
gacp_dotfiles() {
  # 1. Save current directory and go to the target directory
  pushd /home/ecloaiza/DevOps/GitHub/linux_dotfiles > /dev/null

  # 2. Run the command with all provided arguments
  gacp "$@"

  # 3. Return to the original directory
  popd > /dev/null
}
gcpp_dotfiles() {
  # 1. Save current directory and go to the target directory
  pushd /home/ecloaiza/DevOps/GitHub/linux_dotfiles > /dev/null

  # 2. Run the command with all provided arguments
  gcpp "$@"

  # 3. Return to the original directory
  popd > /dev/null
}

# Function to perform Git Add, Commit, Pull, and then Push.
# This is the "safe push" function.
# It requires one argument: the commit message.
# 1. Commits local changes
# 2. Pulls remote changes to sync
# 3. Pushes the final merged result
#
# Usage: gcpp "Your commit message"
gcpp() {
    echo "Starting Commit, Pull, Push sequence (gcpp)..."

    if [ -z "$1" ]; then
        echo "Error: You must provide a commit message."
        echo "Usage: gcpp \"Your descriptive message\""
        return 1
    fi

    # --- 1. COMMIT LOCAL CHANGES ---
    # Add changes
    echo "--> (1/3) Adding changes..."
    git add .
    if [ $? -ne 0 ]; then
        echo "Error during 'git add'. Aborting."
        return 1
    fi

    # Commit
    local MESSAGE="$1"
    echo "--> (1/3) Committing changes..."
    git commit -m "$MESSAGE"
    if [ $? -ne 0 ]; then
        echo "Error during 'git commit'. Aborting pull/push."
        return 1
    fi
    echo "SUCCESS: Local changes committed."

    # --- 2. PULL REMOTE CHANGES ---
    echo ""
    echo "--> (2/3) Starting Pull operation to synchronize with remote..."
    git pull

    if [ $? -ne 0 ]; then
        echo "Error: Pull failed after commit. You may have conflicts to resolve now."
        echo "Please resolve conflicts, then run 'git push' manually."
        return 1
    fi
    echo "SUCCESS: Remote changes pulled and merged into local branch."

    # --- 3. PUSH MERGED CHANGES ---
    echo ""
    echo "--> (3/3) Pushing final merged changes to main..."
    git push -u origin main

    if [ $? -eq 0 ]; then
        echo "SUCCESS: Commit, Pull, and Push complete!"
    else
        echo "Error: Push failed after a successful pull. Check your connection or permissions."
        return 1
    fi
}


# Function: sshk
# Description: Runs a pre-connection command (optional) and then initiates
#              an SSH session using kitty +kitten ssh for terminfo compatibility.
# Usage: sshk username host [pre_command]

sshk() {
    # Check if correct number of arguments are provided
    if [ "$#" -lt 2 ]; then
        echo "Usage: sshk <username> <host> [pre_command]"
        echo "Example: sshk user1 myhost.com 'echo Running pre-command...'"
        return 1
    fi

    local USERNAME="$1"
    local HOST="$2"
    local PRE_COMMAND="$3"

    echo "--- Preparing SSH Connection ---"

    # 1. Execute optional pre-command
    if [ -n "$PRE_COMMAND" ]; then
        echo "Executing pre-command: $PRE_COMMAND"
        eval "$PRE_COMMAND"
        if [ $? -ne 0 ]; then
            echo "Error executing pre-command. Aborting."
            return 1
        fi
        echo "Pre-command finished."
    fi

    # 2. Initiate the Kitty SSH connection
    echo "Starting SSH session to $USERNAME@$HOST using kitty +kitten..."
    kitty +kitten ssh "${USERNAME}@${HOST}"
}
# Function to perform Git Pull on the linux_dotfiles repository
# while preserving the caller's current directory.
#
# Usage: gpull_dotfiles
gpull_dotfiles() {
  # 1. Save current directory and go to the dotfiles repo
  pushd /home/ecloaiza/devops/github/linux_dotfiles > /dev/null

  # 2. Pull latest changes
  gpull

  # 3. Return to the original directory
  popd > /dev/null
}

# Function: sshe
# Description: SSH into a host as user 'ecloaiza' using kitty +kitten ssh.
#              Optionally runs a pre-command before connecting.
# Usage: sshe <host> [pre_command]

sshe() {
    # Check if correct number of arguments are provided
    if [ "$#" -lt 1 ]; then
        echo "Usage: sshe <host> [pre_command]"
        echo "Example: sshe myhost.com 'echo Running pre-command...'"
        return 1
    fi

    local USERNAME="ecloaiza"
    local HOST="$1"
    local PRE_COMMAND="$2"

    echo "--- Preparing SSH Connection ---"

    # 1. Execute optional pre-command
    if [ -n "$PRE_COMMAND" ]; then
        echo "Executing pre-command: $PRE_COMMAND"
        eval "$PRE_COMMAND"
        if [ $? -ne 0 ]; then
            echo "Error executing pre-command. Aborting."
            return 1
        fi
        echo "Pre-command finished."
    fi

    # 2. Initiate the Kitty SSH connection
    echo "Starting SSH session to ${USERNAME}@${HOST} using kitty +kitten..."
    kitty +kitten ssh "${USERNAME}@${HOST}"
}
# Function to perform Git Pull on the tutorials repository
# while preserving the caller's current directory.
#
# Usage: gpull_tutorials
gpull_tutorials() {
  # 1. Save current directory and go to the tutorials repo
  pushd /home/ecloaiza/DevOps/GitHub/tutorials > /dev/null

  # 2. Pull latest changes
  gpull

  # 3. Return to the original directory
  popd > /dev/null
}


# Provide a helpful message when the script is sourced
echo "Git functions loaded: 'gacp' (Add, Commit, Push), 'gpull' (Pull/Refresh), and 'gcpp' (Commit, Pull, Push)."
