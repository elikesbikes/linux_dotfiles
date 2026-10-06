#!/usr/bin/env bash
# Proton Pass secrets for Docker start.sh scripts - SOURCE this, then call pp_load:
#
#   source "$HOME/scripts/proton-pass/pass-secrets.sh"
#   pp_load restic "Starting restic" \
#       "RESTIC_PASSWORD|restic - RESTIC_PASSWORD|note" \
#       "?HASS_TOKEN|hermes - HASS_TOKEN|API Key"          # leading ? = optional (exported empty if missing)
#
# Exports each VAR from Proton Pass (vault $PP_VAULT, default HOMELAB) with this host's own PAT
# (TPM handle 0x81010001; ~/.secrets/proton-pass-pat only where a host still has it).
#
# Why it is built this way (2026-10-06): Proton rate-limits PAT logins (HTTP 429, code 2028 "Too many
# recent logins", Retry-After ~270 s); pass-cli silently waits that out, which looked like a hang. Every
# start used to log in, and retries made it worse. So:
#   1. A TPM-sealed cache (pass_cache.py, next to this file) younger than PP_FRESH_S (600 s) is used
#      WITHOUT logging in - restarts and multi-step deploys cost one login, not several.
#   2. Otherwise one login. A 429 / 2028 / timeout is never retried (each retry is another login).
#      Other errors get one retry.
#   3. If Proton cannot be used, the cache is used up to PP_MAX_AGE_S (7 days) old - loudly
#      ("degraded"). Older or missing: the start fails.
# Every outcome goes to syslog (tag proton-pass-load -> Graylog) and stderr; values never do.
# pass-cli's trace is piped through pass_trace.py (allow-list; raw trace carries Bearer tokens and the
# PAT) and kept only for failed or slow (>= 8 s) calls in ~/.local/state/proton-pass/debug (mode 600).
# Compromise runbook: delete ~/.local/state/proton-pass-cache on the host AND rotate its secrets;
# revoking the PAT alone does not invalidate the cache.

_PP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_pp_log() {  # _pp_log <outcome> <detail...>
  local msg="component=$_PP_COMPONENT outcome=$1 ${*:2}"
  logger -t proton-pass-load -- "$msg" 2>/dev/null || true
  echo "[proton-pass] $msg" >&2
}

_pp_attempts() { [ -s "$_PP_ATTEMPTS_FILE" ] && tr '\n' ' ' < "$_PP_ATTEMPTS_FILE" | sed 's/ $//'; return 0; }

_pp_pat() {
  local pat
  if command -v tpm2_unseal >/dev/null 2>&1 && pat="$(tpm2_unseal -c "${PP_TPM_HANDLE:-0x81010001}" 2>/dev/null)" \
     && [ -n "$pat" ]; then
    printf '%s' "$pat"; return 0
  fi
  if [ -r "${PP_PAT_FILE:-$HOME/.secrets/proton-pass-pat}" ]; then
    cat "${PP_PAT_FILE:-$HOME/.secrets/proton-pass-pat}"; return 0
  fi
  return 1
}

# One traced pass-cli call in this load's session: stdout passes through untouched (item values),
# stderr is filtered in the pipe into $_PP_ATTEMPT_LOG. Exit status is pass-cli's (124 = cap fired).
_pp_call() {  # _pp_call <step> <pass-cli args...>
  local step="$1" rc t0 ms; shift
  t0="${EPOCHREALTIME/./}"
  ( set -o pipefail
    { PROTON_PASS_SESSION_DIR="$_PP_SESSION" PROTON_PASS_AGENT_REASON="$_PP_REASON" \
      PROTON_PASS_KEY_PROVIDER=fs PROTON_PASS_NO_UPDATE_CHECK=1 PROTON_PASS_DISABLE_TELEMETRY=1 NO_COLOR=1 \
      PASS_LOG_LEVEL=info MUON_LOG_LEVEL=trace \
        timeout "${PP_ATTEMPT_TIMEOUT:-20}" "${PP_PASS_CLI:-$HOME/.local/bin/pass-cli}" "$@" 2>&1 1>&3 3>&- \
        | python3 "$_PP_DIR/pass_trace.py" > "$_PP_ATTEMPT_LOG"; } 3>&1 )
  rc=$?
  ms=$(( (${EPOCHREALTIME/./} - t0) / 1000 ))
  # Appended to a file: item reads run inside $(...), where a variable update would be lost.
  echo "$step:$rc/$((ms / 1000)).$(( (ms % 1000) / 100 ))" >> "$_PP_ATTEMPTS_FILE"
  if [ "$rc" != 0 ] || [ "$ms" -ge 8000 ]; then
    local dir="${PP_DEBUG_DIR:-$HOME/.local/state/proton-pass/debug}" f
    if mkdir -p -m 700 "$dir" 2>/dev/null; then
      f="$dir/$(date -u +%Y%m%dT%H%M%SZ)-$_PP_COMPONENT-$step-rc$rc-${ms}ms.log"
      { echo "# host=$(hostname -s) component=$_PP_COMPONENT step=$step rc=$rc ms=$ms attempts=$(_pp_attempts)"
        cat "$_PP_ATTEMPT_LOG"; } > "$f" 2>/dev/null && chmod 600 "$f"
      find "$dir" -maxdepth 1 -name '*.log' -mtime +14 -delete 2>/dev/null
    fi
  fi
  return "$rc"
}

# Proton refused or did not answer in time: retrying would only be another login against the limit.
_pp_rate_limited() {  # _pp_rate_limited <rc>
  [ "$1" = 124 ] || grep -qiE 'status: 429|2028|too many recent logins' "$_PP_ATTEMPT_LOG" 2>/dev/null
}

# Read a cache entry into _PP_VALUES (same order as _PP_VARS). 0 = all required present.
_pp_cache_read() {  # _pp_cache_read <max_age_s>
  local k v rc i
  local -A got=()
  while IFS= read -r -d '' k && IFS= read -r -d '' v; do got["$k"]="$v"; done \
    < <(python3 "$_PP_DIR/pass_cache.py" get "$_PP_COMPONENT" "$_PP_KEYSET" "$1" 2>/dev/null)
  wait $!; rc=$?
  [ "$rc" = 0 ] || { _PP_CACHE_RC=$rc; return 1; }
  _PP_VALUES=()
  for i in "${!_PP_VARS[@]}"; do
    [ -n "${got[${_PP_VARS[$i]}]+x}" ] || { _PP_CACHE_RC=3; return 1; }
    _PP_VALUES+=("${got[${_PP_VARS[$i]}]}")
  done
}

_pp_cache_write() {
  local i
  for i in "${!_PP_VARS[@]}"; do printf '%s\0%s\0' "${_PP_VARS[$i]}" "${_PP_VALUES[$i]}"; done \
    | python3 "$_PP_DIR/pass_cache.py" put "$_PP_COMPONENT" "$_PP_KEYSET" 2>/dev/null
}

# Log in once and read every item into _PP_VALUES. Sets _PP_WHY on failure.
_pp_from_proton() {
  local pat rc n=0 i value
  pat="$(_pp_pat)" || { _PP_WHY="no PAT (TPM unseal failed, no PAT file)"; return 1; }
  while :; do
    rm -rf "$_PP_SESSION"; mkdir -m 700 "$_PP_SESSION"
    PROTON_PASS_PERSONAL_ACCESS_TOKEN="$pat" _pp_call login login >/dev/null; rc=$?
    [ "$rc" = 0 ] && break
    if _pp_rate_limited "$rc"; then
      _PP_WHY="rate limited or no answer (rc=$rc; Proton 429/2028 or ${PP_ATTEMPT_TIMEOUT:-20}s cap)"; pat=""; return 1
    fi
    if [ "$n" -ge 1 ]; then
      _PP_WHY="login failed: $(grep -vE '^[0-9]{4}-' "$_PP_ATTEMPT_LOG" | tail -n 1 | cut -c1-160)"; pat=""; return 1
    fi
    n=$((n + 1)); sleep "${PP_RETRY_SLEEP:-3}"
  done
  pat=""
  _PP_VALUES=()
  for i in "${!_PP_VARS[@]}"; do
    n=0
    while :; do
      value="$(_pp_call "view-${_PP_VARS[$i]}" item view --vault-name "${PP_VAULT:-HOMELAB}" \
                 --item-title "${_PP_TITLES[$i]}" --field "${_PP_FIELDS[$i]}")"; rc=$?
      [ "$rc" = 0 ] && [ -n "$value" ] && break
      if [ "${_PP_OPT[$i]}" = 1 ] && [ "$rc" = 0 ]; then value=""; break; fi    # optional + empty
      if [ "$n" -ge 1 ]; then
        if [ "${_PP_OPT[$i]}" = 1 ]; then value=""; break; fi
        _PP_WHY="cannot read '${_PP_TITLES[$i]}' / ${_PP_FIELDS[$i]} for ${_PP_VARS[$i]}"; return 1
      fi
      n=$((n + 1)); sleep "${PP_RETRY_SLEEP:-3}"
    done
    _PP_VALUES+=("$value")
  done
}

# Callers are `set -euo pipefail` start.sh scripts. The body runs on the left of `||`, where bash
# suspends errexit, so an expected failure (a missing optional item, a refused login) is handled here
# instead of silently killing the start. The result still fails the caller when loading really failed.
pp_load() {  # pp_load <component> <reason> SPEC...   SPEC = "[?]VAR|item title|field"
  _pp_load_body "$@" || return 1
}

_pp_load_body() {
  _PP_COMPONENT="$1"; _PP_REASON="$2 on $(hostname -s)"; shift 2
  _PP_VARS=(); _PP_TITLES=(); _PP_FIELDS=(); _PP_OPT=(); _PP_VALUES=(); _PP_WHY=""; _PP_ATTEMPTS_FILE="/dev/null"
  _PP_CACHE_RC=0
  local spec var title field i rc=0 age
  for spec in "$@"; do
    IFS='|' read -r var title field <<< "$spec"
    if [[ "$var" == \?* ]]; then var="${var#\?}"; _PP_OPT+=(1); else _PP_OPT+=(0); fi
    [[ "$var" =~ ^[A-Z_][A-Z0-9_]*$ ]] && [ -n "$title" ] && [ -n "$field" ] \
      || { _pp_log failed "reason=bad-spec spec=${spec%%|*}"; return 1; }
    _PP_VARS+=("$var"); _PP_TITLES+=("$title"); _PP_FIELDS+=("$field")
  done
  _PP_KEYSET="$(printf '%s\n' "$@" | sha256sum | cut -c1-16)"

  if _pp_cache_read "${PP_FRESH_S:-600}"; then
    age="$(python3 "$_PP_DIR/pass_cache.py" age "$_PP_COMPONENT")"
    _pp_log ok "source=cache-fresh age=${age}s count=${#_PP_VARS[@]}"
  else
    _PP_SESSION="$(mktemp -d "${TMPDIR:-/tmp}/pp-session.XXXXXX")" || { _pp_log failed "reason=no-session-dir"; return 1; }
    _PP_ATTEMPT_LOG="$_PP_SESSION.attempt"; _PP_ATTEMPTS_FILE="$_PP_SESSION.attempts"; : > "$_PP_ATTEMPTS_FILE"
    _pp_from_proton; rc=$?
    PROTON_PASS_SESSION_DIR="$_PP_SESSION" timeout 10 "${PP_PASS_CLI:-$HOME/.local/bin/pass-cli}" logout >/dev/null 2>&1
    local attempts; attempts="$(_pp_attempts)"
    rm -rf "$_PP_SESSION" "$_PP_ATTEMPT_LOG" "$_PP_ATTEMPTS_FILE"; _PP_ATTEMPTS_FILE=/dev/null
    if [ "$rc" = 0 ]; then
      if _pp_cache_write; then :; else echo "[proton-pass] WARNING: could not refresh the TPM cache for $_PP_COMPONENT" >&2; fi
      _pp_log ok "source=proton count=${#_PP_VARS[@]} attempts=\"$attempts\""
    elif _pp_cache_read "${PP_MAX_AGE_S:-604800}"; then
      age="$(python3 "$_PP_DIR/pass_cache.py" age "$_PP_COMPONENT")"
      _pp_log degraded "source=cache age=${age}s reason=\"$_PP_WHY\" attempts=\"$attempts\""
    else
      _pp_log failed "reason=\"$_PP_WHY\" cache_rc=$_PP_CACHE_RC attempts=\"$attempts\""
      return 1
    fi
  fi
  for i in "${!_PP_VARS[@]}"; do export "${_PP_VARS[$i]}=${_PP_VALUES[$i]}"; done
  _PP_VALUES=()
}
