#!/usr/bin/env bash
#
# llm_json.sh — shared multi-provider LLM JSON client for the agentic loop.
#
# Posts a chat-completion request through an ordered chain of OpenAI-compatible
# providers:
#
#   openrouter -> gemini -> groq -> huggingface -> ollama      (override with LLM_PROVIDER_ORDER)
#
# Every endpoint speaks the OpenAI wire format (`Authorization: Bearer` +
# POST /chat/completions). Within one provider the API keys are tried in order;
# within one key the provider's models are tried in order. A transport failure
# is retried with jittered backoff, an auth/credit failure (401/402/403) rotates
# to the next key, and a 400/404/422 (model unavailable / bad request) falls
# through to the next model without failing the whole run. The reply is
# validated against a jq boolean schema and ONE semantic correction retry is
# attempted before giving up loudly (NO silent fallback).
#
# Usage:
#   llm_json.sh --system-file SYS --user-file USER --out OUT \
#               --schema '<JQ_BOOL_FILTER>' [--effort low|medium|high] [--max-tokens N]
#
# Env:
#   OPENROUTER_API_KEY   openrouter bearer token (the free-tier daily cap on 429
#                        is key-scoped)
#   GEMINI_API_KEY       gemini bearer token
#   GROQ_API_KEY         groq bearer token; never logged
#   HF_API_KEY         huggingface bearer token (free/prepaid tier)
#   OLLAMA_API_KEY       ollama bearer token
#   OPENROUTER_ENDPOINT / GEMINI_ENDPOINT / GROQ_ENDPOINT / HF_ENDPOINT /
#   OLLAMA_ENDPOINT
#                        override the provider endpoint (defaults below)
#   OPENROUTER_MODELS / GEMINI_MODELS / GROQ_MODELS / HF_MODELS /
#   OLLAMA_MODELS
#                        space-separated model list; overrides the default
#   LLM_PROVIDER_ORDER   space/comma-separated subset/reorder of
#                        "openrouter gemini groq huggingface ollama"
#                        (default: all, that order)
#   LLM_MAX_ATTEMPTS     default 3
#   LLM_BACKOFF          default "5 15 45" seconds, indexed by attempt
#   LLM_REASONING_EFFORT explicit override; when SET (even to "") it wins over
#                        --effort and an empty value disables reasoning_effort
#
# reasoning_effort is sent ONLY when the resolved effort is non-empty AND the
# active provider supports it (groq does; openrouter/gemini/huggingface/ollama do
# not). If a provider rejects the parameter with HTTP 400/422 whose message
# mentions `reasoning_effort`, the same (provider,key,model) is retried once
# without it.
#
# Exit 0 only after writing schema-valid JSON to --out. Every failure path
# prints an ::error :: diagnostic (HTTP code / attempt / reason) to stderr and
# exits 1. API key values and full response bodies are NEVER printed.
#
set -euo pipefail

HDR_FILE="/tmp/llm_hdr.txt"
BODY_FILE="/tmp/llm_body.txt"
CANDIDATE_FILE="$(mktemp "${TMPDIR:-/tmp}/llm_candidate.XXXXXX")"
trap 'rm -f "$CANDIDATE_FILE"' EXIT

HTTP_CODE=""
CONTENT=""

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

MAX_ATTEMPTS="${LLM_MAX_ATTEMPTS:-3}"

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
BACKOFF="${LLM_BACKOFF:-5 15 45}"
read -r -a BACKOFF_ARR <<< "$BACKOFF"

# Ordered providers:
#   name|endpoint_env|endpoint_default|keys_env|models_env|models_default|supports_effort
PROVIDER_SPECS=(
  "openrouter|OPENROUTER_ENDPOINT|https://openrouter.ai/api/v1/chat/completions|OPENROUTER_API_KEY|OPENROUTER_MODELS|nex-agi/nex-n2.5-mini:free|false"
  "gemini|GEMINI_ENDPOINT|https://generativelanguage.googleapis.com/v1beta/openai/chat/completions|GEMINI_API_KEY|GEMINI_MODELS|gemini-3.5-flash-lite gemini-3.1-flash-lite gemini-3-flash-preview|false"
  "groq|GROQ_ENDPOINT|https://api.groq.com/openai/v1/chat/completions|GROQ_API_KEY|GROQ_MODELS|openai/gpt-oss-20b qwen/qwen3.6-27b groq/compound-mini|true"
  "huggingface|HF_ENDPOINT|https://huggingface.co/api/inference/chat/completions|HF_API_KEY|HF_MODELS|openbmb/MiniCPM5-2B XHToken/Spark-X2.5-4B|false"
  "ollama|OLLAMA_ENDPOINT|https://ollama.com/v1/chat/completions|OLLAMA_API_KEY|OLLAMA_MODELS|gpt-oss:20b gpt-oss:120b|false"
)

# provider_line NAME -> the matching spec line ("" not printed on miss).
provider_line() {
  local want="$1" spec
  for spec in "${PROVIDER_SPECS[@]}"; do
    if [ "${spec%%|*}" = "$want" ]; then
      printf '%s' "$spec"
      return 0
    fi
  done
  return 1
}

# provider_field NAME IDX -> the IDX'th (1-based) pipe-delimited field.
provider_field() {
  local want="$1" idx="$2" spec
  spec="$(provider_line "$want")" || return 1
  local IFS='|'
  # shellcheck disable=SC2086
  set -- $spec
  printf '%s' "${!idx}"
}

# Resolve the active provider order: default all five; LLM_PROVIDER_ORDER may
# be space- or comma-separated, is a subset/reorder, and unknown names are
# ignored with a warning.
ORDER_RAW="${LLM_PROVIDER_ORDER:-openrouter gemini groq huggingface ollama}"
ORDER_RAW="${ORDER_RAW//,/ }"
read -r -a ORDER_TOKENS <<< "$ORDER_RAW"
ACTIVE_PROVIDERS=()
for _name in "${ORDER_TOKENS[@]}"; do
  [ -n "$_name" ] || continue
  if provider_line "$_name" >/dev/null 2>&1; then
    _dup="false"
    if [ "${#ACTIVE_PROVIDERS[@]}" -gt 0 ]; then
      for _seen in "${ACTIVE_PROVIDERS[@]}"; do
        if [ "$_seen" = "$_name" ]; then
          _dup="true"
        fi
      done
    fi
    if [ "$_dup" = "false" ]; then
      ACTIVE_PROVIDERS+=("$_name")
    fi
  else
    echo "llm_json: warning: unknown provider '${_name}' in LLM_PROVIDER_ORDER; ignoring" >&2
  fi
done
unset _name _seen _dup
[ "${#ACTIVE_PROVIDERS[@]}" -gt 0 ] || fail "LLM_PROVIDER_ORDER contained no known provider"

# Collect keys across all active providers up front: with none configured there
# is nothing to try and the run must fail before any network call.
ANY_KEY="false"
for _p in "${ACTIVE_PROVIDERS[@]}"; do
  _keys_env="$(provider_field "$_p" 4)"
  for _kv in $_keys_env; do
    if [ -n "${!_kv:-}" ]; then
      ANY_KEY="true"
    fi
  done
done
unset _p _keys_env _kv
[ "$ANY_KEY" = "true" ] || fail "no API key configured (set OPENROUTER_API_KEY / GEMINI_API_KEY / GROQ_API_KEY / HF_API_KEY / OLLAMA_API_KEY)"

# Build the request body. $1 = model, $2 = SEND_EFFORT ("true"/"false"),
# $3 = assistant raw content ("" on the first call), $4 = correction
# instruction ("" on the first call). reasoning_effort is included only when
# SEND_EFFORT=true AND the resolved EFFORT is non-empty. Uses --rawfile for the
# prompt files and --arg for everything else so untrusted text is never
# interpolated into the shell.
build_body() {
  local model="${1:-}" send_effort="${2:-false}"
  local assistant="${3:-}" correction="${4:-}"
  local effort_field=""
  if [ "$send_effort" = "true" ] && [ -n "$EFFORT" ]; then
    effort_field="$EFFORT"
  fi
  jq -n \
    --rawfile sys "$SYS_FILE" \
    --rawfile user "$USER_FILE" \
    --arg model "$model" \
    --arg effort "$effort_field" \
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

# POST the body to $1=ENDPOINT with $2=KEY; capture HTTP code into the global
# HTTP_CODE. No --fail-with-body: the code and body are both needed for
# retry/validation decisions.
post() {
  local endpoint="$1" key="$2" body="$3"
  HTTP_CODE="$(curl -sS -D "$HDR_FILE" -o "$BODY_FILE" -w '%{http_code}' \
    -X POST "$endpoint" \
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
    401|402|403) return 0 ;;
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
# the backoff budget on a key that cannot succeed again today. Harmless when the
# body does not carry the marker (plain 429 stays a transport retry).
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

# request_with_fallback PHASE ASSISTANT CORRECTION -> sets global CONTENT on
# success, otherwise fails the run. Providers are tried in ACTIVE_PROVIDERS
# order; within a provider keys rotate in order; within a key models fall
# through in order. The key VALUE is never logged; only the provider, model and
# key index (ki/N).
request_with_fallback() {
  local phase="${1:-primary}" assistant="${2:-}" correction="${3:-}"
  local last_msg="" last_code=""
  local pname endpoint endp_env endp_def keys_env models_env models_def supports_effort
  local key key_idx nkeys kv models model attempt send_effort force_no_effort next_key
  local cmsg fr delay

  for pname in "${ACTIVE_PROVIDERS[@]}"; do
    endp_env="$(provider_field "$pname" 2)"
    endp_def="$(provider_field "$pname" 3)"
    keys_env="$(provider_field "$pname" 4)"
    models_env="$(provider_field "$pname" 5)"
    models_def="$(provider_field "$pname" 6)"
    supports_effort="$(provider_field "$pname" 7)"

    endpoint="${!endp_env:-}"
    [ -n "$endpoint" ] || endpoint="$endp_def"

    PKEYS=()
    for kv in $keys_env; do
      if [ -n "${!kv:-}" ]; then
        PKEYS+=("${!kv}")
      fi
    done
    if [ "${#PKEYS[@]}" -eq 0 ]; then
      echo "llm_json: skipping provider ${pname} (no key configured)" >&2
      continue
    fi

    models="$models_def"
    if [ -n "${!models_env:-}" ]; then
      models="${!models_env}"
    fi
    read -r -a MODEL_ARR <<< "$models"

    nkeys="${#PKEYS[@]}"
    key_idx=0
    for key in "${PKEYS[@]}"; do
      key_idx=$(( key_idx + 1 ))
      for model in "${MODEL_ARR[@]}"; do
        # force_no_effort: set when this (provider,key,model) rejected
        # reasoning_effort, so the retry omits it. Once per model.
        # next_key: set on a key-level failure (auth/credit/daily cap) so the
        # model loop breaks out to the NEXT KEY instead of the next model.
        force_no_effort="false"
        next_key="false"
        attempt=1
        while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
          if [ "$force_no_effort" = "true" ]; then
            send_effort="false"
          else
            send_effort="$supports_effort"
          fi
          local body
          body="$(build_body "$model" "$send_effort" "$assistant" "$correction")"
          post "$endpoint" "$key" "$body"
          cmsg="$(api_error_message)"
          if [ -n "$cmsg" ]; then
            last_msg="$cmsg"
          fi
          last_code="$HTTP_CODE"

          if [ "$HTTP_CODE" = "200" ]; then
            CONTENT="$(extract_content)"
            if [ -n "$CONTENT" ]; then
              echo "llm_json: HTTP 200 (${phase}) via ${pname}/${model} on key ${key_idx}/${nkeys}, attempt ${attempt}/${MAX_ATTEMPTS}" >&2
              return 0
            fi
            # HTTP 200 with no assistant content: some providers return an
            # overload/gateway {"error":...} body (or an empty/truncated
            # message) with a success status. Treat it as transient: back off,
            # retry, then move on to the next model.
            fr="$(finish_reason)"
            if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
              delay="$(retry_after)"
              if [ -n "$delay" ]; then
                echo "llm_json: HTTP 200 empty content (${phase}) via ${pname}/${model} on key ${key_idx}/${nkeys}${fr:+ [finish=${fr}]}${cmsg:+ : ${cmsg}}; honoring Retry-After=${delay}s (attempt ${attempt}/${MAX_ATTEMPTS})" >&2
              else
                delay="$(backoff_for $(( attempt - 1 )))"
                echo "llm_json: HTTP 200 empty content (${phase}) via ${pname}/${model} on key ${key_idx}/${nkeys}${fr:+ [finish=${fr}]}${cmsg:+ : ${cmsg}}; backoff ${delay}s before attempt $(( attempt + 1 ))/${MAX_ATTEMPTS}" >&2
              fi
              sleep "$delay"
              attempt=$(( attempt + 1 ))
              continue
            fi
            echo "llm_json: empty-content exhausted (HTTP 200, ${phase}, ${pname}/${model})${fr:+ [finish=${fr}]}${cmsg:+ : ${cmsg}} after ${attempt} attempt(s); next model" >&2
            break
          fi

          if is_key_cap "$HTTP_CODE"; then
            echo "llm_json: key ${key_idx}/${nkeys} hit the free-tier daily cap (HTTP 429, ${pname}); next key" >&2
            next_key="true"
            break
          fi
          if is_key_failure "$HTTP_CODE"; then
            echo "llm_json: key ${key_idx}/${nkeys} rejected HTTP ${HTTP_CODE} (${phase}, ${pname}); next key" >&2
            next_key="true"
            break
          fi

          case "$HTTP_CODE" in
            400|404|422)
              # Some models reject the reasoning_effort parameter; retry this
              # same (provider,key,model) ONCE without it before moving on.
              if [ "$force_no_effort" = "false" ] && [ "$supports_effort" = "true" ] && [ -n "$EFFORT" ]; then
                case "$cmsg" in
                  *reasoning_effort*)
                    echo "llm_json: HTTP ${HTTP_CODE} (${phase}, ${pname}/${model}) mentions reasoning_effort; retrying once without it" >&2
                    force_no_effort="true"
                    continue
                    ;;
                esac
              fi
              echo "llm_json: HTTP ${HTTP_CODE} (${phase}, ${pname}/${model}); model unavailable, next model${cmsg:+ : ${cmsg}}" >&2
              break
              ;;
          esac

          if is_transport "$HTTP_CODE"; then
            if [ "$attempt" -lt "$MAX_ATTEMPTS" ]; then
              delay="$(retry_after)"
              if [ -n "$delay" ]; then
                echo "llm_json: HTTP ${HTTP_CODE} (${phase}) via ${pname}/${model} on key ${key_idx}/${nkeys}; honoring Retry-After=${delay}s (attempt ${attempt}/${MAX_ATTEMPTS})" >&2
              else
                delay="$(backoff_for $(( attempt - 1 )))"
                echo "llm_json: transport HTTP ${HTTP_CODE} (${phase}) via ${pname}/${model} on key ${key_idx}/${nkeys}; backoff ${delay}s before attempt $(( attempt + 1 ))/${MAX_ATTEMPTS}" >&2
              fi
              sleep "$delay"
              attempt=$(( attempt + 1 ))
              continue
            fi
            echo "llm_json: transport exhausted (HTTP ${HTTP_CODE}, ${phase}, ${pname}/${model}); next model" >&2
            break
          fi

          # Any other unexpected status: record it and try the next model
          # rather than aborting the whole chain.
          echo "llm_json: HTTP ${HTTP_CODE} (${phase}, ${pname}/${model}); next model${cmsg:+ : ${cmsg}}" >&2
          break
        done
        if [ "$next_key" = "true" ]; then
          break
        fi
      done
    done
  done

  if [ -n "$last_msg" ]; then
    fail "all providers failed on ${phase}: ${last_msg} (last HTTP ${last_code})"
  else
    fail "all providers failed on ${phase} (last HTTP ${last_code})"
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

# --- primary call (provider chain + transport retries) --------------------
request_with_fallback "primary" "" ""

# request_with_fallback already guarantees non-empty content on success; this
# is a defensive re-check (and the single source of the extraction logic).
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
request_with_fallback "correction" "$CONTENT" "$CORRECTION_PROMPT"

[ -n "$CONTENT" ] || fail "correction HTTP 200 but response contained no message content"

printf '%s' "$CONTENT" | strip_fences > "$CANDIDATE_FILE"
if jq -e "$SCHEMA" "$CANDIDATE_FILE" >/dev/null 2>&1; then
  write_out || fail "failed to write corrected validated JSON to ${OUT}"
  echo "llm_json: wrote corrected validated JSON to ${OUT}" >&2
  exit 0
fi

fail "response still failed schema validation after one correction attempt"
