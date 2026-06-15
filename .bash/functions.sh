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

    echo "--> Running: git pull --rebase origin main"
    git pull --rebase origin main || {
        echo "ERROR: Rebase failed. Resolve conflicts, then run 'git rebase --continue'."
        return 1
    }

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
# repo, pushes it, and optionally triggers a GitLab deploy.
#
# Usage:
#   gacp_tutorials_wcopy <project> "Commit message" [host]
#
#   host: ranger0 | endurance | all   (omit to push only)
#
# Examples:
#   gacp_tutorials_wcopy restic "update config"
#   gacp_tutorials_wcopy restic "update config" ranger0
#   gacp_tutorials_wcopy restic "update config" all
# ------------------------------------------------------------
gacp_tutorials_wcopy() {
  local PROJECT_NAME="$1"
  local COMMIT_MSG="$2"
  local DEPLOY_HOST="${3:-}"

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

  echo "Copying filtered files (.yml, .py, .sh, .md) to destination..."

  mkdir -p "${DEST_PATH}"

  rsync -am \
    --exclude="logs/" \
    --exclude=".env" \
    --exclude="backup/" \
    --exclude="*.conf" \
    --exclude="docker-compose.override.yml" \
    --exclude="certs/" \
    --exclude="acme.json" \
    --exclude="dashboard.yaml" \
    --exclude="secrets/" \
    --exclude="*.htpasswd" \
    --include="*/" \
    --include="*.yml" \
    --include="*.yaml" \
    --include="*.py" \
    --include="*.sh" \
    --include="*.[mM][dD]" \
    --include="*.json" \
    --include="*.example" \
    --include="*.png" \
    --include="*.txt" \
    --exclude="*" \
    "${SRC_PATH}/" \
    "${DEST_PATH}/"

  pushd "${TUTORIALS_ROOT}" > /dev/null || return 1
  gacp "${COMMIT_MSG}"
  local PUSH_STATUS=$?
  local PUSHED_SHA
  PUSHED_SHA=$(git rev-parse HEAD)
  popd > /dev/null

  if [[ $PUSH_STATUS -ne 0 ]]; then
    return $PUSH_STATUS
  fi

  if [[ -n "${DEPLOY_HOST}" ]]; then
    _gitlab_deploy_tutorials "${PROJECT_NAME}" "${DEPLOY_HOST}" "${PUSHED_SHA}"
  fi
}

# ------------------------------------------------------------
# _gitlab_deploy_tutorials  (internal helper)
# ------------------------------------------------------------
# Polls for the GitLab pipeline triggered by a push SHA, then
# plays the deploy job(s) for the requested host(s).
# Requires GITLAB_URL and GITLAB_TOKEN from ~/.secrets/gitlab
# ------------------------------------------------------------
_gitlab_deploy_tutorials() {
  local PROJECT="$1"
  local HOST="$2"
  local SHA="$3"
  local GL_URL="${GITLAB_URL:-https://gitlab.home.elikesbikes.com}"
  local GL_PROJECT="ecloaiza%2Ftutorials"
  local TOKEN="${GITLAB_TOKEN:-}"

  if [[ -z "${TOKEN}" ]]; then
    echo "ERROR: GITLAB_TOKEN not set — source ~/.secrets/gitlab or set it manually"
    return 1
  fi

  local JOB_NAMES=()
  case "${HOST}" in
    ranger0)       JOB_NAMES=("deploy:ranger0") ;;
    endurance)     JOB_NAMES=("deploy:endurance") ;;
    docker-prod-1) JOB_NAMES=("deploy:docker-prod-1") ;;
    ranger1)       JOB_NAMES=("deploy:ranger1") ;;
    all)           JOB_NAMES=("deploy:ranger0" "deploy:endurance" "deploy:docker-prod-1" "deploy:ranger1") ;;
    *)
      echo "ERROR: Unknown host '${HOST}'. Use ranger0, endurance, docker-prod-1, ranger1, or all"
      return 1
      ;;
  esac

  echo "Waiting for pipeline (SHA ${SHA:0:8})..."
  local PIPELINE_ID=""
  local i
  for i in $(seq 1 15); do
    PIPELINE_ID=$(curl -sf "${GL_URL}/api/v4/projects/${GL_PROJECT}/pipelines?sha=${SHA}" \
      -H "PRIVATE-TOKEN: ${TOKEN}" \
      | python3 -c "import sys,json;d=json.load(sys.stdin);print(d[0]['id'] if d else '')" 2>/dev/null)
    if [[ -n "${PIPELINE_ID}" ]]; then
      echo "Pipeline #${PIPELINE_ID} created"
      break
    fi
    sleep 3
  done

  if [[ -z "${PIPELINE_ID}" ]]; then
    echo "ERROR: No pipeline appeared after 45s for SHA ${SHA}"
    return 1
  fi

  for JOB_NAME in "${JOB_NAMES[@]}"; do
    local JOB_ID=""
    for i in $(seq 1 8); do
      JOB_ID=$(curl -sf "${GL_URL}/api/v4/projects/${GL_PROJECT}/pipelines/${PIPELINE_ID}/jobs" \
        -H "PRIVATE-TOKEN: ${TOKEN}" \
        | python3 -c "
import sys,json
jobs=json.load(sys.stdin)
match=[x for x in jobs if x['name']=='${JOB_NAME}']
print(match[0]['id'] if match else '')
" 2>/dev/null)
      [[ -n "${JOB_ID}" ]] && break
      sleep 3
    done

    if [[ -z "${JOB_ID}" ]]; then
      echo "ERROR: Job '${JOB_NAME}' not found in pipeline #${PIPELINE_ID}"
      continue
    fi

    # Trigger the job. A manual deploy job reports status 'manual' from
    # the moment the pipeline is created — even while earlier stages are
    # still running — so the status field can't tell us when it's ready.
    # Playing too early returns 400 "Unplayable Job". So we just retry
    # /play until it succeeds (or an earlier stage fails the job).
    local PLAY_RESULT="" PLAYED=0
    for i in $(seq 1 20); do
      # Stop early if an earlier stage failed and skipped this job.
      local JOB_STATUS
      JOB_STATUS=$(curl -sf "${GL_URL}/api/v4/projects/${GL_PROJECT}/jobs/${JOB_ID}" \
        -H "PRIVATE-TOKEN: ${TOKEN}" \
        | python3 -c "import sys,json;print(json.load(sys.stdin).get('status',''))" 2>/dev/null)
      case "${JOB_STATUS}" in
        failed|canceled|skipped)
          echo "ERROR: ${JOB_NAME} not playable (status: ${JOB_STATUS}) — an earlier stage likely failed"
          break ;;
        pending|running|success)
          PLAYED=1; break ;;
      esac

      PLAY_RESULT=$(curl -s -X POST "${GL_URL}/api/v4/projects/${GL_PROJECT}/jobs/${JOB_ID}/play" \
        -H "PRIVATE-TOKEN: ${TOKEN}" \
        | python3 -c "import sys,json;d=json.load(sys.stdin);print(d.get('status') or d.get('message') or '')" 2>/dev/null)
      case "${PLAY_RESULT}" in
        pending|running|created)
          PLAYED=1; break ;;
      esac
      sleep 3
    done

    if [[ "${PLAYED}" -eq 1 ]]; then
      echo "Triggered ${JOB_NAME} (job #${JOB_ID})"
      echo "  ${GL_URL}/ecloaiza/tutorials/-/jobs/${JOB_ID}"
    else
      echo "ERROR: Failed to trigger ${JOB_NAME} (job #${JOB_ID}) — last result: ${PLAY_RESULT:-${JOB_STATUS:-unknown}}"
      echo "  ${GL_URL}/ecloaiza/tutorials/-/jobs/${JOB_ID}"
    fi
  done
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
  # Assuming gpull is a defined alias or function in your environment
  gpull 
  popd > /dev/null

  echo "Copying filtered files (.yml, .py, .sh):"
  echo "  Source      : ${SRC_PATH}"
  echo "  Destination : ${DEST_PATH}"

  mkdir -p "${DEST_PATH}"

  # -a: archive mode
  # -m: prune empty directories (doesn't copy folders that end up empty)
  # include "*/" allows rsync to recurse into subdirectories
  rsync -am \
    --include="*/" \
    --include="*.yml" \
    --include="*.py" \
    --include="*.sh" \
    --include="*.[mM][dD]" \
    --exclude="*" \
    "${SRC_PATH}/" \
    "${DEST_PATH}/"
}

# ------------------------------------------------------------
# gacp_homelab
# ------------------------------------------------------------
# Runs the gacp workflow inside the homelab repository.
# Optionally supports creating and pushing an annotated Git tag.
#
# Usage:
#   gacp_homelab "Commit message"
#   gacp_homelab --tag v1.0.1 "Commit message"
# ------------------------------------------------------------
gacp_homelab() {
    local TAG=""
    local MESSAGE=""

    # Argument handling for optional tagging
    if [ "$1" = "--tag" ]; then
        TAG="$2"
        MESSAGE="$3"
    else
        MESSAGE="$1"
    fi

    # Validation: Ensure a message is provided
    if [ -z "$MESSAGE" ]; then
        echo "Error: Commit message is required."
        return 1
    fi

    # Navigate to the homelab directory
    if ! pushd /home/ecloaiza/devops/github/homelab > /dev/null; then
        echo "Error: homelab repo path not found."
        return 1
    fi

    # Execute the core gacp workflow
    gacp "$MESSAGE" || {
        popd > /dev/null
        return 1
    }

    # Handle optional tagging logic
    if [ -n "$TAG" ]; then
        echo "--> Creating annotated tag: $TAG"
        git tag -a "$TAG" -m "$MESSAGE" && git push origin "$TAG" || {
            popd > /dev/null
            return 1
        }
    fi

    # Return to the original directory
    popd > /dev/null
}
clone_tutorials() {
    local base_dir="/home/ecloaiza/devops/github"
    local tutorials_dir="$base_dir/tutorials"

    # Check if tutorials directory exists and delete it
    if [ -d "$tutorials_dir" ]; then
        echo "Tutorials directory exists. Deleting $tutorials_dir..."
        rm -rf "$tutorials_dir"
    else
        echo "Tutorials directory doesn't exist."
    fi

    # Create base directory if it doesn't exist
    if [ ! -d "$base_dir" ]; then
        echo "Creating $base_dir..."
        mkdir -p "$base_dir"
    fi

    # Change to the base directory
    cd "$base_dir" || return 1

    # Clone the repository
    echo "Cloning repository..."
    git clone https://github.com/elikesbikes/tutorials.git
}



echo "Git helper functions loaded (gacp, gcap, gcpp, dotfiles, tutorials, ssh)."
