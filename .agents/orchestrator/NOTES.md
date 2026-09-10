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
- Commit SHA + push result: `4ea5642` — `git push origin dev` OK
  (`b7d5a98..4ea5642  dev -> dev`). This notes-record entry is a second,
  notes-only commit (its own SHA is recorded post-push, not invented here).

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

---

# Phase 4b-1 — Programmer writes real files + task-branch auto-merge (`dev` only — NEVER main)

Second branch-model slice: the Programmer now writes the LLM changeset's real
files to a per-goal `task/<goal#>` branch and auto-merges (`--no-ff`) into the
per-parent `issue/<parent#>` integration branch. Agents never push `dev`/`main`
and never force-push; the final `issue/<parent#>` → `dev` PR is Phase 4b-2.
`.github/scripts/llm_json.sh` is unchanged.

## What changed (ONLY these 4 files)

- `.github/workflows/agent-programmer.yml` (main work)
  - **Permissions/checkout:** job `permissions` gained `contents: write`
    (`issues: write` + `actions: write` kept; top-level stays `permissions: {}`);
    checkout is now `fetch-depth: 0` + `persist-credentials: true`; added a
    `Configure git author identity` step (`github-workflow-agent` /
    `agent@users.noreply.github.com`).
  - **Variables:** parses `Parent: #N` from the goal body (missing/invalid →
    loud comment + `needs-human` + exit 1, **before** any branch work); derives
    `INTEGRATION=issue/<parent#>` and `TASK=task/<goal#>`; reads the latest
    `tl:v1` via §6 for `objective/steps/files/acceptance/kind`; sets
    `NONDEV=(kind != "code")`.
  - **LLM changeset call:** one `llm_json.sh` call, effort `medium` for
    `kind: code` else `low`. New schema (re-checked with `jq -e` before use):
    object with non-empty string `summary`, array `files` of
    `{path:string(nonempty), content:string}`, array of string `changes`, string
    `evidence`, boolean `needs_human`, string `needs_human_reason`. System
    prompt is kind-aware (code → real files with full contents; non-dev → one
    markdown document) and embeds the goal + parent context. Output is written
    to `/tmp/programmer_changeset.json` (NOT the repo root, so it can never be
    staged by `git add -A`).
  - **Non-dev canonical path:** when `NONDEV`, the model's path is ignored and
    the changeset is collapsed to exactly one file
    `.agents/issue-<parent#>/goal-<goal#>.md`, content = `files[0].content`
    (fallback: `summary`).
  - **Safety guards (before writing):** rejects the whole changeset (loud +
    `needs-human` + exit 1) on any empty/absolute/`..`-segment path, any
    `.git/**`, any `.github/workflows/**`, > 25 files, or > 200000 content
    bytes; no file is silently dropped. Portable `case` loop (bash 3.2-safe).
  - **Git flow (never `dev`/`main`, no force):** `git fetch --no-tags origin
    dev`; if `issue/<parent#>` is absent on origin it is created locally from
    `origin/dev` (the final push publishes it), otherwise fetched and checked
    out; stale `task/<goal#>` deleted local + remote (`git branch -D` /
    `git push origin --delete`); `task/<goal#>` cut from the integration branch;
    files written; `git add -A`; empty staging → loud + `needs-human`; commit
    `feat(goal-#N):` / `docs(goal-#N):` (subject truncated to 72 chars);
    `git push -u origin task/<goal#>`; checkout integration;
    `git merge --no-ff task/<goal#> -m "merge(...) : ..."`; a conflict does
    `git merge --abort`, loud + `needs-human` + exit 1; `git push origin
    issue/<parent#>`; captures `TASK_SHA`, `MERGE_SHA`, and `git diff --stat`.
    Exactly one content push per branch (plus the mandated task-branch delete).
  - **`result:v1` payload:** `attempt, summary, kind, files:[paths only],
    changes, evidence, commit, merge_commit, task_branch, integration_branch,
    needs_human, needs_human_reason`, posted with the §6 envelope + readable
    markdown (branches/SHAs/files/diff stat). `needs_human:true` → `needs-human`
    label + loud comment + no `goal/review`; else `goal/review`, then the
    existing dispatch of `agent-review.yml`. The `ERR` trap posts a loud comment
    + `needs-human` and exits 1, and never re-adds `goal/ready`.
  - Idempotency: a `result:v1` for the current attempt carrying `task_branch`
    short-circuits the LLM + git and only re-applies the transition (an older
    text-only `result:v1` is ignored and re-processed).
- `.github/workflows/agent-techlead.yml` (small): the `kind` enum in BOTH the
  system prompt and the `--schema` widened from `code|docs|analysis` to
  `code|docs|analysis|requirement|user-story`; everything else unchanged.
- `.agents/orchestrator/STATE-MACHINE.md`: §1 effort row updated for the
  non-dev kinds; §2 gained a `Kind:` bullet; §9 rewritten to match the
  implementation exactly (`issue/<parent#>` integration branch incl. the
  Programmer fallback, `task/<goal#>` cut/commit/push/`--no-ff` auto-merge,
  stale task delete+recreate with no force-push, the path/`.git/`/
  `.github/workflows/**`/25-file/200000-byte guards, the non-dev canonical path,
  the `result:v1` fields, conflict/nothing-to-commit → `needs-human`, the single
  `issue/<N>` → `dev` PR in Phase 4b-2, and the hard rule that agents NEVER
  push/merge `dev`/`main`).
- `.agents/orchestrator/NOTES.md` (this section).

## Verification (actual output)

- `ruby -ryaml -e "YAML.load_file(...)"` → `YAML OK` for both workflows.
- Extracted all 9 `run:` blocks (Ruby YAML) and `bash -n` each → `bash -n OK`
  for all 9. (`shellcheck` not installed on the host.)
- Structural assertions (Ruby YAML): job permissions
  `{"contents"=>"write","issues"=>"write","actions"=>"write"}`, top-level `{}`;
  checkout `fetch-depth==0`, `persist-credentials==true`; git identity present;
  `.github/workflows/*)` and `.git/*)` guard arms present; canonical
  `.agents/issue-${PARENT}/goal-${ISSUE_NUMBER}.md` present; `git ls-remote
  --exit-code --heads origin "refs/heads/${INTEGRATION}"` present;
  `git merge --no-ff` / `git merge --abort` / stale-delete present;
  `gh workflow run agent-review.yml` present; no `--add-label goal/ready`.
- `git push` audit: `git push -u origin "${TASK}"` (1), `git push origin
  --delete "${TASK}"` (1, mandated stale-branch delete), `git push origin
  "${INTEGRATION}"` (1); **0** pushes targeting `dev`/`main`; **0** literal
  `--force`.
- Changeset schema equality: on-disk `CHANGESET_SCHEMA` byte-identical to the
  tested filter → `CHANGESET SCHEMA IDENTICAL: true`.
- `jq -e` schema tests (15/15): accepts a valid changeset and an empty-`files`
  changeset; rejects missing/empty `summary`, non-array `files`, file missing
  `path`/`content`, empty `path`, non-string `content`, non-string `changes`
  element, non-string `evidence`, non-bool `needs_human`, missing
  `needs_human_reason`, an array, and `{}`.
- TL schema tests: accepts `code/docs/analysis/requirement/user-story`, rejects
  `bogus` and `CODE`.
- **Mock end-to-end (72/72 assertions)**: extracted Programmer step run against
  a throwaway local git repo + bare `origin`, with mock `gh`, a `git` conflict
  shim, and mock `llm_json.sh` (`${{ github.repository }}` substituted as
  GitHub would):
  - (a) `kind: code` happy path → `task/101` pushed, `issue/55` merge
    `--no-ff`, `feat(goal-#101)` commit, file on `issue/55`, `result:v1` with
    paths-only `files`, `commit`/`merge_commit` set, `goal/review`, effort
    `medium`, no `changeset.json` committed, then the dispatch step verifies it
    ran `agent-review.yml` with `issue_number=101`;
  - (b) `kind: docs` → exactly `.agents/issue-55/goal-101.md`, model path
    ignored, effort `low`;
  - (b2) non-dev with empty `files` → canonical content falls back to
    `summary`;
  - (c) path guards reject `../evil`, `/etc/passwd`, `.github/workflows/ci.yml`
    (needs-human, no task branch, no `goal/review`);
  - (d) merge conflict → `needs-human`, no `goal/review`, task branch still
    pushed;
  - (e) empty changeset → `needs-human`;
  - (f) missing `Parent:` → `needs-human`, no task/integration branch;
  - (g) missing integration branch → fallback creates/publishes `issue/55` with
    the merge;
  - (h) model `needs_human:true` → result posted, `needs-human`, no branch, no
    `goal/review`;
  - (i) re-run with an existing `result:v1` for the attempt → no second LLM
    call, single result comment, `goal/review`.
- `git status --short` shows exactly the 4 intended files.

## Commit + push record (dev only — NEVER main)

- Message: `feat(programmer): real file changesets on task/<goal#> auto-merged into issue/<parent#> (Phase 4b-1)`.
- Files in this commit (ONLY these 4):
  - `.github/workflows/agent-programmer.yml`
  - `.github/workflows/agent-techlead.yml`
  - `.agents/orchestrator/STATE-MACHINE.md`
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`/forced update, no
  `--no-verify`).
- Commit SHA + push result: `693439f` — `git push origin dev` OK
  (`8036bac..693439f  dev -> dev`). This notes-record entry is a second,
  notes-only commit (its own SHA is recorded post-push, not invented here).

## Open risks / follow-ups

- **`agent-review` is now schema-incompatible until Phase 4b-2.** `agent-review`
  still validates `tl:v1` `kind` as `code|docs|analysis` only and its
  `RESULT_SCHEMA` requires the old text-only `deliverable:string` +
  `evidence:[string]`. A goal reaching `goal/review` after this change will be
  rejected → `needs-human`. Phase 4b-2 must widen the review's TL schema,
  accept the new `result:v1` shape, and open the single
  `issue/<N>` → `dev` PR (`pull-requests: write`). Also
  `.github/workflows/agent-review.yml`'s copy of the TL `kind` enum is not in
  this task's 4-file scope.
- **Live git/gh unverified.** The mock proves control flow and the local git
  merge semantics; the real Actions runner, `GITHUB_TOKEN` push permissions,
  branch protections, and the integration-branch interaction with the
  orchestrator have not run. First trial = a goal at `goal/ready` with a valid
  `OPENCODE_API_KEY`, then confirm `task/<goal#>` + the `--no-ff` merge on
  `issue/<parent#>`.
- **Non-text files unsupported.** File contents are JSON strings written via
  `jq -r`; binary is out of scope for v1.
- **Idempotency keys on `task_branch`.** A pre-Phase-4b-1 `result:v1` (no
  `task_branch`) is ignored and the new git flow re-runs; a genuine 4b-1 result
  short-circuits. Repeated dispatches are otherwise safe (stale task branch is
  deleted and recreated, never force-pushed).
- **Commit subject `cut -c1-72`** counts characters, not bytes; a very long
  multi-byte summary could make the subject slightly longer in bytes. Cosmetic.
- **`git fetch --no-tags origin "${INTEGRATION}"`** assumes the integration
  branch is fetchable once present; a transient fetch failure trips the `ERR`
  trap (loud + `needs-human`), not a silent skip.
- **No `agent-build`/`/approve` path change.** The old human-gated
  `agent-build` workflow still exists; this task replaces the Programmer's
  text-only deliverable with committed branch work, so the `/approve` gate is
  now orthogonal to the loop (worth reconciling in a later phase).

---

# Phase 4b-2 — PO review accepts `result:v1` + opens the single human-gated PR (`dev` only — NEVER main)

Third branch-model slice and the closure of the loop: `agent-review` now accepts
the Phase 4b-1 `result:v1` changeset, mechanically verifies the declared files
on the integration branch, and — once every child goal of a parent is
`goal/done` — opens **exactly one** PR `issue/<parent#>` → `dev` for human
review/merge. Agents never merge and never push `dev`/`main`.
`.github/scripts/llm_json.sh` is unchanged and no role inlines `curl`.

## What changed (ONLY these 3 files)

- `.github/workflows/agent-review.yml` (main work)
  - **Permissions:** job gained `pull-requests: write` (kept `contents: read`,
    `issues: write`, `actions: write`); top-level stays `permissions: {}`; no
    `contents: write` (review never writes repo contents).
  - **New TL acceptance:** the `tl:v1` `kind` set widened to
    `code|docs|analysis|requirement|user-story` (both the `TL_SCHEMA` reader and
    the system prompt description). Everything else about `tl:v1` unchanged.
  - **New `result:v1`:** `RESULT_SCHEMA` replaced with the Phase 4b-1 shape
    (`summary`, `kind`, string-array `files`, string-array `changes`, `evidence`,
    `commit`, `merge_commit`, `task_branch`, `integration_branch`, boolean
    `needs_human`, `needs_human_reason`, numeric `attempt`). Missing/invalid →
    loud comment + `needs-human` + `exit 1`. `needs_human:true` → loud comment +
    `needs-human` + `exit 1`, with **no LLM call** (also no LLM when the payload
    is missing).
  - **Mechanical file verification (new, before the LLM):** for every
    `result.files` path, `gh api repos/<repo>/contents/<path>?ref=<integration>`
    (no git auth) → a non-empty `.sha` means `present`, else `MISSING`. Builds a
    `FILE_EVIDENCE` list and sets `MISSING_ANY`. Computes `AHEAD_BY` via
    `gh api repos/<repo>/compare/dev...<integration>` (fallback `0`). All of
    `FILE_EVIDENCE`, `AHEAD_BY`, the full `result` and the TL `acceptance` are
    included in the LLM user prompt; when a file is `MISSING` the prompt forbids
    a `done` verdict, and a post-LLM guard force-downgrades a `done` to `revise`.
  - **Verdict unchanged:** same `{verdict,reason,missing,guidance}` schema and
    `<!-- verdict:v1 -->` comment; `done` → `goal/done`; `revise` →
    `<!-- attempts:NEXT -->` (NEXT=ATTEMPT+1), `needs-human` + loud escalation
    when `NEXT > MAX_REVISE=3`, else `goal/tl` (+ the existing
    `agent-techlead` dispatch). No dispatch on `done`/`needs-human`.
  - **Parent termination + the single PR (new):** after a `done` verdict whose
    parent is complete (non-empty children, all `goal/done`) and not already
    marked, resolve `PINTEGRATION=issue/<parent#>` and recompute `PAHEAD_BY`.
    When `PAHEAD_BY > 0`, reuse an open PR for the same head
    (`gh pr list --head ... --state open`) or open ONE with
    `gh pr create --base dev --head "${PINTEGRATION}"`, title
    `[Issue #<parent#>] <parent title>`, and a body listing the goals + links +
    "Human review required; the agent will not merge. Do not merge until
    reviewed." When the branch is missing or `PAHEAD_BY == 0`, no PR is opened
    and the comment says "no changes to propose". Either way the parent gets
    `<!-- parent-done:v1 -->` + `status:done`, idempotently. **Never**
    `gh pr merge`, `git merge` to `dev`, or a `dev`/`main` push. The `ERR` trap
    still posts a loud comment and exits non-zero.
  - **Header comment** updated to describe the final PR and to state the review
    opens (but never merges) it and does not push `dev`/`main`.
- `.agents/orchestrator/STATE-MACHINE.md` — appended **§10 Final PR & human
  gate (Phase 4b-2)**: exactly one `issue/<parent#>` → `dev` PR when
  `ahead_by > 0`, idempotent by open PR head; human reviews/merges; agents never
  merge or push `dev`/`main`; `status:done` + `parent-done:v1`; the review needs
  `pull-requests: write` and no `contents: write`; the mechanical file check;
  and that non-dev-only parents still PR their markdown artifacts.
- `.agents/orchestrator/NOTES.md` (this section).

## Verification (actual output)

- `ruby -ryaml -e "YAML.load_file('.github/workflows/agent-review.yml')"` →
  `YAML OK`.
- Extracted all 4 `run:` blocks (Ruby YAML) and `bash -n` each → `bash -n OK`
  for all 4. (`shellcheck` not installed on the host.)
- Structural assertions (Ruby YAML + source scan): job permissions
  `{"contents"=>"read","issues"=>"write","pull-requests"=>"write",
  "actions"=>"write"}`, top-level `{}`; **no** `contents: write`;
  `gh pr create` present once with `--base dev --head "${PINTEGRATION}"`;
  **no** `gh pr merge`, **no** `git merge`, **no** `git push` to `dev`/`main`;
  new `result` schema (`merge_commit`, `all(.files[]; type=="string")`,
  `.attempt|type=="number"`, boolean `needs_human`) present; widened TL `kind`
  set present; `FILE_EVIDENCE` / `AHEAD_BY` / `compare/dev...` / contents-`?ref=`
  present; `parent-done:v1` + "no changes to propose" + the human-review note
  present.
- `jq -e` schema tests (on-disk schema strings): new result schema **accepts** a
  full valid object and **rejects** the old text-only shape, missing
  `merge_commit`, non-array `files`, string `needs_human`, and missing
  `attempt`; TL schema **accepts** `code/docs/analysis/requirement/user-story`
  and rejects `bogus`/`CODE`.
- **Mock `gh` + mock `llm_json.sh` end-to-end (42/42 assertions)** drove the
  extracted review step:
  - (a) all children `goal/done` + `AHEAD_BY=10` → **one** `gh pr create` with
    `head=issue/55`/`base=dev`, `parent-done:v1` + PR URL posted on the parent,
    `status:done`, goal `goal/done`, 1 LLM call; prompt contained
    `a/b.txt=present`, "ahead of dev by 10 commit(s)", and the acceptance item;
  - (b) re-run (same state) → no second PR, no second LLM call (verdict:v1
    idempotency + parent marker);
  - (b2) open PR already exists for `issue/55` and the parent is unmarked → no
    new PR, the existing PR URL is reused in the parent comment, `status:done`;
  - (c) `AHEAD_BY=0` → no PR, "no changes to propose" note, still `status:done`;
  - (d) one child not `goal/done` → no PR, no `parent-done:v1`, no `status:done`;
  - (e) `result.needs_human:true` → `needs-human`, **no** LLM call, no PR;
  - (f) `result:v1` missing → `needs-human`, **no** LLM call, no PR;
  - (g) declared file `c.md` MISSING while the model returned `done` → prompt
    flags `c.md=MISSING` + "MUST NOT be", verdict forced to `revise`, goal
    re-entered `goal/tl`, no PR.
- `git status --short` shows exactly the 3 intended files.

## Commit + push record (dev only — NEVER main)

- Message: `feat(review): accept result:v1, verify files, open the single human-gated PR (Phase 4b-2)`.
- Files in this commit (ONLY these 3):
  - `.github/workflows/agent-review.yml`
  - `.agents/orchestrator/STATE-MACHINE.md` (§10 appended)
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `c806309` — `git push origin dev` OK
  (`9479c31..c806309  dev -> dev`). This notes-record entry is a second,
  notes-only commit (its own SHA is recorded post-push, not invented here).

## Open risks / follow-ups

- **Live LLM/`gh`/PR unverified.** YAML parse + `bash -n` + structural + schema
  checks + a mocked end-to-end flow prove syntax and control flow only. The real
  Actions runner, the OpenRouter path, `pull-requests: write` on the worker
  token, branch protections, and the real `compare`/`contents`/`pr create`
  behavior have not run. First trial = a complete parent whose goals are all
  `goal/done`, then confirm one open `issue/<parent#>` → `dev` PR appears and no
  agent merge occurs.
- **`compare/dev...issue/<n>` with an unencoded slash.** The state-machine
  command is used verbatim; if the API rejects the slashed ref it falls back to
  `AHEAD_BY=0` → no PR (a soft failure that is still visible in the parent
  comment as "no changes to propose"). Worth confirming on the live runner; if
  needed, URL-encode the head ref (`issue%2F<n>`) in both compare and PR calls.
- **Review token scope widened.** `pull-requests: write` lets the review open
  PRs; it still has no `contents: write`, and the workflow contains no merge or
  `dev`/`main` push, so the only write beyond comments/labels is a PR.
- **Mechanical file check is per declared path only.** A result that lies about
  which files it touched (or omits the real deliverable) is not caught; the LLM
  still sees `changes`/`evidence` and the diff is human-reviewed in the final
  PR.
- **Non-dev parents with no code goals** still open a PR carrying the markdown
  artifacts (`.agents/issue-<parent#>/goal-<goal#>.md`); that is intended but
  means `dev` receives documentation commits once a human merges.
- **Parent completion still relies on `gh issue list --search` indexing**; a
  freshly labeled final child can be briefly stale, delaying PR creation. The
  `agent-review-<n>` concurrency group serializes review runs per goal and the
  block is idempotent, so a retry is safe.

---

# Phase 4c-1 — full-loop audit fixes: path guard, integration retry, bot guard, token budget, fence strip (`dev` only — NEVER main)

Blocking/Warning fixes from the full-loop audit that belong to the Programmer,
the shared LLM helper, and the Tech Lead. Five files. The review/orchestrator/
triage workflows are untouched. No push/PR/merge behavior is weakened: agents
still never push `dev`/`main` and never force-push.

## What changed

- **B1 + N2 + N3 — path guard hardened (`.github/workflows/agent-programmer.yml`).**
  The literal-prefix `case` loop was replaced by a single `jq` allowlist pass over
  the NORMALIZED path (`norm` strips one leading `./`), run before any write:
  - reject empty / absolute (`/…`) paths;
  - reject anything not matching the conservative charset
    `\A[A-Za-z0-9._/+@-]+\z` (letters, digits, `. _ / + @ -`);
  - reject any `..` segment, any `.git` component (incl. nested `sub/.git/x`),
    and the `.github/workflows` component sequence;
  - reject a leading dot segment unless it is `.agents/` or `.github/`.
  Validating in `jq` (not a line-based bash loop) also closes the embedded
  newline/control-character bypass: `\A…\z` is used because Oniguruma's `^…$`
  matches before a trailing newline. This rejects `./.github/workflows/x`,
  `./.git/config`, `sub/.git/x`, `../evil`, `/etc/passwd`, `a b.js`, and empty.
  The existing >25-file and >200000-byte caps are unchanged; any violation is a
  loud comment + `needs-human` + `exit 1` before anything is written.
- **B3 — bounded integration-update retry (`.github/workflows/agent-programmer.yml`).**
  Because concurrency is per-goal, sibling goals can push `issue/<parent#>`
  concurrently; the loser previously hard-failed on a non-fast-forward rejection
  and lost its merge. The integration update now retries up to
  `MAX_INTEGRATION_ATTEMPTS=5` (short `IATTEMPT*2`-second backoff):
  `fetch origin <INTEGRATION> → git checkout -B <INTEGRATION> origin/<INTEGRATION>
  → git merge --no-ff <TASK> -m <msg> → git push origin <INTEGRATION>`.
  On a rejected push it re-fetches/re-checkouts the latest origin and re-merges
  the (unchanged) task branch. A real merge conflict still does `git merge
  --abort` → loud + `needs-human` + `exit 1`; exhausted retries → loud +
  `needs-human` + `exit 1`. NEVER `--force`, and the only push targets remain
  `task/<goal#>` and `issue/<parent#>`.
  The fallback integration-branch creation is now race-safe: when
  `issue/<parent#>` is absent it is created locally from `origin/dev`, and a
  concurrent sibling creation makes the first push rejected; the retry simply
  fetches and uses the sibling's branch instead of failing.
- **B5 — bot guard allows human label recovery (both workflows).** Removed the
  `github.event.issue.user.type != 'Bot'` clause from the job `if:` in
  `agent-programmer.yml` and `agent-techlead.yml`. Goal issues are authored by
  `GITHUB_TOKEN` (Bot), so the documented "human re-applies the label" recovery
  never ran. `github.event.sender.type != 'Bot'` and the `workflow_dispatch`
  short-circuit are kept. (Other roles still carry the clause; out of scope.)
- **B6 — programmer completion budget (`.github/workflows/agent-programmer.yml`).**
  The programmer calls `llm_json.sh` with
  `--max-tokens "${PROGRAMMER_MAX_TOKENS:-16000}"` (the helper's 1500 default
  truncated full-file changesets → schema failure → `needs-human`). The budget is
  env-overridable via the repo variable `PROGRAMMER_MAX_TOKENS`
  (`${{ vars.PROGRAMMER_MAX_TOKENS || '16000' }}`). No other role's token budget
  changed.
- **N6 — fence stripping preserves interior fences (`.github/scripts/llm_json.sh`).**
  Replaced `sed '/^```/d'` (which deleted every fence line and corrupted content
  containing real fenced code) with a `strip_fences` awk helper that removes only
  one optional leading `^```[A-Za-z0-9]*$` line and one optional trailing
  `^```$` line, preserving every interior line byte-for-byte.
- **Docs.** `STATE-MACHINE.md` §9 safety guards rewritten to the allowlist
  (charset, normalized leading `./`, `.git` component, `.github/workflows`, caps)
  and a new *Integration update retry (bounded)* subsection documents the
  re-fetch/re-merge/push retry and the never-force / never-`dev`/`main` rule.
  This NOTES section.

## Verification (actual output)

- `ruby -ryaml` parses both workflows (`YAML OK`); every `run:` block extracted
  (5 programmer + 4 techlead) and `bash -n` on each → all OK. `bash -n
  .github/scripts/llm_json.sh` → OK.
- Path guard (jq filter extracted verbatim from the workflow, `jq`/bash
  harness): **24/24 pass**. Rejects `./.github/workflows/ci.yml`,
  `.github/workflows/ci.yml`, `.git/config`, `./.git/config`, `sub/.git/x`,
  `.git`, `../evil`, `a/../../b`, `/etc/passwd`, `a b.js`, `docs/x y.md`, empty,
  `x/.github/workflows/y`, `.ssh/id_rsa`, `.`; accepts `src/app.js`,
  `.agents/issue-1/goal-2.md`, `README.md`, `src/.eslintrc`,
  `.github/scripts/foo.sh`, `a/b-c_d+e@f.txt`. Embedded newline and tab paths are
  rejected (N3); a multi-file set with one bad path is rejected on the first
  violation.
- Fence stripper (`strip_fences` extracted verbatim): **7/7 pass**. Outer
  ` ```json ` / ` ``` ` wrappers stripped; non-fenced single-line and pretty JSON
  untouched; a payload with interior ``` fences survives intact with and without
  an outer wrapper; uppercase language tag stripped.
- Mock git race sim (real local bare `origin`, extracted retry block, `git` shim
  that injects a concurrent sibling commit, `sleep` shim):
  - normal: 2 integration-push attempts, rcs `1,0` → exactly one successful
    integration push, `INTEGRATION_PUSHED=true`; final `issue/55` contains
    `base.txt` + task `f.txt` + sibling `sib-1.txt` (both integrated);
  - conflict: `NEEDS_HUMAN … could not auto-merge`, 0 pushes, exit 1, remote tip
    unchanged;
  - exhausted: 5 attempts all rejected (rcs `1,1,1,1,1`, sleeps `2 4 6 8`),
    `NEEDS_HUMAN … rejected after 5 attempts`, exit 1;
  - fallback: `issue/55` absent at start, sibling creates it just before our
    create-push → first push rejected, retry fetches/re-merges, one successful
    push, remote contains both the task and sibling files.
- Push audit over the extracted `run:` blocks: only `git push -u origin
  "${TASK}"`, `git push origin --delete "${TASK}"`, and `git push origin
  "${INTEGRATION}"`; **zero** literal `dev`/`main` push targets (the only `dev`
  match is `2>/dev/null`) and **zero** `--force` commands (the sole `--force`
  token is the word in a comment).
- Bot guard: neither workflow contains `github.event.issue.user.type`; both keep
  `github.event.sender.type != 'Bot'` and the `workflow_dispatch` short-circuit.
- `git status --short` shows exactly the 5 intended files.

## Commit + push record (dev only — NEVER main)

- Message: `fix(agents): harden path guard, bounded integration retry, bot-guard recovery, token budget, fence strip (Phase 4c-1)`.
- Files in this commit (ONLY these 5):
  - `.github/workflows/agent-programmer.yml`
  - `.github/workflows/agent-techlead.yml`
  - `.github/scripts/llm_json.sh`
  - `.agents/orchestrator/STATE-MACHINE.md` (§9)
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `<recorded post-push>` — `git push origin dev` OK
  (`<old>..<new>  dev -> dev`). This notes-record entry is a second, notes-only
  commit (its own SHA is recorded post-push, not invented here).

## Open risks / follow-ups

- **Live runner unverified.** YAML/`bash -n`/`jq`/mock-git tests prove syntax and
  control flow only; the real Actions runner, `GITHUB_TOKEN` push permissions,
  branch protections, and concurrent sibling behavior across separate runners
  have not run. First live test = two sibling goals of one parent at
  `goal/ready`, then confirm both merges land on `issue/<parent#>`.
- **`git push` rejection cause is not distinguished.** Any non-zero `git push`
  (non-fast-forward vs transient auth/network) is treated as a concurrent update
  and retried; a persistent non-race error only surfaces after 5 attempts. It is
  bounded, loud, and never forced, so safe, but the log shows the real git error.
- **Leading-dot allowlist is conservative.** Paths whose first segment is a dot
  directory other than `.agents`/`.github` (e.g. `.gitignore`, `.env.example`)
  are now rejected where the old guard allowed them. Intended for hardening;
  widen the allowlist if a legitimate code goal needs such a path.
- **`jq` version dependency.** The guard uses Oniguruma `\A…\z` anchors and
  `startswith`; verified on jq 1.7 and standard on the ubuntu-latest jq 1.6
  (Oniguruma). A PCRE-built jq also accepts `\A…\z`.
- **`--max-tokens` is a cap, not a guarantee.** 16000 tokens is generous but a
  very large multi-file changeset could still truncate; the schema failure
  remains loud (`needs-human`) rather than silently partial.
- **`strip_fences` still removes a genuine trailing fence line.** A model reply
  whose legitimate last line is ``` alone is stripped; interior fences (the
  reported corruption) are preserved. This matches the mandated single
  leading/trailing strip.
- **Bot-guard change widens the human-recovery surface.** Removing the
  `issue.user.type` clause means a human re-applying `goal/ready`/`goal/tl` on a
  bot-authored goal now runs the role; `sender.type != 'Bot'` still blocks
  bot-triggered label edits, and `workflow_dispatch` remains the automated path.

