#!/bin/bash
#
# ------------------------------------------------------------
# Git, Docker, and SSH Helper Functions
# ------------------------------------------------------------
# This file defines a set of interactive shell functions used for:
#
# - Git workflows (add / commit / pull / push)
# - Repository-specific wrappers (dotfiles, tutorials)
# - Optional Git tagging during commits
# - Docker container shell access
# - SSH convenience wrappers using kitty +kitten
#
# These functions are intended to be *sourced* into an interactive
# shell (e.g., from ~/.bashrc or ~/.bash_functions), not executed
# directly as a script.
# ------------------------------------------------------------


# ------------------------------------------------------------
# colormap
# ------------------------------------------------------------
# Prints a 256-color palette to the terminal.
# Useful for testing terminal color support and themes.
# ------------------------------------------------------------
function colormap() {
  for i in {0..255}; do
    print -Pn "%K{$i}  %k%F{$i}${(l:3::0:)i}%f " \
      ${${(M)$((i%6)):#3}:+$'\n'}
  done
}


# ------------------------------------------------------------
# dockerent
# ------------------------------------------------------------
# Opens an interactive Bash shell inside a running Docker container.
#
# Usage:
#   dockerent <container_name_or_id>
# ------------------------------------------------------------
function dockerent() {
  sudo docker exec -it "$1" /bin/bash
}


# ------------------------------------------------------------
# dockerents
# ------------------------------------------------------------
# Opens an interactive SH shell inside a running Docker container.
# Useful for minimal containers that do not include bash.
#
# Usage:
#   dockerents <container_name_or_id>
# ------------------------------------------------------------
function dockerents() {
  sudo docker exec -it "$1" /bin/sh
}


# ------------------------------------------------------------
# gacp
# ------------------------------------------------------------
# Performs a standard Git workflow:
#   1. git add .
#   2. git commit -m "<message>"
#   3. git push -u origin main
#
# This is the core primitive used by other wrapper functions.
#
# Usage:
#   gacp "Commit message"
# ------------------------------------------------------------
gacp() {
    if [ -z "$1" ]; then
        echo "Error: You must provide a commit message."
        echo "Usage: gacp \"Your descriptive message\""
        return 1
    fi

    echo "--> Running: git add ."
    git add . || return 1

    local MESSAGE="$1"
    echo "--> Running: git commit -m \"$MESSAGE\""
    git commit -m "$MESSAGE" || return 1

    echo "--> Running: git push -u origin main"
    git push -u origin main || return 1

    echo "SUCCESS: Changes committed and pushed to main."
}


# ------------------------------------------------------------
# gpull
# ------------------------------------------------------------
# Pulls the latest changes from the remote tracking branch
# into the current branch.
#
# Usage:
#   gpull
# ------------------------------------------------------------
gpull() {
    echo "--> Running: git pull"
    git pull || {
      echo "Error: Pull failed. Resolve conflicts if needed."
      return 1
    }
    echo "SUCCESS: Local copy refreshed with remote changes."
}


# ------------------------------------------------------------
# gcap
# ------------------------------------------------------------
# Commits local changes and then pulls remote changes.
# Useful when you want to save work before syncing.
#
# Usage:
#   gcap "Commit message"
# ------------------------------------------------------------
gcap() {
    if [ -z "$1" ]; then
        echo "Error: You must provide a commit message."
        return 1
    fi

    echo "--> Running: git add ."
    git add . || return 1

    local MESSAGE="$1"
    echo "--> Running: git commit -m \"$MESSAGE\""
    git commit -m "$MESSAGE" || return 1

    echo "--> Running: git pull"
    git pull || return 1

    echo "SUCCESS: Commit and pull complete."
}


# ------------------------------------------------------------
# gacp_tutorials
# ------------------------------------------------------------
# Runs the standard gacp workflow inside the tutorials repository,
# while preserving the caller’s original directory.
#
# Usage:
#   gacp_tutorials "Commit message"
# ------------------------------------------------------------
gacp_tutorials() {
  pushd /home/ecloaiza/devops/github/tutorials > /dev/null || return 1
  gacp "$@"
  popd > /dev/null
}


# ------------------------------------------------------------
# gacp_dotfiles
# ------------------------------------------------------------
# Runs the gacp workflow inside the linux_dotfiles repository.
# Optionally supports creating and pushing an annotated Git tag.
#
# Usage:
#   gacp_dotfiles "Commit message"
#   gacp_dotfiles --tag v1.0.1 "Commit message"
#
# Tagging is explicit and optional.
# ------------------------------------------------------------
gacp_dotfiles() {
  local TAG=""
  local MESSAGE=""

  if [ "$1" = "--tag" ]; then
    TAG="$2"
    MESSAGE="$3"
  else
    MESSAGE="$1"
  fi

  if [ -z "$MESSAGE" ]; then
    echo "Error: Commit message is required."
    return 1
  fi

  if ! pushd /home/ecloaiza/devops/github/linux_dotfiles > /dev/null; then
    echo "Error: dotfiles repo path not found."
    return 1
  fi

  gacp "$MESSAGE" || {
    popd > /dev/null
    return 1
  }

  if [ -n "$TAG" ]; then
    echo "--> Creating annotated tag: $TAG"
    git tag -a "$TAG" -m "$MESSAGE" || {
      popd > /dev/null
      return 1
    }

    echo "--> Pushing tag: $TAG"
    git push origin "$TAG" || {
      popd > /dev/null
      return 1
    }

    echo "SUCCESS: Tag '$TAG' created and pushed."
  fi

  popd > /dev/null
}


# ------------------------------------------------------------
# gcpp
# ------------------------------------------------------------
# Safe Git workflow:
#   1. Commit local changes
#   2. Pull remote changes
#   3. Push merged result
#
# Usage:
#   gcpp "Commit message"
# ------------------------------------------------------------
gcpp() {
    if [ -z "$1" ]; then
        echo "Error: Commit message required."
        return 1
    fi

    local MESSAGE="$1"

    git add . || return 1
    git commit -m "$MESSAGE" || return 1
    git pull || return 1
    git push -u origin main || return 1

    echo "SUCCESS: Commit, pull, and push complete."
}


# ------------------------------------------------------------
# sshk
# ------------------------------------------------------------
# SSH helper that optionally runs a pre-command and then
# opens a kitty +kitten ssh session.
#
# Usage:
#   sshk <username> <host> [pre_command]
# ------------------------------------------------------------
sshk() {
    if [ "$#" -lt 2 ]; then
        echo "Usage: sshk <username> <host> [pre_command]"
        return 1
    fi

    local USERNAME="$1"
    local HOST="$2"
    local PRE_COMMAND="$3"

    if [ -n "$PRE_COMMAND" ]; then
        eval "$PRE_COMMAND" || return 1
    fi

    kitty +kitten ssh "${USERNAME}@${HOST}"
}


# ------------------------------------------------------------
# gpull_dotfiles
# ------------------------------------------------------------
# Pulls the latest changes in the linux_dotfiles repository
# while preserving the caller’s current directory.
#
# Usage:
#   gpull_dotfiles
# ------------------------------------------------------------
gpull_dotfiles() {
  pushd /home/ecloaiza/devops/github/linux_dotfiles > /dev/null || return 1
  gpull
  popd > /dev/null
}


# ------------------------------------------------------------
# sshe
# ------------------------------------------------------------
# SSH helper that always connects as user 'ecloaiza'.
# Optionally runs a pre-command before connecting.
#
# Usage:
#   sshe <host> [pre_command]
# ------------------------------------------------------------
sshe() {
    if [ "$#" -lt 1 ]; then
        echo "Usage: sshe <host> [pre_command]"
        return 1
    fi

    local HOST="$1"
    local PRE_COMMAND="$2"

    if [ -n "$PRE_COMMAND" ]; then
        eval "$PRE_COMMAND" || return 1
    fi

    kitty +kitten ssh "ecloaiza@${HOST}"
}


# ------------------------------------------------------------
# gpull_tutorials
# ------------------------------------------------------------
# Pulls the latest changes in the tutorials repository
# while preserving the caller’s current directory.
#
# Usage:
#   gpull_tutorials
# ------------------------------------------------------------
gpull_tutorials() {
  pushd /home/ecloaiza/devops/github/tutorials > /dev/null || return 1
  gpull
  popd > /dev/null
}

# ------------------------------------------------------------
# gacp_tutorials_wcopy
# ------------------------------------------------------------
# Copies a docker project from devops/docker into the tutorials
# repo and runs gacp.
#
# Source:
#   /home/ecloaiza/devops/docker/<project>
#
# Destination:
#   tutorials/docker-compose/<project>
#
# Usage:
#   gacp_tutorials_wcopy <project> "Commit message"
# ------------------------------------------------------------
gacp_tutorials_wcopy() {
  local PROJECT_NAME="$1"
  shift || true

  if [[ -z "${PROJECT_NAME}" ]]; then
    echo "ERROR: Project name is required"
    return 1
  fi

  local SRC_PATH="/home/ecloaiza/devops/docker/${PROJECT_NAME}"
  local TUTORIALS_ROOT="/home/ecloaiza/devops/github/tutorials"
  local DEST_PATH="${TUTORIALS_ROOT}/docker-compose/${PROJECT_NAME}"

  if [[ ! -d "${SRC_PATH}" ]]; then
    echo "ERROR: Source project does not exist: ${SRC_PATH}"
    return 1
  fi

  echo "Copying project:"
  echo "  Source      : ${SRC_PATH}"
  echo "  Destination : ${DEST_PATH}"

  mkdir -p "${DEST_PATH}"

  rsync -a --delete \
    --exclude=".git" \
    "${SRC_PATH}/" \
    "${DEST_PATH}/"

  pushd "${TUTORIALS_ROOT}" > /dev/null || return 1
  gacp "$@"
  popd > /dev/null
}

# ------------------------------------------------------------
# gpull_tutorials_wcopy
# ------------------------------------------------------------
# Pulls latest changes in the tutorials repo and copies a
# docker-compose project back into the devops/docker workspace.
#
# Source:
#   tutorials/docker-compose/<project>
#
# Destination:
#   /home/ecloaiza/devops/docker/<project>
#
# Usage:
#   gpull_tutorials_wcopy <project>
# ------------------------------------------------------------
gpull_tutorials_wcopy() {
  local PROJECT_NAME="$1"

  if [[ -z "${PROJECT_NAME}" ]]; then
    echo "ERROR: Project name is required"
    return 1
  fi

  local TUTORIALS_ROOT="/home/ecloaiza/devops/github/tutorials"
  local SRC_PATH="${TUTORIALS_ROOT}/docker-compose/${PROJECT_NAME}"
  local DEST_PATH="/home/ecloaiza/devops/docker/${PROJECT_NAME}"

  if [[ ! -d "${SRC_PATH}" ]]; then
    echo "ERROR: Source project does not exist: ${SRC_PATH}"
    return 1
  fi

  pushd "${TUTORIALS_ROOT}" > /dev/null || return 1
  gpull
  popd > /dev/null

  echo "Copying project:"
  echo "  Source      : ${SRC_PATH}"
  echo "  Destination : ${DEST_PATH}"

  mkdir -p "${DEST_PATH}"

  rsync -a --delete \
    --exclude=".git" \
    "${SRC_PATH}/" \
    "${DEST_PATH}/"
}


echo "Git helper functions loaded (gacp, gcap, gcpp, dotfiles, tutorials, ssh)."
