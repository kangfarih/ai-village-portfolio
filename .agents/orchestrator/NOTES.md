# orchestrator v1 — NOTES

First real agentic layer: `agent-orchestrate` workflow breaks an issue labeled
`ai-orchestrate` into 3–6 concrete goals via LLM, creates one `ai-goal`
sub-issue per goal, posts a single summary comment on the parent, and adds
`triage/accepted`. Pure GitHub workflow agent; model `thinkingmachines/inkling:free`.

## What was built (this task, `dev` only — NEVER main)

- `.github/workflows/agent-orchestrate.yml` (new) — mirrors `agent-triage.yml`
  patterns exactly: `on: issues: types: [labeled]`; job `if:` requires the
  `ai-orchestrate` label plus human trigger (`issue.user.type != 'Bot'` and
  `sender.type != 'Bot'`); top-level `permissions: {}` with job-level
  `contents: read` + `issues: write`; `runs-on: ubuntu-latest`;
  `timeout-minutes: 10`; `concurrency` group
  `agent-orchestrate-${{ github.event.issue.number }}` with
  `cancel-in-progress: false`.
  Steps: (1) checkout (`fetch-depth: 1`, `persist-credentials: false`);
  (2) identity echo (`Agent: pure GitHub workflow agent` /
  `Model: thinkingmachines/inkling:free`); (3) self-healing
  `gh label create "ai-orchestrate" ... || true` +
  `gh label create "ai-goal" ... || true` with `GH_TOKEN: ${{ github.token }}`;
  (4) LLM goal breakdown (bash + curl + jq only, nothing installed) reading the
  issue via `gh issue view "$ISSUE_NUMBER" --json title,body --jq '{title, body}'`,
  saving goals to `goals.json`; (5) delegation loop (`jq`, capped at 6)
  creating `[GOAL] <title> (from #<N>)` sub-issues labeled `ai-goal` with
  `Parent: #<N>` + `Acceptance: post result as comment + link evidence.` bodies,
  then ONE parent comment (goal list + sub-issue links +
  `Agent: pure GitHub workflow agent | Model: thinkingmachines/inkling:free`),
  then `gh issue edit <N> --add-label "triage/accepted"`.
- `.github/labels.yml` (appended 2 labels, reference only — no label-sync Action):
  `ai-orchestrate` (`0E8A16`, "Opt-in to orchestrator delegation") and `ai-goal`
  (`1D76DB`, "Orchestrator-delegated sub-goal").
- `.agents/orchestrator/NOTES.md` (this file).

## Endpoint / key assumptions

- LLM endpoint is OpenRouter: `POST https://openrouter.ai/api/v1/chat/completions`,
  model `thinkingmachines/inkling:free`, `max_tokens: 1500`, system prompt demanding
  a JSON array only (`{title, detail}` items, no markdown/prose), user content
  `<ISSUE_TITLE>\n\n<ISSUE_BODY>` built with `jq -n` (no shell interpolation of
  untrusted issue text into JSON).
- Auth: `Authorization: Bearer $OPENCODE_API_KEY` where `OPENCODE_API_KEY` comes
  from `${{ secrets.OPENCODE_API_KEY }}` (Actions secret, never logged/printed).
  It must hold a working OpenRouter key; a stale/revoked key yields non-200 and
  falls back (see below), it does NOT fail the job.

## Graceful-fallback behavior (job never fails on LLM error)

- `OPENCODE_API_KEY` empty → skip the LLM call entirely, write 3 template goals
  (research options / compare vs criteria / recommend+document), `LLM_OK=false`.
- Non-200 HTTP (`curl --fail-with-body` + captured `%{http_code}`) → template goals.
- LLM output not a non-empty JSON array after fence-stripping (`sed '/^```/d'`)
  and normalization (items without a title dropped) → template goals.
- Only hard failures: `gh` API errors, `jq` errors on our own files, or zero goals
  (zero goals exits 0 with no changes, before any writes).

## Verification (pre-commit)

- `ruby -ryaml -e "YAML.load_file(...)"` OK for `agent-orchestrate.yml` and
  `labels.yml` (python3 `yaml` module missing on host — same fallback as triage-fix).
- `bash -n` on each extracted inline `run:` script — all pass.
- `git status --short` shows exactly the 3 new/modified files; `git diff --stat`
  reviewed before commit. No other files touched.

## Commit + push record (dev only — NEVER main)

- Message: `feat(orchestrator): LLM goal breakdown + sub-issue delegation (v1)`.
- Files in this commit (ONLY these 3):
  - `.github/workflows/agent-orchestrate.yml` (new)
  - `.github/labels.yml` (appended `ai-orchestrate`, `ai-goal`)
  - `.agents/orchestrator/NOTES.md` (new, incl. this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- SHA + push result: see the task report (`git log --oneline -3` /
  `git status -sb` post-push — SHA unknowable before commit, so recorded there,
  not invented here).

## Review fixes (dev only — NEVER main)

Findings (reviewer report, `agent-orchestrate.yml` on `dev`):

1. (Blocking, ~line 93) jq normalization `[.[] | {title: (.title // ""), ...}]`
   crashed on arrays of non-objects (e.g. `["foo"]`): `.title` on a string
   throws, and `set -euo pipefail` killed the step red, breaking the
   "never fails" guarantee.
   Fix: `try/catch` normalization —
   `[.[] | {title: ((try .title catch "") // ""), detail: ((try .detail catch "") // "")}]`.
2. (Blocking, ~line 137) `gh issue edit --add-label "triage/accepted"`
   assumed the label exists, but the Ensure step only created
   `ai-orchestrate`/`ai-goal`.
   Fix: added `gh label create "triage/accepted" --color "0E8A16"
   --description "Triage accepted, ready for work" 2>/dev/null || true` to the
   Ensure step. `triage/accepted` is now self-created by both workflows
   (triage + orchestrate) and should be added to `.github/labels.yml` later —
   `labels.yml` deliberately NOT touched in this task.
3. (Warning→fix, idempotency) the delegate loop unconditionally created
   sub-issues on every run, so re-adding `ai-orchestrate` duplicated work.
   Fix: guard at the START of the delegate step — if the parent issue already
   has a comment containing `<!-- orchestrator:v1 -->` (via
   `gh issue view "$ISSUE_NUMBER" --json comments --jq '...contains("<!-- orchestrator:v1 -->")'`),
   echo `already orchestrated, skipping` and `exit 0`. The parent comment the
   workflow posts now starts with the literal marker
   `<!-- orchestrator:v1 -->` as its first line.

## Commit + push record — review fixes (dev only — NEVER main)

- Message: `fix(orchestrator): jq crash guard, self-heal triage/accepted, idempotency marker`.
- Files: `.github/workflows/agent-orchestrate.yml`,
  `.agents/orchestrator/NOTES.md` (ONLY these 2 — `labels.yml` untouched).
- Fix commit: `485d5d4` — `git push origin dev` OK
  (`c4fa145..485d5d4  dev -> dev`).
- This notes-record entry: second notes-only commit (SHA recorded post-push).

## Open risks / follow-ups

- **LLM call unverified until a live `ai-orchestrate` event**: YAML parse +
  `bash -n` prove syntax only. The OpenRouter request/response path (key validity,
  model availability, output shape) has never run — first trial should be a test
  issue labeled `ai-orchestrate` with a valid `OPENCODE_API_KEY` set, then confirm
  `goals.json`-driven sub-issues + the single parent comment appear.
- **Worker (`ai-goal` consumer) is v2 / not built**: sub-issues labeled `ai-goal`
  currently have no automation acting on them; claiming/assigning/executing goals
  is out of scope for v1.
- Free-model drift: goal quality/format may vary; prompts constrain but the
  normalization + fallback only guard shape, not content quality.
- `GITHUB_TOKEN` no-retrigger: sub-issue creation/comments by the token do not
  trigger further workflow runs (loop-safe by design); the parent's
  `triage/accepted` label add likewise fires no new run for token-made edits.
- Fork issues get no secrets: `OPENCODE_API_KEY` is unavailable on fork-originated
  events → those runs always take the template-goals path.

---

# Agentic-loop foundation (this task, `dev` only — NEVER main)

> Supersedes the fallback-related bullets above: the template-goals fallback is
> **removed**. Missing config or an LLM that cannot produce schema-valid JSON now
> fails the run loudly (issue comment + non-zero exit) instead of substituting
> template goals.

Foundation for the multi-role loop. Only the PO orchestrator is (re)built here;
the TL / Programmer / review role workflows are not in this task. This ships
the shared client, the frozen state-machine contract, the labels, and the PO
refactor, so later role workflows share one contract.

## What was built

- `.github/scripts/llm_json.sh` (new, `chmod +x`) — shared, reusable LLM JSON
  client. Transport retry with jittered backoff, `Retry-After` handling,
  `jq -e` schema validation, and ONE semantic-correction retry. No `--fail-with-body`
  (the HTTP code and body are both needed). Never prints the key or full body.
- `.agents/orchestrator/STATE-MACHINE.md` (new) — the frozen contract all role
  workflows share: roles/efforts/model, the `goal/*` label state machine,
  `MAX_REVISE=3` with an `<!-- attempts:N -->` counter, parent completion
  (`status:done`, no auto-close), the chosen source of truth (labels for state +
  HTML-comment markers for counters/specs), and per-role concurrency groups.
- `.github/labels.yml` (appended 8 labels, reference only): `goal/tl`
  (`FBCA04`), `goal/ready` (`0E8A16`), `goal/building` (`1D76DB`),
  `goal/review` (`5319E7`), `goal/done` (`0E8A16`), `goal/revise` (`D93F0B`),
  `needs-human` (`B60205`), `status:done` (`0E8A16`).
- `.github/workflows/agent-orchestrate.yml` (refactor) — keeps trigger
  (`issues: [labeled]`), the human/`ai-orchestrate` `if:` guard, least-privilege
  `contents: read` + `issues: write`, `timeout-minutes: 10`, and the
  `agent-orchestrate-<n>` concurrency group. The self-heal step now also
  `gh label create`s the 8 new labels. The inline curl is replaced by prompt
  files (`/tmp/orchestrator_system.txt`, `/tmp/orchestrator_user.txt`) plus one
  call to `.github/scripts/llm_json.sh --schema 'type=="array" and length>0'
  --effort high`. Delegation is deduped per goal against existing `ai-goal`
  sub-issues (`gh issue list ... --search 'in:title "from #N"'`), capped at 6,
  and still writes the `<!-- orchestrator:v1 -->` marker comment and
  `--add-label triage/accepted`. No push/PR/merge steps.
- `.agents/orchestrator/NOTES.md` (this file).

## Helper flags / env (`llm_json.sh`)

- Usage: `--system-file SYS --user-file USER --out OUT --schema '<JQ_BOOL_FILTER>'
  [--effort low|medium|high] [--max-tokens N]` (default 1500).
- Env: `OPENCODE_API_KEY` (required), `MODEL`
  (default `thinkingmachines/inkling:free`), `OPENROUTER_ENDPOINT`
  (default `https://openrouter.ai/api/v1/chat/completions`), `LLM_MAX_ATTEMPTS`
  (default `3`), `LLM_BACKOFF` (default `"5 15 45"`, ±20% jitter, `Retry-After`
  wins when numeric and is capped at 60s).
- Effort: `--effort` is honored when `LLM_REASONING_EFFORT` is **unset**; if
  `LLM_REASONING_EFFORT` is set (even to `""`) it wins, and an empty value omits
  `reasoning_effort` from the request entirely. So `LLM_REASONING_EFFORT=""`
  disables `reasoning_effort` for models that reject it.
- Outcomes: exit 0 only after schema-valid JSON is written to `--out`; every
  other path prints an `::error ::` diagnostic (HTTP code / attempt / reason) to
  stderr and exits 1.

## Fallback removed → loud failure

- `OPENCODE_API_KEY` empty → the workflow comments that the key is not
  configured, then `exit 1`. No silent substitution.
- Helper non-zero exit (transport exhausted, non-retryable HTTP, or schema
  invalid after the one correction) → the workflow comments that the orchestrator
  LLM failed after retries and the label can be re-applied, then `exit 1`.

## Verification (pre-commit)

- `ruby -ryaml -e "YAML.load_file(...)"` OK for `agent-orchestrate.yml` and
  `labels.yml` (python3 `yaml` missing on host — same fallback as earlier tasks).
- `bash -n` OK for `llm_json.sh` and for all 4 extracted workflow `run:` blocks.
- `shellcheck` is **not installed** on the host, so it was skipped.
- Mock `curl` (no real API call) drove `llm_json.sh` end-to-end: valid fenced
  array on 200 → exit 0 + pretty-printed output; 503→200 transport retry; 401
  non-retryable (1 call); invalid→valid correction (2 calls, correction prompt
  present); `Retry-After: 1` honored; `LLM_REASONING_EFFORT=""` omits
  `reasoning_effort`; key never appears in logs. Edge cases: 3×500 exhaustion
  (3 calls, exit 1); correction still invalid (2 calls, exit 1); missing key
  exits 1 before any call; object schema filter works. All passed.

## Commit + push record (dev only — NEVER main)

- Message: `feat(agents): shared LLM client, state-machine contract, PO orchestrator refactor`.
- Files in this commit (ONLY these 5):
  - `.github/scripts/llm_json.sh` (new, executable)
  - `.agents/orchestrator/STATE-MACHINE.md` (new)
  - `.github/labels.yml` (appended 8 labels)
  - `.github/workflows/agent-orchestrate.yml` (refactor)
  - `.agents/orchestrator/NOTES.md` (this file)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- SHA + push result: recorded in the notes-only commit below (SHA is unknowable
  before the commit, so it is not invented here).

## Open risks / follow-ups

- **Live LLM unverified**: YAML parse + `bash -n` + mock tests prove syntax and
  control flow only. The real OpenRouter request/response path (key validity,
  model availability, exact output shape) has never run; first trial = a test
  issue labeled `ai-orchestrate` with `OPENCODE_API_KEY` set, then confirm
  sub-issues + the single parent marker comment.
- **`reasoning_effort` may be rejected by some models/providers** even though it
  is passed conditionally. If a model 400s on it, set `LLM_REASONING_EFFORT=""`
  (env) to disable it — no code change needed.
- The `goal/*` labels are created by `agent-orchestrate`; the TL / Programmer /
  review role workflows (which consume them) are **not built in this task**.
- `STATE-MACHINE.md` is a written contract; only the labels + PO path are
  executable so far. Any future workflow must match it exactly.
