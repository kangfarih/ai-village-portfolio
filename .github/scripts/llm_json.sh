#!/usr/bin/env bash
#
# llm_json.sh — shared LLM JSON client for the agentic loop.
#
# Posts a chat-completion request, retries transport failures with jittered
# backoff, validates the reply against a jq boolean schema, and performs ONE
# semantic correction retry before giving up loudly (NO silent fallback).
#
# Usage:
#   llm_json.sh --system-file SYS --user-file USER --out OUT \
#               --schema '<JQ_BOOL_FILTER>' [--effort low|medium|high] [--max-tokens N]
#
# Env:
#   OPENCODE_API_KEY      (required) bearer token; never logged
#   MODEL                 default thinkingmachines/inkling:free
#   OPENROUTER_ENDPOINT   default https://openrouter.ai/api/v1/chat/completions
#   LLM_MAX_ATTEMPTS      default 3
#   LLM_BACKOFF           default "5 15 45" seconds, indexed by attempt
#   LLM_REASONING_EFFORT  explicit override; when SET (even to "") it wins over
#                         --effort and an empty value disables reasoning_effort
#
# Exit 0 only after writing schema-valid JSON to --out. Every failure path
# prints an ::error :: diagnostic (HTTP code / attempt / reason) to stderr and
# exits 1. The API key and the full response body are NEVER printed.
#
set -euo pipefail

HDR_FILE="/tmp/llm_hdr.txt"
BODY_FILE="/tmp/llm_body.txt"
CANDIDATE_FILE="$(mktemp "${TMPDIR:-/tmp}/llm_candidate.XXXXXX")"
trap 'rm -f "$CANDIDATE_FILE"' EXIT

usage() {
  cat <<'EOF'
Usage:
  llm_json.sh --system-file SYS --user-file USER --out OUT \
              --schema '<JQ_BOOL_FILTER>' [--effort low|medium|high] [--max-tokens N]
EOF
}

fail() {
  echo "::error ::llm_json: $*" >&2
  exit 1
}

SYS_FILE=""
USER_FILE=""
OUT=""
SCHEMA=""
EFFORT_ARG=""
MAX_TOKENS="1500"

while [ "$#" -gt 0 ]; do
  case "$1" in
    --system-file) SYS_FILE="${2:-}"; shift 2 ;;
    --user-file)   USER_FILE="${2:-}"; shift 2 ;;
    --out)         OUT="${2:-}"; shift 2 ;;
    --schema)      SCHEMA="${2:-}"; shift 2 ;;
    --effort)      EFFORT_ARG="${2:-}"; shift 2 ;;
    --max-tokens)  MAX_TOKENS="${2:-}"; shift 2 ;;
    -h|--help)     usage; exit 0 ;;
    *)             usage >&2; fail "unknown argument: $1" ;;
  esac
done

[ -n "$SYS_FILE" ]  || fail "--system-file is required"
[ -n "$USER_FILE" ] || fail "--user-file is required"
[ -n "$OUT" ]       || fail "--out is required"
[ -n "$SCHEMA" ]    || fail "--schema is required"
[ -r "$SYS_FILE" ]  || fail "--system-file is not readable: $SYS_FILE"
[ -r "$USER_FILE" ] || fail "--user-file is not readable: $USER_FILE"
case "$MAX_TOKENS" in
  ''|*[!0-9]*) fail "--max-tokens must be a non-negative integer" ;;
esac

[ -n "${OPENCODE_API_KEY:-}" ] || fail "OPENCODE_API_KEY is not set"

MODEL="${MODEL:-thinkingmachines/inkling:free}"
ENDPOINT="${OPENROUTER_ENDPOINT:-https://openrouter.ai/api/v1/chat/completions}"
MAX_ATTEMPTS="${LLM_MAX_ATTEMPTS:-3}"
BACKOFF="${LLM_BACKOFF:-5 15 45}"

case "$MAX_ATTEMPTS" in
  ''|*[!0-9]*) fail "LLM_MAX_ATTEMPTS must be a positive integer" ;;
esac
[ "$MAX_ATTEMPTS" -ge 1 ] || fail "LLM_MAX_ATTEMPTS must be >= 1"

# Effort resolution: an explicitly-set LLM_REASONING_EFFORT (even empty) wins;
# when the variable is unset, the per-call --effort flag is used. An empty
# resolved value omits reasoning_effort from the request body entirely.
if [ -n "${LLM_REASONING_EFFORT+x}" ]; then
  EFFORT="$LLM_REASONING_EFFORT"
else
  EFFORT="$EFFORT_ARG"
fi

# LLM_BACKOFF is a space-separated list; index by attempt (0-based).
read -r -a BACKOFF_ARR <<< "$BACKOFF"

# Build the request body. $1 = assistant raw content ("" on the first call),
# $2 = correction instruction ("" on the first call). Uses --rawfile for the
# prompt files and --arg for everything else so untrusted text is never
# interpolated into the shell.
build_body() {
  local assistant="${1:-}"
  local correction="${2:-}"
  jq -n \
    --rawfile sys "$SYS_FILE" \
    --rawfile user "$USER_FILE" \
    --arg model "$MODEL" \
    --arg effort "$EFFORT" \
    --argjson mt "$MAX_TOKENS" \
    --arg assistant "$assistant" \
    --arg correction "$correction" \
    '{
       model: $model,
       messages: (
         [{role: "system", content: $sys}, {role: "user", content: $user}]
         + (if $assistant != "" then
              [{role: "assistant", content: $assistant},
               {role: "user", content: $correction}]
            else [] end)
       ),
       max_tokens: $mt
     }
     + (if $effort != "" then {reasoning_effort: $effort} else {} end)'
}

# POST the body; capture HTTP code into HTTP_CODE. No --fail-with-body: the
# code and body are both needed for retry/validation decisions.
post() {
  local body="$1"
  HTTP_CODE="$(curl -sS -D "$HDR_FILE" -o "$BODY_FILE" -w '%{http_code}' \
    -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $OPENCODE_API_KEY" \
    -H "Content-Type: application/json" \
    -d "$body" || true)"
  HTTP_CODE="${HTTP_CODE:-000}"
}

is_transport() {
  case "${1:-}" in
    000|429|500|502|503|504) return 0 ;;
    *) return 1 ;;
  esac
}

# Apply +/-20% jitter to a base delay in seconds.
with_jitter() {
  local base="${1:-0}"
  case "$base" in ''|*[!0-9]*) base=0 ;; esac
  [ "$base" -gt 0 ] || { printf '0'; return 0; }
  local delta=$(( base / 5 ))
  local span=$(( delta * 2 + 1 ))
  local r=$(( RANDOM % span ))
  printf '%s' "$(( base - delta + r ))"
}

# Backoff for a 0-based attempt index; clamps to the last configured value.
backoff_for() {
  local idx="${1:-0}"
  local n="${#BACKOFF_ARR[@]}"
  [ "$n" -gt 0 ] || { printf '0'; return 0; }
  local i="$idx"
  [ "$i" -lt "$n" ] || i=$(( n - 1 ))
  with_jitter "${BACKOFF_ARR[$i]}"
}

# Print a numeric Retry-After (capped at 60s), or nothing if absent/non-numeric.
retry_after() {
  local ra
  ra="$(grep -i '^retry-after:' "$HDR_FILE" 2>/dev/null | tail -n 1 \
    | sed 's/^[^:]*:[[:space:]]*//' | tr -d '\r' | tr -d '[:space:]' || true)"
  case "${ra:-}" in
    ''|*[!0-9]*) return 0 ;;
  esac
  if [ "$ra" -gt 60 ]; then
    ra=60
  fi
  printf '%s' "$ra"
}

# --- transport retry loop -------------------------------------------------
BODY="$(build_body)"
attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
  post "$BODY"
  if [ "$HTTP_CODE" = "200" ]; then
    echo "llm_json: HTTP 200 on attempt ${attempt}/${MAX_ATTEMPTS}" >&2
    break
  fi
  if is_transport "$HTTP_CODE"; then
    if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
      SLEEP="$(retry_after)"
      if [ -n "$SLEEP" ]; then
        echo "llm_json: HTTP ${HTTP_CODE}; honoring Retry-After=${SLEEP}s (attempt ${attempt}/${MAX_ATTEMPTS})" >&2
      else
        SLEEP="$(backoff_for $(( attempt - 1 )))"
        echo "llm_json: transport HTTP ${HTTP_CODE}; backoff ${SLEEP}s before attempt $(( attempt + 1 ))/${MAX_ATTEMPTS}" >&2
      fi
      sleep "$SLEEP"
      attempt=$(( attempt + 1 ))
      continue
    fi
    fail "transport failure HTTP ${HTTP_CODE} after ${attempt} attempt(s)"
  fi
  fail "HTTP ${HTTP_CODE} is not retryable (attempt ${attempt}/${MAX_ATTEMPTS})"
done

# --- extract content ------------------------------------------------------
CONTENT="$(jq -r '.choices[0].message.content // ""' "$BODY_FILE" 2>/dev/null || true)"
[ -n "$CONTENT" ] || fail "HTTP 200 but response contained no message content"

printf '%s' "$CONTENT" | sed '/^```/d' > "$CANDIDATE_FILE"

if jq -e "$SCHEMA" "$CANDIDATE_FILE" >/dev/null 2>&1; then
  jq '.' "$CANDIDATE_FILE" > "$OUT"
  echo "llm_json: wrote validated JSON to ${OUT}" >&2
  exit 0
fi

# --- ONE semantic correction retry ---------------------------------------
echo "llm_json: response failed schema validation; attempting one semantic correction" >&2
CORRECTION_PROMPT="Your previous reply was not valid JSON matching the required schema. Reply with ONLY valid JSON, no markdown, no prose."
BODY="$(build_body "$CONTENT" "$CORRECTION_PROMPT")"
post "$BODY"
[ "$HTTP_CODE" = "200" ] || fail "correction attempt returned HTTP ${HTTP_CODE}; no valid JSON produced"

CONTENT="$(jq -r '.choices[0].message.content // ""' "$BODY_FILE" 2>/dev/null || true)"
[ -n "$CONTENT" ] || fail "correction HTTP 200 but response contained no message content"

printf '%s' "$CONTENT" | sed '/^```/d' > "$CANDIDATE_FILE"
if jq -e "$SCHEMA" "$CANDIDATE_FILE" >/dev/null 2>&1; then
  jq '.' "$CANDIDATE_FILE" > "$OUT"
  echo "llm_json: wrote corrected validated JSON to ${OUT}" >&2
  exit 0
fi

fail "response still failed schema validation after one correction attempt"
