# LLM provider-chain refactor — `.agents/llm-fallback/NOTES.md`

Status: complete (orchestrator owns git; not committed/pushed).
Branch: `dev`.

## What changed

Replaced the messy multi-numbered OpenRouter keys + OpenCode Zen with a single
key per service and a clean 5-service chain. Final chain order (user-confirmed):

`openrouter` (single key) -> `gemini` -> `groq` -> `cline` -> `ollama`

Dropped entirely: OpenCode Zen provider, `OPENCODE_API_KEY`,
`OPENROUTER_API_KEY_2.._5`, `GEMINI_API_KEY_2`.

## Files changed

1. `.github/scripts/llm_json.sh`
   - Header comment (~L8): chain line -> `openrouter -> gemini -> groq -> cline -> ollama`.
   - Env doc block (~L23-35): single-key names only, in chain order; removed
     `[_2.._5]`, `OPENCODE_*`, and the OpenCode last-resort paragraph (~L51-53).
   - `PROVIDER_SPECS` (~L136-142): reordered to openrouter, gemini, groq, cline,
     ollama. Gemini keys -> `GEMINI_API_KEY` only. OpenRouter keys ->
     `OPENROUTER_API_KEY` only. Deleted the `opencode` row.
   - `ORDER_RAW` default (~L168): `openrouter gemini groq cline ollama`.
   - No-key error message (~L202): lists the 5 single-key env names.
   - UNTOUCHED: `is_key_cap` openrouter free-tier logic (~L302-304), backoff,
     `request_with_fallback`, schema-correction machinery.
2. `.github/workflows/agent-triage.yml`
   - Doc echo (~L46) new chain; env block reduced to 5 keys (no guard in this file).
3. `.github/workflows/agent-techlead.yml`
   - Doc echo (~L48); env block (~L61-65); guard (~L87-91) + `::error::`.
4. `.github/workflows/agent-programmer.yml`
   - Doc echo (~L56); env block (~L71-75) (kept `PROGRAMMER_MAX_TOKENS`);
     guard (~L154-158) + `::error::`.
5. `.github/workflows/agent-review.yml`
   - Doc echo (~L63); env block (~L79-83); guard (~L213-217) + `::error::`.
6. `.github/workflows/agent-orchestrate.yml`
   - Doc echo (~L78); env block (~L138-142); guard (~L150-154) +
     comment/`::error::`.
7. `.github/workflows/agent-build.yml` (comments only) — chain comment (~L9) and
   doc echo (~L82).
8. NEW root `.gitignore` — `.DS_Store`, `.env`, `.env.*`, `*.pem`, `*.key`,
   `*.secret`, `node_modules/`.

NOT touched: `.agents/orchestrator/STATE-MACHINE.md`, `.agents/orchestrator/NOTES.md`
(owned by another coder).

## Guard semantics preserved

Each guard still fails when NO provider key is set:
`if [ -z "${OPENROUTER_API_KEY:-}${GEMINI_API_KEY:-}${GROQ_API_KEY:-}${CLINE_API_KEY:-}${OLLAMA_API_KEY:-}" ]`.
`agent-triage.yml` has no guard (unchanged behavior).

## Verification (exact commands + results)

1. Banned refs — must be 0 matches (exit 1):
   ```
   rg -n 'OPENROUTER_API_KEY_[2-5]|OPENCODE_API_KEY|GEMINI_API_KEY_2' .github/
   => exit=1  (no matches)
   ```
2. Shell syntax:
   ```
   bash -n .github/scripts/llm_json.sh  => clean
   ```
3. Default order:
   ```
   rg -n 'ORDER_RAW=|LLM_PROVIDER_ORDER' .github/scripts/llm_json.sh
   168:ORDER_RAW="${LLM_PROVIDER_ORDER:-openrouter gemini groq cline ollama}"
   (plus comment/doc lines)
   ```
4. YAML validation (`ruby -ryaml -e 'YAML.load_file(ARGV[0]); puts "OK"'`):
   all 6 workflows (triage, techlead, programmer, review, orchestrate, build)
   => `OK` each.
5. Functional smoke test (no keys set):
   ```
   ::error ::llm_json: no API key configured (set OPENROUTER_API_KEY / GEMINI_API_KEY / GROQ_API_KEY / CLINE_API_KEY / OLLAMA_API_KEY)
   exit=1
   ```
   And an unknown-order list containing only the old `opencode` is now rejected:
   ```
   llm_json: warning: unknown provider 'opencode' in LLM_PROVIDER_ORDER; ignoring
   ::error ::llm_json: LLM_PROVIDER_ORDER contained no known provider
   exit=1
   ```
6. `git diff --stat` — 7 owned files + root `.gitignore` (untracked). STATE-MACHINE.md
   shows as modified but was already dirty before this task and was NOT touched here.

## Remaining risks / notes for orchestrator

- `.github/workflows/key-test.yml` (~L7,L9) still contains the bare word `opencode`
  as an input *example label/default*, and `.github/labels.yml` (~L6) has a label
  description mentioning opencode. These are NOT provider-chain references and the
  files are outside this task's ownership, so they were left untouched. Cosmetic only.
- Secrets cleanup is a GitHub repo-settings action (not code): the now-unused
  `OPENROUTER_API_KEY_2.._5`, `OPENCODE_API_KEY`, `GEMINI_API_KEY_2` secrets can be
  deleted from the repo/org when ready.
- The openrouter free-tier daily-cap rotation remains in code, but there is now only
  ONE openrouter key, so on a 429 cap the chain moves to gemini/groq/cline/ollama
  rather than rotating OpenRouter keys. This is the intended single-key behavior.
- Ordering of env vars in workflow `env:` blocks was normalized to chain order; this
  is cosmetic and does not affect precedence (each var is distinct).

## Docs (coder: orchestrator docs update, 2026-09-11)

Updated the two orchestrator docs to describe the new single-key-per-service
fallback chain and remove stale OpenRouter-numbered-key / OpenCode Zen
references. Files changed (docs only):

1. `.agents/orchestrator/STATE-MACHINE.md` — §1 "LLM provider chain":
   - Provider table is now exactly 5 rows in order
     `openrouter -> gemini -> groq -> cline -> ollama`, each with a **single**
     key env var: `OPENROUTER_API_KEY`, `GEMINI_API_KEY`, `GROQ_API_KEY`,
     `CLINE_API_KEY`, `OLLAMA_API_KEY`, with the endpoints/models per the
     confirmed chain (openrouter `nex-agi/nex-n2.5-mini:free`; gemini
     `gemini-3.5-flash-lite gemini-3.1-flash-lite gemini-3-flash-preview`;
     groq `openai/gpt-oss-20b qwen/qwen3.6-27b groq/compound-mini`
     (`reasoning_effort` yes); cline `openrouter/free`; ollama
     `gpt-oss:20b gpt-oss:120b`).
   - Default-order text now `openrouter gemini groq cline ollama`
     (`openrouter -> gemini -> groq -> cline -> ollama`).
   - Override lists dropped `OPENCODE_ENDPOINT`/`OPENCODE_MODELS`; removed the
     `opencode` row and the OpenCode caveat blockquote.
2. `.agents/orchestrator/NOTES.md`:
   - Appended `## 2026-09-11 — Single-key-per-service fallback chain
     (openrouter → gemini → groq → cline → ollama)` documenting removal of
     `OPENROUTER_API_KEY_2.._5` (5 rotation keys for ONE provider),
     `GEMINI_API_KEY_2` (inert/never wired), and OpenCode Zen; new order, files
     changed, rationale (distinct services > extra keys of one service; simpler
     env).
   - Marked the stale current-state reference sections
     `(superseded 2026-09-11)`: `## Helper flags / env (llm_json.sh)`,
     `## Fallback removed → loud failure`,
     `## Multi-provider LLM fallback (groq -> gemini -> cline -> ollama)`, and
     `## Re-added OpenRouter + OpenCode providers`.
   - Added a top-of-file **Current config (2026-09-11)** banner so the
     chronological historical entries below cannot be misread as current.

Verification (docs):
- `rg -n 'OPENROUTER_API_KEY_[2-5]|OPENCODE_API_KEY|GEMINI_API_KEY_2' .agents/orchestrator/`
  → STATE-MACHINE.md: 0 hits. NOTES.md: remaining hits are historical log
  entries or sit under an explicit `(superseded 2026-09-11)` marker / in the new
  section documenting the removals.
- `rg -n 'openrouter gemini groq cline ollama' .agents/orchestrator/STATE-MACHINE.md`
  → line 47 default-order line.
- `wc -l`: STATE-MACHINE.md 806 → 799; NOTES.md 2699 → 2802 (new appended
  section + top-of-file current-config banner).
- `git diff --stat` limited to those two docs only.

This coder did **not** touch `.github/**` or any other file. Not committed or
pushed.

## Cosmetic cleanup (2026-09-11)

Removed the last two stale cosmetic `opencode` strings left over from the
provider-chain refactor, neither of which was a provider-chain reference. In
`.github/workflows/key-test.yml` the `key_name` workflow_dispatch input example
and default (`e.g. openai, anthropic, opencode` / `default: opencode`) were
changed to `openrouter`; the endpoint default (OpenAI models URL) and all probe
logic were left untouched. In `.github/labels.yml` the `ai-triage` label
description "Opt-in to opencode triage" was changed to the provider-neutral
"Opt-in to issue triage" (the label key/name was not `opencode`, so it is
unchanged). `rg -n 'opencode' .github/` now returns 0 matches; both files still
parse with `ruby -ryaml`. `.agents/trial-agentic-workflow/NOTES.md` was left as
historical. Not committed or pushed.
