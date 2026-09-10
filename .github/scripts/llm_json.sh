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
#   OPENROUTER_API_KEY[_2.._5]  (>=1 required) bearer tokens, tried in order; rotate on 401/402 or transport exhaustion; never logged
#   MODEL                 default nex-agi/nex-n2.5-mini:free (override via env MODEL / repo variable MODEL)
#   OPENROUTER_ENDPOINT   default https://openrouter.ai/api/v1/chat/completions
#   LLM_MAX_ATTEMPTS      default 3
#   LLM_BACKOFF           default "5 15 45" seconds, indexed by attempt
#   LLM_REASONING_EFFORT  explicit override; when SET (even to "") it wins over
#                         --effort and an empty value disables reasoning_effort
#
# NOTE: OpenRouter may gate a model to "approved" apps; a direct API call then
# returns HTTP 403. That is a model/account restriction, NOT a key failure, so
# 403 is treated as fatal (no key rotation) and the provider's .error.message is
# surfaced to make the reason visible.
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

# --effort, when supplied, must be one of the supported reasoning levels.
case "$EFFORT_ARG" in
  ''|low|medium|high) ;;
  *) fail "--effort must be one of: low, medium, high" ;;
esac

KEYS=()
for _k in OPENROUTER_API_KEY OPENROUTER_API_KEY_2 OPENROUTER_API_KEY_3 OPENROUTER_API_KEY_4 OPENROUTER_API_KEY_5; do
  _v="${!_k:-}"
  [ -n "$_v" ] && KEYS+=("$_v")
done
unset _k _v
[ "${#KEYS[@]}" -gt 0 ] || fail "no API key configured (set OPENROUTER_API_KEY, optionally _2.._5)"

MODEL="${MODEL:-nex-agi/nex-n2.5-mini:free}"
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
  local body="$1" key="$2"
  HTTP_CODE="$(curl -sS -D "$HDR_FILE" -o "$BODY_FILE" -w '%{http_code}' \
    -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $key" \
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

is_key_failure() {
  case "${1:-}" in
    401|402) return 0 ;;
    *) return 1 ;;
  esac
}

# Extract a short, safe provider error message from the last response body.
# Never prints headers or the key; truncates to 300 chars on one line.
api_error_message() {
  local msg
  msg="$(jq -r '.error.message // .error // .message // empty' "$BODY_FILE" 2>/dev/null || true)"
  case "$msg" in ''|null) return 0 ;; esac
  printf '%s' "$msg" | tr '\n' ' ' | cut -c1-300
}

# Extract usable assistant content from the last response body, or "" when the
# provider returned no message content. Handles the plain-string form and the
# array-of-parts form. Reads $BODY_FILE; never prints the raw body. Some
# providers return HTTP 200 with an {"error":...} overload body or an empty /
# truncated message; callers must treat "" as a transient, not a success.
extract_content() {
  jq -r '
    (.choices[0].message.content // "")
    | if type == "string" then .
      elif type == "array" then ([.[] | if type == "object" then (.text // "") else . end] | join(""))
      else "" end
  ' "$BODY_FILE" 2>/dev/null || true
}

# Short finish_reason for diagnostics ("" when absent). Never prints the body.
finish_reason() {
  jq -r '.choices[0].finish_reason // empty' "$BODY_FILE" 2>/dev/null || true
}

# A free-tier daily cap is key-scoped, not a transient provider hiccup: OpenRouter
# returns HTTP 429 with error.metadata.limit_source == "openrouter_free_tier_daily".
# Detect it so the caller rotates to the next key immediately instead of burning
# the backoff budget on a key that cannot succeed again today.
is_key_cap() {
  [ "${1:-}" = "429" ] || return 1
  jq -e '.error.metadata.limit_source == "openrouter_free_tier_daily"' "$BODY_FILE" >/dev/null 2>&1
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
  # Reject absurdly long values before any numeric comparison (they can overflow
  # the shell's integer arithmetic), then cap the delay at 60s.
  if [ "${#ra}" -gt 6 ]; then
    ra=60
  elif [ "$ra" -gt 60 ]; then
    ra=60
  fi
  printf '%s' "$ra"
}

# Transport retry + key rotation helper: POST $1 with jittered backoff /
# Retry-After on transport failures, rotating to the next configured key on an
# auth/credit failure (401/402) or once a key's transport retries are
# exhausted. Returns 0 only on HTTP 200. Used for BOTH the primary call and the
# single semantic correction. A non-retryable, non-key HTTP code (e.g. 403/400/
# 404/422) fails loudly without rotating: the request/model is wrong, not the
# key — 403 in particular means OpenRouter gated the model to approved apps.
# $2 = phase label for diagnostics. The key VALUE is never logged; only the key
# index (ki/N) and HTTP codes.
post_with_retries() {
  local body="$1" phase="${2:-primary}"
  local n="${#KEYS[@]}"
  local ki=0 key
  for key in "${KEYS[@]}"; do
    ki=$(( ki + 1 ))
    local attempt=1
    while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
      post "$body" "$key"
      if [ "$HTTP_CODE" = "200" ]; then
        if [ -n "$(extract_content)" ]; then
          echo "llm_json: HTTP 200 (${phase}) on key ${ki}/${n}, attempt ${attempt}/${MAX_ATTEMPTS}" >&2
          return 0
        fi
        # HTTP 200 with no assistant content: some providers return an
        # overload/gateway {"error":...} body (or an empty/truncated message)
        # with a success status. Treat it as transient exactly like a transport
        # failure: back off, retry, then rotate keys. Previously this was fatal
        # on the first attempt (NOTES.ts "known gap").
        local empty_msg empty_fr
        empty_msg="$(api_error_message)"
        empty_fr="$(finish_reason)"
        if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
          local edelay
          edelay="$(retry_after)"
          if [ -n "$edelay" ]; then
            echo "llm_json: HTTP 200 empty content (${phase}) on key ${ki}/${n}${empty_fr:+ [finish=${empty_fr}]}${empty_msg:+ : ${empty_msg}}; honoring Retry-After=${edelay}s (attempt ${attempt}/${MAX_ATTEMPTS})" >&2
          else
            edelay="$(backoff_for $(( attempt - 1 )))"
            echo "llm_json: HTTP 200 empty content (${phase}) on key ${ki}/${n}${empty_fr:+ [finish=${empty_fr}]}${empty_msg:+ : ${empty_msg}}; backoff ${edelay}s before attempt $(( attempt + 1 ))/${MAX_ATTEMPTS}" >&2
          fi
          sleep "$edelay"
          attempt=$(( attempt + 1 ))
          continue
        fi
        echo "llm_json: key ${ki}/${n} empty-content exhausted (HTTP 200, ${phase})${empty_fr:+ [finish=${empty_fr}]}${empty_msg:+ : ${empty_msg}} after ${attempt} attempt(s); rotating" >&2
        break
      fi
      if is_key_cap "$HTTP_CODE"; then
        echo "llm_json: key ${ki}/${n} hit the free-tier daily cap (HTTP 429); rotating (${phase})" >&2
        break
      fi
      if is_key_failure "$HTTP_CODE"; then
        echo "llm_json: key ${ki}/${n} rejected HTTP ${HTTP_CODE}; rotating (${phase})" >&2
        break
      fi
      if is_transport "$HTTP_CODE"; then
        if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
          local delay
          delay="$(retry_after)"
          if [ -n "$delay" ]; then
            echo "llm_json: HTTP ${HTTP_CODE} (${phase}) on key ${ki}/${n}; honoring Retry-After=${delay}s (attempt ${attempt}/${MAX_ATTEMPTS})" >&2
          else
            delay="$(backoff_for $(( attempt - 1 )))"
            echo "llm_json: transport HTTP ${HTTP_CODE} (${phase}) on key ${ki}/${n}; backoff ${delay}s before attempt $(( attempt + 1 ))/${MAX_ATTEMPTS}" >&2
          fi
          sleep "$delay"
          attempt=$(( attempt + 1 ))
          continue
        fi
        echo "llm_json: key ${ki}/${n} transport exhausted (HTTP ${HTTP_CODE}, ${phase}) after ${attempt} attempt(s); rotating" >&2
        break
      fi
      local api_msg; api_msg="$(api_error_message)"
      if [ -n "$api_msg" ]; then
        fail "HTTP ${HTTP_CODE} is not retryable (${phase}, attempt ${attempt}/${MAX_ATTEMPTS}): ${api_msg}"
      else
        fail "HTTP ${HTTP_CODE} is not retryable (${phase}, attempt ${attempt}/${MAX_ATTEMPTS})"
      fi
    done
  done
  local last_msg; last_msg="$(api_error_message)"
  if [ -n "$last_msg" ]; then
    fail "all ${n} API key(s) failed on ${phase}: ${last_msg}"
  else
    fail "all ${n} API key(s) failed on ${phase}"
  fi
}

# Atomically write the schema-validated candidate to --out.
write_out() {
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/llm_out.XXXXXX")"
  if jq '.' "$CANDIDATE_FILE" > "$tmp"; then
    mv "$tmp" "$OUT"
  else
    rm -f "$tmp"
    return 1
  fi
}

# Strip an optional single fenced wrapper around the whole reply: one leading
# fence line (``` or ```lang) and/or one trailing ``` line. Interior lines that
# contain fenced blocks (real code/doc content) are preserved byte-for-byte.
# The old `/^```/d` deleted every fence line and corrupted legitimate content.
strip_fences() {
  awk '
    { lines[NR] = $0 }
    END {
      first = 1
      last = NR
      if (last >= 1 && lines[1] ~ /^```[A-Za-z0-9]*$/) first = 2
      if (last >= first && lines[last] ~ /^```$/) last = last - 1
      for (i = first; i <= last; i++) print lines[i]
    }
  '
}

# --- primary call + transport retries -------------------------------------
BODY="$(build_body)"
post_with_retries "$BODY" "primary"

# --- extract content ------------------------------------------------------
# post_with_retries already guarantees non-empty content on success; this is a
# defensive re-check (and the single source of the extraction logic).
CONTENT="$(extract_content)"
[ -n "$CONTENT" ] || fail "HTTP 200 but response contained no message content"

printf '%s' "$CONTENT" | strip_fences > "$CANDIDATE_FILE"

if jq -e "$SCHEMA" "$CANDIDATE_FILE" >/dev/null 2>&1; then
  write_out || fail "failed to write validated JSON to ${OUT}"
  echo "llm_json: wrote validated JSON to ${OUT}" >&2
  exit 0
fi

# --- ONE semantic correction retry (with its own transport retries) --------
echo "llm_json: response failed schema validation; attempting one semantic correction" >&2
CORRECTION_PROMPT="Your previous reply was not valid JSON matching the required schema. Reply with ONLY valid JSON, no markdown, no prose."
BODY="$(build_body "$CONTENT" "$CORRECTION_PROMPT")"
post_with_retries "$BODY" "correction"

CONTENT="$(extract_content)"
[ -n "$CONTENT" ] || fail "correction HTTP 200 but response contained no message content"

printf '%s' "$CONTENT" | strip_fences > "$CANDIDATE_FILE"
if jq -e "$SCHEMA" "$CANDIDATE_FILE" >/dev/null 2>&1; then
  write_out || fail "failed to write corrected validated JSON to ${OUT}"
  echo "llm_json: wrote corrected validated JSON to ${OUT}" >&2
  exit 0
fi

fail "response still failed schema validation after one correction attempt"
