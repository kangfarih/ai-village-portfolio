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
- SHA + push result: `f0f9e86` — `git push origin dev` OK
  (`bca8c83..f0f9e86  dev -> dev`). This notes-record entry is a second
  notes-only commit (its own SHA is recorded post-push, not invented here).

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

---

# Phase 1 review fixes (`dev` only — NEVER main)

Findings from the Phase 1 foundation review, fixed across the 5 Phase 1 files.

## B1 (blocking) — invalid `gh` flags on sub-issue creation

`gh issue create` does **not** support `--json`/`--jq`; on success it prints the
new issue URL to stdout. Fixed in `.github/workflows/agent-orchestrate.yml`:

```bash
URL="$(gh issue create --title "$SUB_TITLE" --body "$SUB_BODY" \
  --label "ai-goal" --label "goal/tl")"
```

No `--parent` (unreliable across `gh` versions); the `Parent: #<N>` line stays in
the body. This also fixes **W5**: goals now carry `goal/tl` as well as `ai-goal`,
so the Phase-2 TL workflow (triggered by `goal/tl`) picks them up.

## B2 (blocking) — per-element schema

The orchestrator's `--schema` now requires every element to be an object with a
non-empty string `title` and a string `detail`:

```
type=="array" and length>0 and all(.[]; type=="object" and (.title|type=="string") and (.title|length>0) and (.detail|type=="string"))
```

The Delegate step re-checks the same contract with `jq -e` **before** creating
anything; on failure it posts a `<!-- orchestrator:v1-error -->` comment and
`exit 1`.

## W1/W2/W3 (blocking-ish) — dedupe + failure signalling

- Removed the coarse `MARKER && EXISTING_COUNT>0` early skip. Each of the (≤6)
  goals now has its expected title computed and is skipped only if an existing
  `ai-goal` title already matches — so partial prior runs and deleted/re-created
  goals are recovered individually.
- Existing titles are fetched with `gh issue list --label ai-goal --state all
  --search "in:title \"from #<N>\"" --json title,url` and **no `|| true`**: a
  query failure is loud, never treated as "no existing goals".
- The create loop is wrapped in an `ERR` trap that posts a parent comment
  beginning `<!-- orchestrator:v1-error -->` (distinct from the success marker)
  and exits non-zero on ANY failure.
- The success marker `<!-- orchestrator:v1 -->` is posted only when not already
  present; it lists created **and** existing goal links. `triage/accepted` is
  added to the parent only at the very end, after full success.
- Deviation worth noting: the existing-goal query fetches `--json title,url`
  (rather than `title` only) so the summary comment can link existing goals too.

## W4 — contract mismatch

`.github/labels.yml` now lists the three labels the workflows create:
`triage/accepted` (`0E8A16`, "Triage accepted, ready for work"),
`priority/important-soon` (`0E8A16`, "Triage priority: needs staffing soon"),
and `kind/task` (`1D76DB`, "Task or decision item"). `STATE-MACHINE.md` lists
them as triage-owned upstream labels, explicitly not part of the goal loop.

## W6/W7 — `.github/scripts/llm_json.sh` hardening

- The single semantic-correction call now goes through the same
  `post_with_retries` transport helper as the primary call, so a 429/5xx on the
  correction backs off/retries. Still exactly ONE semantic correction.
- `Retry-After` values longer than 6 digits are rejected before any numeric
  comparison, then capped at 60s (avoids shell integer overflow).
- `--effort` is validated against `low|medium|high` (empty allowed); anything
  else is a loud rejection. `LLM_REASONING_EFFORT` remains an explicit override.
- `--out` is written atomically: pretty-print to a `mktemp` file, then `mv` into
  place (temp removed on failure).

## STATE-MACHINE.md / NOTES.md

Contract updated: goal creation applies `ai-goal` + `goal/tl`; the
`<!-- orchestrator:v1-error -->` loud-failure marker is documented; the
per-title dedupe rule and cap are stated; triage-owned labels called out. This
section is the NOTES record.

## Verification (pre-commit)

- `ruby -ryaml -e "YAML.load_file(...)"` OK for `agent-orchestrate.yml` and
  `labels.yml`.
- `bash -n` OK for `llm_json.sh` and every extracted workflow `run:` block.
- Mock `curl` (no live API) drove `llm_json.sh`: valid → exit 0 + atomic output;
  503→200 transport retry; correction 503→200 retried then validated; correction
  still invalid → 2 semantic calls + exit 1; `Retry-After: 1234567890123` clamped
  to 60s; `--effort bogus` rejected before any call.
- `jq -e` per-element schema exercised: good array passes; `["foo"]` and an
  object missing `title` fail.
- `git diff --stat` touched only the 5 Phase 1 paths.

## Commit + push record (dev only — NEVER main)

- Message: `fix(agents): correct gh issue create, per-element schema, idempotent delegation, loud failures`.
- Files (ONLY these 5): `.github/workflows/agent-orchestrate.yml`,
  `.github/scripts/llm_json.sh`, `.github/labels.yml`,
  `.agents/orchestrator/STATE-MACHINE.md`, `.agents/orchestrator/NOTES.md`.
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Fix commit: `417cbbe` — `git push origin dev` OK
  (`9d387d2..417cbbe  dev -> dev`).
- This notes-record entry: second notes-only commit (its own SHA recorded
  post-push, not invented here).

## Open risks / follow-ups

- **Live LLM still unverified**: these fixes are proven by YAML/`bash -n` parse,
  mock transport tests, and `jq` schema tests only. The real OpenRouter path and
  the actual `gh issue create`/`gh issue list` behaviour (including exact
  `--search` matching) need a live `ai-orchestrate` trial with a valid key.
- The existing-goal dedupe matches the full expected title exactly; if a human
  edits a `[GOAL] … (from #N)` title, re-running may create a duplicate. The
  cap of 6 limits the blast radius.
- `gh issue list --search "in:title ..."` uses GitHub's search index; a freshly
  created sub-issue from an earlier run could be briefly unindexed, risking a
  duplicate on a rapid re-run (mitigated by the `agent-orchestrate-<n>`
  concurrency group serializing runs).
- Phase-2 TL / Programmer / review workflows do not exist yet; `goal/tl` is now
  applied but nothing consumes it until they ship.

---

# Phase 2a — TL + Programmer role workflows (`dev` only — NEVER main)

Second executable slice of the loop: the two workers that consume `goal/tl` and
`goal/ready`. Only these roles are built here; PO review (`goal/review` verdict)
is still out of scope. All model traffic goes through
`.github/scripts/llm_json.sh`; no role inlines `curl`.

## What was built

- `.github/workflows/agent-techlead.yml` (new) — trigger `goal/tl`, effort
  **medium**. Mirrors `agent-orchestrate.yml`: `on: issues: [labeled]`, human
  `if:` guard (`issue.user.type != 'Bot'` + `sender.type != 'Bot'`), top-level
  `permissions: {}` + job `contents: read` / `issues: write`,
  `fetch-depth: 1` + `persist-credentials: false`, identity echo, self-heal
  `goal/tl`/`goal/ready` via `gh label create … || true`, and the
  `agent-techlead-<n>` concurrency group. Reads the latest `tl:v1` payload; if
  `.attempt == ATTEMPT` it skips the LLM and only performs the transition.
  Otherwise it reads the goal title/body + `Parent: #N` parent + latest
  `verdict:v1` reason/guidance, calls `.github/scripts/llm_json.sh --effort
  medium` with the TL system prompt and schema
  (`objective/steps/files/acceptance/kind`), injects `.attempt`, posts the
  `tl:v1` comment (base64 payload + readable markdown), then
  `--remove-label goal/tl --add-label goal/ready`.
- `.github/workflows/agent-programmer.yml` (new) — trigger `goal/ready`, effort
  **medium** for `kind=="code"` else **low**. Claims first
  (`--remove-label goal/ready --add-label goal/building`), reads the latest
  `tl:v1`; missing/invalid → loud comment + `needs-human`. Idempotent on a
  `result:v1` whose `.attempt == ATTEMPT`. Calls `llm_json.sh` with the
  Programmer system prompt + schema (`summary/deliverable/changes/evidence/
  needs_human/needs_human_reason`), injects `.attempt`, posts the `result:v1`
  comment, then either `needs-human` (when `.needs_human == true`) or
  `--remove-label goal/building --add-label goal/review`. An `ERR` trap, the
  missing-key check, and the missing-spec check all post a loud comment and move
  the goal to `needs-human` (removing `goal/building`) then `exit 1`;
  `goal/ready` is never re-added, so there is no retry loop. No push/PR/merge.
- `.agents/orchestrator/STATE-MACHINE.md` — appended **§6 Comment payload
  format (v1)**: the `<!-- marker -->` / single-line base64 / `<!-- /marker -->`
  envelope, the `tl:v1` / `result:v1` / `verdict:v1` markers, the exact
  `RAW`/`PAYLOAD`/`JSON` extraction snippet, attempt injection, and the
  `<!-- attempts:N -->` counter (empty→0).
- `.agents/orchestrator/NOTES.md` (this section).

## Verification (pre-commit)

- `ruby -ryaml -e "YAML.load_file(...)"` OK for both new workflows.
- `bash -n` OK for all 6 extracted `run:` blocks (`shellcheck` not installed).
- Mock `gh` + a mock `llm_json.sh` drove both workflows end-to-end:
  - TL: attempts=1 + no payload → medium LLM, `tl:v1` posted with `attempt:1`,
    transition to `goal/ready`; existing `tl:v1` for the same attempt → no LLM,
    transition only; missing key → loud comment + exit 1, no LLM; helper
    failure → loud comment + exit 1, no transition.
  - Programmer: kind=code → effort medium, `result:v1` posted with `attempt:0`,
    transition to `goal/review`; kind=docs → effort low; `needs_human:true` →
    `needs-human`, no `goal/review`; existing `result:v1` for the attempt → no
    LLM, transition only; missing/invalid `tl:v1` → `needs-human` + exit 1;
    missing key → `needs-human` + exit 1; helper failure → `needs-human` +
    exit 1; claim failure → `ERR` trap → exactly one loud comment + `needs-human`
    + exit 1 (no double-post, no `goal/ready` re-add).
- Marker extraction/decoding round-trip (TL/result/verdict) on a sample comment,
  including hostile model text (`%`, `"`, backticks, `|`, newlines) and a marker
  string echoed inside the readable section: extraction still returns the
  base64 line; attempt parsing picks the last `<!-- attempts:N -->` and
  defaults to 0.
- Schemas exercised with `jq -e`: TL accepts code/docs/analysis and rejects a
  missing `objective`, non-array `steps`, bad `kind`, arrays, and `{}`;
  Programmer accepts only when every field has the exact type and rejects
  `needs_human` as a string, missing fields, non-string `deliverable`,
  non-array `changes`, and non-objects.
- `git diff --stat` touches ONLY the 4 Phase 2a paths.

## Commit + push record (dev only — NEVER main)

- Message: `feat(agents): TL and Programmer role workflows (loop v1)`.
- Files in this commit (ONLY these 4):
  - `.github/workflows/agent-techlead.yml` (new)
  - `.github/workflows/agent-programmer.yml` (new)
  - `.agents/orchestrator/STATE-MACHINE.md` (§6 appended)
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `a87f818` — `git push origin dev` OK
  (`f8b23e4..a87f818  dev -> dev`).
- This notes-record entry is a second, notes-only commit (its own SHA is
  recorded post-push, not invented here).

## Open risks / follow-ups

- **Live LLM unverified**: YAML parse + `bash -n` + mocked end-to-end flows
  prove syntax and control flow only. The real OpenRouter path and real `gh`
  comment/label behaviour have never run; first trial = a goal issue labeled
  `goal/tl` with `OPENCODE_API_KEY` set.
- **`verdict:v1` shape is inferred**: `agent-review` (the PO verdict workflow)
  is not built in this task, so the TL reads `.reason`/`.guidance` defensively
  (`try … catch` + `// ""`). If the PO writes different keys, revision context
  is empty (not fatal); reconcile when `agent-review` ships.
- **Attempt counter is PO-owned**: the TL/Programmer only read
  `<!-- attempts:N -->`; nothing increments it yet (PO revise path is not
  built), so attempts stay 0 until `agent-review` exists.
- **Bot guard vs. token-created goals (loop wiring risk)**: the mandated `if:`
  guard rejects `issue.user.type == 'Bot'` and `sender.type == 'Bot'`, and
  `GITHUB_TOKEN`-created events do not start new workflow runs. Since
  `agent-orchestrate` creates goals *and* applies `goal/tl` with
  `GITHUB_TOKEN`, those label events are both non-triggering and bot-authored,
  so the automated PO→TL hand-off does not fire as-is. This task implements the
  frozen guard **verbatim** and does not change token/trigger wiring; the
  hand-off needs either an App/PAT identity that produces human-like events or a
  deliberate human re-label step — decide this before a live end-to-end trial.
- **GNU `base64 -w0` on the encode side** (ubuntu-latest) with `base64 -d` on
  decode: correct on the runner, not portable to BSD/macOS, but the workflows
  only run on Linux.
- Programmer never pushes: the deliverable is text in a comment; applying it is
  the human `/approve` (agent-build) gate. No auto-apply.

---

# Phase 2b — PO review verdict + loop termination (`dev` only — NEVER main)

Third executable slice of the loop: the PO review role that consumes
`goal/review`, issues the verdict, and terminates a goal (and its parent). All
model traffic still goes through `.github/scripts/llm_json.sh`; no role inlines
`curl`. No push / PR / merge steps anywhere.

## What was built

- `.github/workflows/agent-review.yml` (new) — trigger `goal/review`, effort
  **high**. Mirrors `agent-techlead.yml` / `agent-programmer.yml` exactly:
  `on: issues: types: [labeled]`; human `if:` guard
  (`contains(...,'goal/review') && issue.user.type != 'Bot' && sender.type !=
  'Bot'`); top-level `permissions: {}` + job `contents: read` / `issues: write`;
  `runs-on: ubuntu-latest`; `timeout-minutes: 10`; concurrency
  `agent-review-<n>` with `cancel-in-progress: false`; checkout
  (`fetch-depth: 1`, `persist-credentials: false`); identity echo; self-heal
  `gh label create … || true` for `goal/done`, `goal/revise`, `goal/tl`,
  `goal/review`, `needs-human`, `status:done`; env `GH_TOKEN`,
  `OPENCODE_API_KEY`, `MODEL=thinkingmachines/inkling:free`; job env
  `MAX_REVISE: "3"`.
  - Reads `ATTEMPT` from the last `<!-- attempts:N -->` (default 0), goal
    title/body + `Parent: #N` + parent title/body.
  - Reads the latest `tl:v1` and `result:v1` via the §6 extraction and validates
    each against its schema; either missing/undecodable → loud comment +
    `needs-human` (remove `goal/review`) + `exit 1`.
  - Idempotent on a `verdict:v1` payload whose `.attempt == ATTEMPT`: skips the
    LLM and re-applies the stored verdict's transition.
  - Otherwise calls `llm_json.sh --effort high` with the mandated PO system
    prompt and schema
    (`verdict in {done,revise}` + string `reason` + array `missing` + string
    `guidance`), injects `.attempt`, and posts the `verdict:v1` comment (base64
    payload + readable verdict/reason/missing/guidance).
  - Applies the verdict: `done` → remove `goal/review`, add `goal/done`;
    `revise` → `NEXT=ATTEMPT+1`, post a separate comment **exactly**
    `<!-- attempts:NEXT -->`, then `goal/tl` (or, when `NEXT > MAX_REVISE`,
    `needs-human` + a loud escalation comment naming the attempt count).
  - Parent termination (only after `done`): skip if the parent already carries a
    `<!-- parent-done:v1 -->` marker or `status:done`; otherwise discover
    children with
    `gh issue list --label ai-goal --state all --search "in:title \"from #<parent>\"" --json number,title,url,labels`
    and, when the list is non-empty AND every child has `goal/done`, post
    `<!-- parent-done:v1 -->` + the goal list/links and add `status:done`. No
    auto-close.
  - An `ERR` trap over the review step posts a loud comment and exits non-zero;
    the child lookup uses no `|| true`, so a failed query is loud rather than an
    empty "no children".
- `.agents/orchestrator/STATE-MACHINE.md` — appended **§7 Review verdict +
  termination (v1)**: exact verdict semantics, PO-owned `<!-- attempts:N -->`
  counter, `MAX_REVISE=3` escalation, the `<!-- parent-done:v1 -->` marker +
  `status:done` condition, and no auto-close. §1–§6 semantics unchanged.
- `.agents/orchestrator/NOTES.md` (this section).

## Verification (pre-commit)

- `ruby -ryaml -e "YAML.load_file(...)"` OK for `agent-review.yml`; job/if/
  concurrency/MAX_REVISE parsed as expected.
- `bash -n` OK for all 3 extracted `run:` blocks (`shellcheck` not installed).
- Mock `gh` + mock `llm_json.sh` drove the **full extracted review step**
  end-to-end (47 assertions, all pass):
  - done verdict + all children `goal/done` → `goal/done` + `status:done` +
    `<!-- parent-done:v1 -->`;
  - revise at attempt 0 → exact `<!-- attempts:1 -->` + `goal/tl`, no
    `needs-human`;
  - revise at attempt 3 (`NEXT=4 > MAX_REVISE`) → `needs-human`, no `goal/tl`,
    exact `<!-- attempts:4 -->`, loud escalation comment;
  - done but one child not `goal/done` → goal done, parent **not** marked;
  - done but empty child list → parent **not** marked;
  - pre-existing `verdict:v1` for the attempt → no LLM call, transition
    re-applied;
  - missing `tl:v1` → loud comment + `needs-human` + exit 1, no LLM;
  - failed child lookup → `ERR` trap → loud comment + exit 1;
  - LLM failure → loud comment + `needs-human` + exit 1 (1 call);
  - missing `OPENCODE_API_KEY` → loud comment + `needs-human` + exit 1 (0 calls);
  - §6 extraction/decoding round-trips a payload surrounded by hostile readable
    text (`%`, quotes, backticks, pipe, newlines, marker echo before a blank
    line).
  - `jq -e` verdict schema accepts `done` + `revise`, rejects a bad verdict,
    missing `reason`, non-array `missing`, missing `guidance`, arrays, `{}`.
  - `jq` all-done detection: all `goal/done` → true; one not → false; empty →
    false; label-less element → false.
- `git diff --stat` touches only the 3 Phase 2b paths.

## Commit + push record (dev only — NEVER main)

- Message: `feat(agents): PO review verdict workflow + parent termination (loop v1)`.
- Files in this commit (ONLY these 3):
  - `.github/workflows/agent-review.yml` (new)
  - `.agents/orchestrator/STATE-MACHINE.md` (§7 appended)
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `7ded7bf` — `git push origin dev` OK
  (`0a5f01b..7ded7bf  dev -> dev`).
- This notes-record entry is a second, notes-only commit (its own SHA is
  recorded post-push, not invented here).

## Open risks / follow-ups

- **Live LLM unverified**: YAML parse + `bash -n` + mocked end-to-end flows
  prove syntax and control flow only. The real OpenRouter path and real `gh`
  comment/label/list behaviour have never run; first trial = a goal issue
  labeled `goal/review` with `OPENCODE_API_KEY` set.
- **Bot guard vs. token-created label events (loop wiring risk)**: the mandated
  `if:` guard rejects bot-authored issues/senders, and `GITHUB_TOKEN`-made label
  edits do not start new runs. As with the TL/Programmer roles, the automated
  `goal/building → goal/review` hand-off (token-made) will not fire
  `agent-review` without an App/PAT identity or a deliberate human re-label.
  This task implements the frozen guard verbatim and does not change wiring.
- **§6 extractor and a literal marker echoed in readable text**: `sed -n
  '/<!-- <marker> -->/{n;p;}'` also matches the marker inside the readable
  section; if that echo is followed by a non-blank line, `base64 -d` can return
  a corrupt payload. The review fails **loudly** (schema validation →
  `needs-human`) rather than mis-reviewing, but this is a shared TL/Programmer/
  review extractor property, not introduced here and not changed (the task
  mandates §6 verbatim).
- **Parent lookup failure after `done`**: the goal is already `goal/done` when
  parent discovery runs; if discovery fails, the `ERR` trap is loud but the
  parent is left unmarked. Retrying (re-apply `goal/review`) is idempotent and
  safe because the verdict payload for the attempt already exists.
- **`gh issue list --search` indexing lag**: the child query uses GitHub search;
  a freshly labeled child can be briefly stale, delaying parent completion. The
  `agent-review-<n>` concurrency group serializes review runs per goal.
- Free-model verdict quality/drift: the schema only constrains shape, not
  judgment; `missing[]` and `guidance` are advisory to the TL/Programmer.

---

# Phase 4a — branch isolation for the PO/orchestrator (`dev` only — NEVER main)

First branch-model slice: the orchestrator now cuts a per-parent integration
branch and classifies every goal with a `kind`, so downstream roles know
code vs non-development. Only the PO half ships here; the Programmer branch/
merge implementation is Phase 4b. All model traffic still goes through
`.github/scripts/llm_json.sh` (unmodified).

## What changed (ONLY these 3 files)

- `.github/workflows/agent-orchestrate.yml`
  - **`kind` classification**: the system prompt now demands
    `{"title", "detail", "kind"}` per goal, with `kind` ∈
    `code | docs | analysis | requirement | user-story`, and explains that
    `code` changes repo source/config/files while the rest are non-development
    and produce a markdown artifact on the issue branch.
  - **Schema tightened**: both the `llm_json.sh --schema` filter and the
    pre-loop `jq -e` guard now require, per element: object, non-empty string
    `.title`, string `.detail`, and `.kind` in the allowed set. The two filters
    are byte-identical.
  - **Goal body** now includes `Kind: <kind>` and
    `Integration branch: issue/<parent#>`.
  - **Checkout** `fetch-depth: 1` → `0`; `persist-credentials: false` → `true`
    (needed to push). Added a `Configure git author identity` step using the
    repo-wide identity `github-workflow-agent` /
    `agent@users.noreply.github.com` (same as `agent-build.yml`).
  - **Job `permissions`** gained `contents: write` (kept `issues: write` +
    `actions: write`; top-level stays `permissions: {}`; no `pull-requests`
    added).
  - **Integration branch** created as the first action under the delegation
    step's existing `ERR` trap, before the goal loop: `git fetch --no-tags
    origin dev`; skip when `refs/heads/issue/<N>` exists on `origin`; else
    `git checkout -B "issue/<N>" "origin/dev"` + `git push -u origin
    "issue/<N>"`. Never `--force`, and the only `git push` in the file targets
    `issue/<N>`.
  - **Summary comment** (`<!-- orchestrator:v1 -->`) now states the integration
    branch, the `task/<goal#>` → `issue/<N>` auto-merge model, the single
    `issue/<N>` → `dev` PR at completion, and that agents never merge to `dev`.
    `v1-error` semantics unchanged.
- `.agents/orchestrator/STATE-MACHINE.md` — appended **§9 Branch model (v1)**:
  `issue/<parent#>` integration branch, `task/<goal#>` per-goal branch
  (Programmer, Phase 4b), non-dev artifact path
  `.agents/issue-<parent#>/goal-<goal#>.md`, the single final
  `issue/<N>` → `dev` PR awaiting human merge, the no-workflow-edits hard rule,
  and the `contents: write` / `pull-requests: write` permission note.
- `.agents/orchestrator/NOTES.md` (this section).

## Verification (pre-commit, actual output)

- `ruby -ryaml -e "YAML.load_file('.github/workflows/agent-orchestrate.yml')"` →
  `YAML OK`.
- Extracted all 6 `run:` blocks (via Ruby YAML) and `bash -n` each:
  `bash -n OK` for all 6.
- Structural assertions (Ruby YAML on the parsed workflow): job
  `permissions == {"contents"=>"write","issues"=>"write","actions"=>"write"}`;
  no `pull-requests` key; checkout `fetch-depth==0` and
  `persist-credentials==true`; `issue/${ISSUE_NUMBER}` logic present;
  `git ls-remote --exit-code --heads origin` present;
  `git checkout -B "issue/${ISSUE_NUMBER}" "origin/dev"` present;
  `git push -u origin "issue/${ISSUE_NUMBER}"` present; the scan of all
  `git push` lines returns exactly that one line — no `dev`/`main` target and
  no `--force` anywhere.
- Schema equality: the `--schema` filter and the pre-loop `jq -e` guard print
  identically → `IDENTICAL: true`.
- `jq -e` schema tests on the exact filter:
  - passes: valid 3-field array; two valid elements;
  - rejects: missing `.kind`, bad `.kind`, non-string `.title`, empty `.title`,
    `["foo"]`, `[]`, and case-mismatched `"CODE"`.
- `git status --short` shows exactly the 3 intended files.

## Commit + push record (dev only — NEVER main)

- Message: `feat(orchestrator): integration branch issue/<parent#> + goal kind classification (Phase 4a)`.
- Files in this commit (ONLY these 3):
  - `.github/workflows/agent-orchestrate.yml`
  - `.agents/orchestrator/STATE-MACHINE.md` (§9 appended)
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `recorded in the follow-up notes-only commit`
  (its own SHA is recorded post-push, not invented here).

## Open risks / follow-ups

- **Live branch creation unverified**: YAML parse + `bash -n` + structural
  assertions prove syntax and that only `issue/<N>` is pushed. The real
  `git fetch`/`checkout -B`/`push -u` against `origin/dev` has not run; first
  trial = a test issue labeled `ai-orchestrate` with `OPENCODE_API_KEY` set,
  then confirm `refs/heads/issue/<N>` exists on `origin`.
- **Re-run after a partial failure creates the branch but no goals (or vice
  versa)**: branch creation is idempotent (remote-exists → skip), so re-applying
  `ai-orchestrate` is safe. However a branch may be created for a parent whose
  `goals.json` later fails the guard; the orphan branch is harmless but persists.
- **Phase 4b (Programmer) not built**: `task/<goal#>` creation, the `--no-ff`
  auto-merge into `issue/<parent#>`, the non-dev artifact commit to
  `.agents/issue-<parent#>/goal-<goal#>.md`, the final `issue/<N>` → `dev` PR,
  the no-workflow-edits guard, and the Programmer's `contents: write` are
  described in §9 but not executable yet.
- **Dedupe on re-run does not re-check `kind`**: existing goals are skipped by
  exact title, so a goal created by an older run (without `Kind:`) keeps its old
  body; only newly created goals carry `Kind:`/`Integration branch:`. Acceptable
  for v1, worth a migration note if it matters.
- **`v1-error` on branch failure is generic**: the delegation `ERR` trap message
  says "failed while delegating goals"; a branch-creation failure is now caught
  by the same trap and produces the same loud `<!-- orchestrator:v1-error -->`
  comment + non-zero exit, but does not specifically name the branch step.
- `contents: write` widens the orchestrator's token scope; branch creation is
  the only write path and it never targets `dev`/`main` (structurally asserted).
