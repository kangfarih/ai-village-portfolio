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

> **SUPERSEDED by Phase 4b-1 (programmer now pushes task/issue branches).**
> The Phase-2a claim immediately below is retained only as history and is **no
> longer true**: the Programmer now writes the changeset's real files to a
> `task/<goal#>` branch and auto-merges (`--no-ff`) them into the
> `issue/<parent#>` integration branch, pushing those agent-owned branches
> (never `dev`/`main`, never `--force`). The deliverable is branch content, not
> a comment, and the human `/approve` (`agent-build`) gate is orthogonal to the
> loop. See the Phase 4b-1 section below.

- Programmer never pushes: the deliverable is text in a comment; applying it is
  the human `/approve` (agent-build) gate. No auto-apply.

> **END SUPERSEDED (Phase 2a) — see Phase 4b-1.**

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
- Fix commit: `2ab3bfe` — `git push origin dev` OK
  (`f73a32d..2ab3bfe  dev -> dev`).
- This notes-record entry is a second, notes-only commit (its own SHA is
  recorded post-push, not invented here).

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

---

# Phase 4c-2 — review PR-ahead via git, tolerant PR create, stale-result guard, REST child/dedupe queries, drop `goal/revise` (`dev` only — NEVER main)

Second batch of Blocking/Warning fixes from the full-loop audit: the PO review's
final-PR path and the orchestrator's goal dedupe. Five files. No push/PR/merge
behavior is weakened: agents still never push `dev`/`main` and never merge.

## What changed (ONLY these 5 files)

- **B2 — the final PR now opens: review ahead/branch/file checks moved from the
  GitHub API to git.** `gh api repos/<repo>/compare/dev...issue/<N>` put a raw
  `/` in a path param and 404'd, `|| echo 0` swallowed it, `AHEAD_BY` became 0
  and the single PR was never opened. The review checkout is now
  `fetch-depth: 0` + `persist-credentials: true` (read-only token still
  fetches); it runs `git fetch --no-tags origin dev` and, when present,
  `git fetch --no-tags origin "refs/heads/${INTEGRATION}:refs/remotes/origin/${INTEGRATION}"`.
  Branch absence is detected with `git ls-remote --exit-code --heads origin ...`
  and treated as "no branch";
  `AHEAD_BY="$(git rev-list --count "origin/dev..origin/${INTEGRATION}" ...)"`;
  file existence uses `git cat-file -e "origin/${INTEGRATION}:${path}"`. A
  transport/auth failure is never silently read as 0 — it trips the `ERR` trap.
- **B4 — tolerant/idempotent final-PR creation.** The parent marker +
  `status:done` are re-read immediately before finalizing;
  `gh pr list --head ... --state open` reuses an existing PR, else
  `gh pr create`; if create fails (a racing review won) it re-lists and reuses
  the winner's URL, otherwise surfaces the error through the `ERR` trap; the
  `<!-- parent-done:v1 -->` comment is only posted when the (re-read) marker is
  absent, and `status:done` is added idempotently. Still no `gh pr merge`, no
  push.
- **B5 — review bot guard allows human label recovery.** Removed the
  `github.event.issue.user.type != 'Bot'` clause from the review job `if:`
  (kept `github.event.sender.type != 'Bot'` and the `workflow_dispatch`
  short-circuit). Goal issues are Bot-authored, so the human re-label path now
  runs.
- **W1 + W4 + N4 — parent/child completion uses the REST list, not the search
  index.** The review's child query is now
  `gh issue list --label ai-goal --state all --limit 200 --json number,title,url,labels`
  filtered locally by exact title suffix `(from #<parent>)`; the same filtered
  list feeds the completion check, the PR body, and the parent comment.
- **W2 — stale `result:v1` cannot burn a revision.** Before any LLM call the
  review requires the latest `result:v1` `.attempt == ATTEMPT`; on mismatch it
  logs a "not ready for this attempt" note and exits 0 with no LLM call and no
  label/marker change.
- **W5 — orchestrator goal dedupe uses the REST list.** The delegate step's
  existing-goal lookup is now the REST list + local exact-suffix filter
  (matching the dispatch step); per-goal exact-title dedupe semantics are
  unchanged.
- **W7 — removed the dead `goal/revise` state.** Removed from
  `.github/labels.yml`, `STATE-MACHINE.md`, and the two workflows' self-heal
  `gh label create` lines; the contract now states explicitly that a `revise`
  verdict re-enters at `goal/tl` (no `goal/revise` label exists).
- **W8 — superseded banner in NOTES.** The Phase-2a "Programmer never pushes /
  deliverable is a comment" risk bullet is now wrapped in a clearly-marked
  `SUPERSEDED by Phase 4b-1 (programmer now pushes task/issue branches)` banner.
- **N5 — resolved integration branch in the review prompt.** The prompt renders
  the resolved `INTEGRATION` (result value or `issue/<parent#>` fallback) in
  both the mechanical-check heading and the file note.

## Verification (actual output)

- `ruby -ryaml` parses both workflows + `labels.yml` → `YAML OK`; every `run:`
  block extracted and `bash -n` → all 4 + 6 OK.
- Structural assertions: review has **no** `compare/` API call and **no**
  `gh api`; **no** `--search` anywhere in review/orchestrator; review job `if:`
  has **no** `issue.user.type`; `pull-requests: write` present; **no**
  `contents: write` in review; **no** `gh pr merge`; **no** `git push` in
  review; `gh pr create --base dev --head` present.
- Mock `gh` + real local git (bare `origin`) + mock `llm_json.sh` drove the
  extracted review step: **41/41** assertions pass — (a) all children done +
  branch ahead>0 → exactly one PR + `parent-done:v1` + `status:done` + one LLM
  call; (b) re-run → no second PR / no duplicate marker / no second LLM;
  (c) branch absent → no PR, "no changes to propose", still `status:done`;
  (d) stale `result.attempt != ATTEMPT` → no LLM, no verdict, no label change,
  exit 0; (e) another parent's goals (incl. `#99` and a `#155` boundary case)
  excluded by the exact-suffix filter; (f) `gh pr create` fails but a racing PR
  appears → reused, exit 0; (g) create fails with no PR → `ERR` trap, loud
  non-zero; (h) empty `integration_branch` renders the resolved `issue/55` in
  the prompt (no `issue/<unknown>`).
- Orchestrator W5 filter: exact-suffix keeps only `(from #7)`, excludes
  `(from #77)` / `(from #177)` / a longer title; per-goal exact-title dedupe
  skips only the exact existing title.
- `git status --short` shows exactly the 5 intended files.

## Commit + push record (dev only — NEVER main)

- Message: `fix(agents): git-based review PR checks, tolerant PR create, stale-result guard, REST child/dedupe queries, drop goal/revise (Phase 4c-2)`.
- Files in this commit (ONLY these 5):
  - `.github/workflows/agent-review.yml`
  - `.github/workflows/agent-orchestrate.yml`
  - `.github/labels.yml`
  - `.agents/orchestrator/STATE-MACHINE.md`
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Fix commit: `05593d7` — `git push origin dev` OK
  (`462ef59..05593d7  dev -> dev`).
- This notes-record entry: second, notes-only commit (its own SHA recorded
  post-push, not invented here).

## Open risks / follow-ups

- **Live runner unverified.** YAML/`bash -n`/mock-git tests prove syntax and
  control flow only; the real Actions runner, `GITHUB_TOKEN` read-only fetch,
  branch protections, and `pull-requests: write` have not run. First live trial =
  a complete parent whose goals are all `goal/done`, then confirm one open
  `issue/<parent#>` → `dev` PR appears.
- **`git ls-remote --exit-code` conflates no-ref with a transport error.** The
  preceding `git fetch --no-tags origin dev` proves connectivity, so a
  transport failure surfaces there (ERR trap) before branch detection; the
  `ls-remote` failure is therefore treated as branch-absent. If connectivity is
  lost only for the second command, it reads as "no branch" (no PR) rather than
  loud — narrow, and the parent still gets `status:done`.
- **Re-checking `status:done` before finalizing can, in a rare race, skip the
  marker comment.** The racing review posts the marker before adding
  `status:done`, so the marker exists; this only suppresses our duplicate.
- **`persist-credentials: true` + `contents: read`** stores the read-only token
  in git config for the job; the workflow contains no push step, so it is
  fetch-only. A future added push step would need an explicit permission bump.

---

# Phase 4c-3 — final PR head passes the repo's own PR checks (`dev` only — NEVER main)

Last full-loop audit Blocking fix (B7). The loop ends by opening one PR
`issue/<parent#>` → `dev`, but the repo's own PR checks rejected that head:
`branch-lint` only accepted `session/...` and `ci-smoke`'s 400-line diff gate
always failed a batched integration PR. Agents still never push `dev`/`main`,
never force-push, and never merge; no other behavior changed. Only the two
workflows were modified (plus this NOTES record). No role/workflow execution
logic changed.

## What changed (ONLY these 3 files)

- **`.github/workflows/branch-lint.yml`** — the head-naming regex now accepts
  EITHER existing convention:
  - `^session/(T|B)-[0-9]+-[a-z0-9-]+-[0-9]{8}-[a-z]+$` (human session), or
  - `^(issue|task)/[0-9]+$` (agent integration `issue/<parent#>`; `task/<goal#>`
    accepted for completeness though task branches are not PR heads in the loop).

  Combined filter:
  `^(session/(T|B)-[0-9]+-[a-z0-9-]+-[0-9]{8}-[a-z]+|(issue|task)/[0-9]+)$`.
  The error message now lists both accepted forms. The `BASE == dev` check and
  the least-privilege job `permissions` (`contents: read`,
  `pull-requests: read`; top-level `{}`) are unchanged.
- **`.github/workflows/ci-smoke.yml`** — the `Diff size guard (<400 lines)` step
  now begins by detecting an integration head
  (`echo "${{ github.head_ref }}" | grep -Eq '^issue/[0-9]+$'`) and, when it
  matches, echoes `SKIP: batched integration PR (issue/<n>)` and `exit 0` **for
  that step only**. A one-PR-per-parent batched integration PR intentionally
  carries every child goal and will always exceed 400 lines, so the size gate is
  meaningless for it. A short YAML/`run:` comment explains the exemption. Every
  other step (SPEC escapes, `node --check`, secrets grep, `.env/.pem/.key`
  filename gate) still runs for `issue/*` PRs. Triggers and permissions
  unchanged.
- **`.agents/orchestrator/NOTES.md`** (this section).

## Known limitation — `GITHUB_TOKEN` PRs do not trigger `pull_request` workflows

A PR opened with the workflow `GITHUB_TOKEN` does **not** trigger
`pull_request`-event workflows (GitHub's recursion/loop-prevention rule). The
final loop PR is opened by `agent-review` using `GITHUB_TOKEN`, so
`branch-lint` and `ci-smoke` **may not run on it at creation time** — the fix
above makes the head *acceptable to* those checks, but does not guarantee they
execute. The backstop is a human push (or a re-open/synchronize by a
human/App identity), or branch-protection required-status-check configuration
that treats the checks appropriately; that config lives outside these files and
is not changed here.

## Verification (actual output)

- `ruby -ryaml -e "YAML.load_file(...)"` → `branch-lint YAML OK`,
  `ci-smoke YAML OK`.
- All `run:` blocks extracted via Ruby YAML and `bash -n` each → `bash -n OK`
  for `branch-lint[0]` and `ci-smoke[0..3]` (5 total; `shellcheck` not installed
  on the host).
- Head-naming grep logic (on-disk regex tested directly):
  - `ACCEPT  issue/55`
  - `ACCEPT  task/55`
  - `ACCEPT  session/T-010-hero-20260910-ab`
  - `REJECT  dev`
  - `REJECT  issue/`
  - `REJECT  issue/abc`
  - `REJECT  feat/x`
- Integration skip detection (on-disk `^issue/[0-9]+$`):
  - `SKIP    issue/55`
  - `RUN     issue/55x`
  - `RUN     task/55`
  - `RUN     session/T-010-hero-20260910-ab`
  - `RUN     feat/x`
- `git status --short` shows exactly the 3 intended files.

## Commit + push record (dev only — NEVER main)

- Message: `fix(ci): accept issue/<parent#> PR head and exempt batched integration PR from size guard (Phase 4c-3)`.
- Files in this commit (ONLY these 3):
  - `.github/workflows/branch-lint.yml`
  - `.github/workflows/ci-smoke.yml`
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `f0bfc0b` — `git push origin dev` OK
  (`8ec6cbe..f0bfc0b  dev -> dev`).
  This notes-record entry is a second, notes-only commit recording the SHA
  (its own SHA is recorded post-push, not invented here).

## Open risks / follow-ups

- **`GITHUB_TOKEN` PRs may not run these checks at creation** (see limitation
  above). Until branch protection/App identity is configured, a green
  `branch-lint`/`ci-smoke` result on the agent PR is not automatic; a human
  re-push or required-check config is the backstop.
- **`task/<n>` now passes `branch-lint` as a PR head** for completeness. In the
  loop `task/<goal#>` branches are auto-merged into `issue/<parent#>` and are not
  PR heads, so this only widens the accepted pattern by one harmless form.
- **The size guard is skipped per-step, not bypassed globally.** A malicious or
  accidental `issue/<n>` PR could carry an arbitrarily large diff past the size
  gate; the remaining smoke steps (escapes, `node --check`, secrets, secret
  filenames) still run, and human review of the batched PR remains the gate.
- **Regex is intentionally strict** (`^issue/[0-9]+$`, no leading zeros
  restriction): `issue/0` and `issue/007` would pass; harmless for head naming.

---

# Phase 5a — non-development goals become linked GitHub tickets (`dev` only — NEVER main)

Non-development goals (`docs`/`analysis`/`requirement`/`user-story`) no longer
become `ai-goal` sub-issues that travel the branch/TL/Programmer/PR loop. The
orchestrator now turns each one into a **linked ticket** (`ai-ticket` + a
`kind/*` label) whose deliverable is the requirement/user-story/analysis itself;
code goals are unchanged. A docs-only parent gets no integration branch and no
PR — the orchestrator marks it complete itself. `.github/scripts/llm_json.sh`
is unchanged and no role inlines `curl`.

## What changed (ONLY these 5 files)

- `.github/workflows/agent-orchestrate.yml`
  - **LLM schema untouched**: `{title, detail, kind}` and the `kind` enum
    (`code|docs|analysis|requirement|user-story`) are exactly as before. The
    system prompt now states that for non-code kinds `detail` is the **full
    markdown body** of the deliverable (e.g. Problem / User Story / Acceptance
    Criteria for requirement/user-story; findings + recommendation for analysis).
  - **Kind-aware branch step**: `CODE_COUNT` is computed over the (≤6) goals and
    the `issue/<parent#>` integration branch is created **only when
    `CODE_COUNT > 0`**; with zero code goals the step is skipped and logged.
    The per-element `jq -e` contract guard now runs **before** branch creation.
  - **Kind-aware goal loop**: `kind: code` goals keep today's behavior exactly
    (`[GOAL] <title> (from #N)`, `ai-goal` + `goal/tl`, exact-title dedupe, body
    with `Kind:`/`Parent:`/`Integration branch:`). Non-code goals create a ticket
    titled `[<Kind Title Case>] <title>` (`user-story` → `User Story`) with
    labels `kind/<kind>` + `ai-ticket` (no `ai-goal`/`goal/tl`) and a body
    `<!-- agent-ticket:v1 origin:#N -->` / `## <Kind>` / `detail` / `Origin: #N`.
    Created via `gh issue create` (stdout URL; no `--json`/`--jq`), quoted args.
  - **Ticket idempotency**: `gh issue list --label ai-ticket --state all --limit
    200 --json title,body` is filtered locally; a ticket is skipped only when an
    issue with the exact title has a body containing `Origin: #N`. Code goals
    keep the exact-title suffix dedupe.
  - **Summary + docs-only completion**: the `<!-- orchestrator:v1 -->` comment
    lists code goals and tickets separately; when `CODE_COUNT == 0` it also posts
    `<!-- parent-done:v1 -->` and adds `status:done` (idempotent marker read;
    `--add-label` is itself idempotent). `triage/accepted` is still added last.
  - **Dispatch**: `agent-techlead` is dispatched only for code goals — the
    dispatch query is scoped to `ai-goal` issues still at `goal/tl`, which tickets
    never carry.
  - **Self-heal labels**: the Ensure step now also creates `ai-ticket`,
    `kind/feature`, `kind/bug`, `kind/requirement`, `kind/user-story`,
    `kind/analysis`, `kind/docs` (existing labels kept).
  - Unchanged: `ERR` trap (`v1-error`), `contents: write`/`issues: write`/
    `actions: write`, and no push to `dev`/`main` (the only push is
    `issue/<N>`).
- `.github/workflows/agent-programmer.yml`
  - **Non-dev path retired**: the `NONDEV` branch, the non-dev system prompt and
    the collapse to `.agents/issue-<parent#>/goal-<goal#>.md` are removed.
  - **Defensive guard**: if the parsed `tl:v1` `kind != "code"`, it posts a loud
    comment, moves the goal to `needs-human` (removing `goal/building`) and exits
    1 — without creating a branch. Changeset schema, path allowlist, bounded
    integration retry, guards, `result:v1`, and dispatch are unchanged.
- `.github/labels.yml` — appended `ai-ticket`, `kind/feature`, `kind/bug`,
  `kind/requirement`, `kind/user-story`, `kind/analysis`, `kind/docs` (reference
  only; `kind/task` stays).
- `.agents/orchestrator/STATE-MACHINE.md` — §9 `issue/<parent#>` creation is
  now conditional on ≥1 code goal; the non-dev markdown-artifact path is removed
  and replaced by a pointer to the new **§11 Non-development flow** (ticket
  title/labels/body/marker, ticket idempotency, docs-only `status:done`,
  code-only dispatch, the Programmer guard). §1/§2/§10 wording aligned.
- `.agents/orchestrator/NOTES.md` (this section).

## Verification (actual output)

- `ruby -ryaml -e "YAML.load_file(...)"` → `YAML OK` for
  `agent-orchestrate.yml`, `agent-programmer.yml`, `labels.yml`.
- Extracted all 11 `run:` blocks (Ruby YAML) and `bash -n` each →
  `bash -n OK` for all 11. (`shellcheck` not installed on the host.)
- Structural assertions:
  - branch creation guarded by `CODE_COUNT` (`CODE_COUNT=0` ⇒ skip); the
    per-element contract guard runs before it;
  - `gh issue create` has **no** `--json`; code goal create uses
    `ai-goal`+`goal/tl`, ticket create uses `kind/${KIND}`+`ai-ticket`;
  - dispatch query is `gh issue list --label ai-goal ...` + `goal/tl`, so
    tickets are never dispatched;
  - the only `git push` in the orchestrator is
    `git push -u origin "issue/${ISSUE_NUMBER}"`; programmer pushes are
    `${TASK}`/`${INTEGRATION}` (plus the mandated task delete) — **zero**
    `dev`/`main` push targets and zero `--force`;
  - `NONDEV`, `.agents/issue-<parent#>/goal-<goal#>.md` and the non-dev system
    prompt are gone from the Programmer; the `kind != "code"` guard is present;
  - all 7 new labels exist in both the self-heal step and `labels.yml`.
- **Mock `gh` + mock `git` + extracted orchestrator run blocks — 43/43
  assertions pass:**
  - (a) all-non-dev goals → 0 branches, 3 tickets with correct titles/labels
    (`ai-ticket` + `kind/*`, no `ai-goal`), `Origin: #55` bodies,
    `<!-- parent-done:v1 -->` + `status:done` + `triage/accepted`, 0 dispatches;
  - (b) mixed → exactly 1 branch `issue/55`, 1 code goal (with
    `Integration branch: issue/55`) + 2 tickets, no parent-done, dispatch step
    runs `agent-techlead.yml` once with `issue_number=1`;
  - (c) re-run with the goal progressed past `goal/tl` → no duplicate
    goals/tickets, no duplicate branch, no duplicate dispatch, single summary
    comment;
  - (d) `gh issue create` failure on a ticket → `<!-- orchestrator:v1-error -->`
    comment + non-zero exit, no branch, no parent-done.
- **Mock `gh` + extracted Programmer run block — 10/10 assertions pass:**
  `kind: docs` → loud "non-development / should not reach the Programmer"
  comment, `goal/building` removed + `needs-human` added, no `goal/review`, **no
  git command**; `kind: code` passes the guard and reaches the missing-key
  branch (proving the guard is code-only).
- `git status --short` shows exactly the 5 intended files.

## Commit + push record (dev only — NEVER main)

- Message: `feat(agents): non-dev goals become linked ai-ticket issues instead of branches (Phase 5a)`.
- Files in this commit (ONLY these 5):
  - `.github/workflows/agent-orchestrate.yml`
  - `.github/workflows/agent-programmer.yml`
  - `.github/labels.yml`
  - `.agents/orchestrator/STATE-MACHINE.md` (§9 updated, §11 appended)
  - `.agents/orchestrator/NOTES.md` (this section)
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `ae8c759` — `git push origin dev` OK
  (`47ce866..ae8c759  dev -> dev`, after rebasing onto the `origin/dev`
  `Merge pull request #14` commit that landed mid-task).
  This notes-record entry is a second, notes-only commit recording the SHA
  (its own SHA is recorded post-push, not invented here).

## Open risks / follow-ups

- **Live runner unverified.** YAML parse + `bash -n` + structural checks + the
  mocked orchestrator/programmer flows prove syntax and control flow only. The
  real Actions runner, the OpenRouter path, and real `gh issue
  create`/`list`/`comment` behaviour have not run. First live trial = a parent
  labeled `ai-orchestrate` with a valid `OPENCODE_API_KEY` and at least one
  non-code goal, then confirm the linked `ai-ticket` issues and (mixed) one
  `ai-goal`.
- **Ticket dedupe keys on the exact generated title.** A human who edits a
  ticket title would defeat the dedupe and a re-run could create a duplicate;
  the `Origin: #N` body marker still prevents cross-parent collisions. Acceptable
  for v1.
- **`kind/feature`/`kind/bug` labels are not produced by the goal LLM** (its
  `kind` enum has no feature/bug); they exist for triage/humans and future
  kinds. Only `kind/requirement|user-story|analysis|docs` are emitted here.
- **`gh issue list --limit 200`** is the same bounded lookup the code-goal dedupe
  already uses; a repo with >200 tickets of one label could miss a match and
  duplicate on re-run. The orchestrator concurrency group serializes runs.
- **Docs-only parent completion is orchestrator-owned**, not review-owned. If a
  docs-only parent already carries `status:done` from elsewhere, the marker
  comment is still posted once; both operations are idempotent.
- **Existing non-dev goals created before Phase 5a** (already `ai-goal` +
  `goal/tl` with `Kind: docs`) still reach the Programmer and now hit the
  defensive guard → `needs-human`. They are not migrated to tickets
  automatically; a human closes/re-labels them.

---

# Phase 5b — `agent-triage` LLM-classifies the issue `kind` (`dev` only — NEVER main)

`agent-triage` no longer hardcodes `kind/task`. It now makes one `llm_json.sh`
call (`--effort low`) to classify the issue into exactly one of
`feature | bug | task | requirement | user-story` and applies the matching
`kind/<kind>` label. Triage must stay green: any classification failure falls
back to `kind/task`. `.github/scripts/llm_json.sh` is unchanged and the workflow
inlines no `curl`.

## What changed (ONLY these 3 files)

- `.github/workflows/agent-triage.yml`
  - **New step `Classify issue kind (LLM, never fails)` (`id: classify`)**,
    inserted before the label step:
    - fetches the issue with
      `gh issue view "$ISSUE_NUMBER" --json title,body --jq '{title, body}'`
      (`GH_TOKEN: ${{ github.token }}`); `|| echo '{}'` keeps a fetch failure
      from breaking triage;
    - writes the system prompt (exactly one of feature/bug/task/requirement/
      user-story; requirement = spec/decision/acceptance-criteria; user-story =
      "as a … I want … so that …"; bug = defect; feature = new capability; task
      = anything else/chore) and the user file (`title + "\n\n" + body` via
      `jq -n --arg`), so untrusted issue text is never shell-interpolated;
    - calls `bash .github/scripts/llm_json.sh` with
      `--out /tmp/triage_kind.json`,
      `--schema 'type=="object" and (.kind=="feature" or .kind=="bug" or
      .kind=="task" or .kind=="requirement" or .kind=="user-story")'`,
      `--effort low`, and env `OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}`
      / `MODEL: thinkingmachines/inkling:free`.
    - **Never fails**: the helper runs inside `if … then … else … fi`, so a
      non-zero exit (missing/invalid key, non-200, bad JSON) only logs an
      `::warning::`; `KIND` defaults to `task`. On success `.kind` is read and
      validated against the 5-kind set. `KIND` is exported via
      `echo "kind=$KIND" >> "$GITHUB_OUTPUT"`.
    - The key is passed only via `env` and is never echoed.
  - **Apply triage labels** now reads `KIND: ${{ steps.classify.outputs.kind }}`
    (defaulting to `task` when empty/unknown), self-heals all five
    `kind/feature|bug|task|requirement|user-story` labels plus
    `priority/important-soon` and `triage/accepted`
    (`gh label create … 2>/dev/null || true`), and applies
    `--add-label "priority/important-soon,kind/${KIND},triage/accepted"`. No
    hardcoded `kind/task` remains.
  - **Post triage comment** reads the same `steps.classify.outputs.kind` and
    adds a `Classified kind: ${KIND}` line, keeping the existing DoR checklist,
    the Agent/Model line, and the "Do NOT open PRs. Do NOT push. Do NOT merge."
    line.
  - Unchanged: the human-only `if:` guard, top-level `permissions: {}` + job
    `contents: read` / `issues: write` / `pull-requests: read`, the
    `fetch-depth: 1` + `persist-credentials: false` checkout, and the
    `agent-triage-<n>` / `cancel-in-progress: false` concurrency.
- `.agents/orchestrator/STATE-MACHINE.md` — the triage-owned-label note now says
  `kind/<kind>` (not `kind/task`) and a new **Triage classification** subsection
  documents the 5-kind LLM classification, the applied labels, the
  `kind/task` fallback on any LLM failure ("triage must stay green"), and that
  all model traffic goes through `llm_json.sh --effort low` with no inline
  `curl`.
- `.agents/orchestrator/NOTES.md` (this section).

## Verification (actual output)

- `ruby -ryaml -e "YAML.load_file('.github/workflows/agent-triage.yml')"` →
  `YAML OK`; all 4 `run:` blocks extracted (Ruby YAML) and `bash -n` each →
  `bash -n OK` for all 4. (`shellcheck` not installed on the host.)
- Structural assertions:
  - `bash .github/scripts/llm_json.sh` present once with the 5-kind `--schema`;
  - **no** inline `curl` in the workflow;
  - all five `gh label create "kind/…"` self-heal lines present;
  - the only `--add-label` is
    `"priority/important-soon,kind/${KIND},triage/accepted"` — no hardcoded
    `kind/task` target;
  - `OPENCODE_API_KEY` appears **only** as
    `OPENCODE_API_KEY: ${{ secrets.OPENCODE_API_KEY }}` (no echo/reference in a
    `run:` body);
  - `id: classify` + `steps.classify.outputs.kind` wired into both the label and
    comment steps;
  - the helper call is the `if bash .github/scripts/llm_json.sh` condition.
- **Mock `llm_json.sh` + mock `gh`, driving the extracted classify + label +
  comment steps — 10/10 assertions pass:**
  - each of the 5 kinds (`feature`, `bug`, `task`, `requirement`, `user-story`)
    → `kind=<k>` in the step output and `kind/<k>` + `priority/important-soon` +
    `triage/accepted` in the applied labels, classify exit 0;
  - helper failure (non-zero, no output file) → output `task`, applied
    `kind/task`, `::warning::` emitted, classify exit 0 (job not failed);
  - empty output file (helper exit 0) → output `task`, applied `kind/task`,
    classify exit 0;
  - the comment body states `Classified kind: bug` and still contains the DoR
    checklist and the Do-NOT-PRs/push/merge line.

## Commit + push record (dev only — NEVER main)

- Message: `feat(triage): LLM-classify issue kind and apply kind/<kind> label (Phase 5b)`.
- Files in this commit (ONLY these 2):
  - `.github/workflows/agent-triage.yml`
  - `.agents/orchestrator/STATE-MACHINE.md`
- Push: `git push origin dev` (no `-i`, no `--force`, no `--no-verify`).
- Commit SHA + push result: `a332da1` — `git push origin dev` OK
  (`ec6a0ff..a332da1  dev -> dev`). This notes-record entry is a second,
  notes-only commit recording the SHA (its own SHA is recorded post-push, not
  invented here).

## Open risks / follow-ups

- **Live LLM unverified.** YAML parse + `bash -n` + structural checks + the
  mocked flow prove syntax and control flow only. The real OpenRouter path has
  not run; first live trial = an issue labelled `ai-triage` with a valid
  `OPENCODE_API_KEY`, then confirm the comment's `Classified kind:` and the
  applied `kind/<kind>` match the issue.
- **Free-model misclassification.** The schema constrains shape, not judgment;
  a wrong kind produces a wrong `kind/*` label (still green). A human can
  re-apply `ai-triage` after editing, and a later run re-labels.
- **A second `kind/*` is never removed.** Re-classifying an issue adds the new
  `kind/<kind>` but does not remove a stale one from a previous run, so an issue
  can accumulate more than one `kind/*` label. Triage runs are human-triggered
  and rare; acceptable for v1.
- **`gh issue view` failure is soft.** It is wrapped (`|| echo '{}'`), so a
  transient read failure yields an empty title/body prompt and likely a
  `kind/task` fallback rather than a hard failure — consistent with "triage must
  stay green".
- **`/tmp/triage_kind.json` is cleared before the call** (`rm -f`) so a stale
  file from a prior run cannot be misread as a fresh classification.

---

# Phase 5c — adversarial audit fixes (`dev` only — NEVER main)

Blocking + Warning + Nitpick fixes from the Phase 5 adversarial audit. Most work
is in `agent-orchestrate.yml`; the triage/review workflows and the state-machine
contract are also updated. No push/PR/merge behavior is weakened: agents still
never push `dev`/`main`, never force-push, and never merge.

## What changed (ONLY these 5 paths; 4 in the fix commit, this NOTES record in the second)

### Blocking

- **B1 — exact ticket dedupe marker** (`.github/workflows/agent-orchestrate.yml`).
  The ticket dedupe previously tested a bare substring `Origin: #<parent>`, so
  parent `#1` was falsely satisfied by parent `#12`'s body (`Origin: #12`
  contains `Origin: #1`) and tickets were silently dropped; a prompt-injected
  `Origin: #N` line in a detail body could self-collide. The step now builds
  `TICKET_MARKER="<!-- agent-ticket:v1 origin:#${ISSUE_NUMBER} -->"` and tests
  `.body | contains($TICKET_MARKER)` — the exact delimited marker the workflow
  writes, including the ` -->` terminator — keeping the exact-title check. Ticket
  bodies still contain that exact marker (now emitted first).
- **B2 — docs-only completion guard** (`.github/workflows/agent-orchestrate.yml`).
  When `CODE_COUNT == 0` the orchestrator unconditionally posted
  `<!-- parent-done:v1 -->` + `status:done`. `CODE_COUNT` reflects only the
  current run's `goals.json`, so a re-run (or manually-created children) could
  mark a mixed parent done while an `ai-goal` child was still building, making
  `agent-review` skip its whole termination block (incl. `gh pr create`) and
  strand the integration branch. Before marking done, the step now lists this
  parent's `ai-goal` children and computes `UNFINISHED` (title ends exactly with
  `(from #<parent>)`, null-guarded via `(.title // "")`, and no `goal/done`
  label). If non-zero it logs an `::notice::` and does **not** post the marker or
  add `status:done`, leaving termination to `agent-review`. The parent-marker
  idempotency check is retained inside the allow path.

### Warnings

- **W1 — orchestrator token budget.** The `llm_json.sh` call now passes
  `--max-tokens "${ORCHESTRATOR_MAX_TOKENS:-8000}"` (was the 1500 default, too
  small for full-markdown details across up to 6 goals).
- **W2 — trusted metadata before untrusted LLM detail.** Code-goal bodies now
  emit `Kind:`/`Integration branch:`/`Parent:`/`Acceptance:` FIRST, then the
  detail; ticket bodies emit the exact marker + `Origin:` + `Kind:` first, then
  the heading and detail. The model `detail` is passed through
  `strip_trusted_lines` (`grep -v -E '^(Parent:|Origin:|Kind:|Integration
  branch:|<!--)'`) before embedding, so a prompt-injected metadata line cannot
  shadow the trusted one (`agent-programmer.yml` extracts `Parent:` with
  `sed … | head -n1`, and the trusted line is now first anyway).
- **W3 — untrusted titles/details neutralized.** `sanitize_title` collapses
  newlines/tabs, squeezes whitespace, and caps the title at 120 characters
  before `gh issue create`; `neutralize_mentions` inserts a zero-width space
  after every `@` (`sed 's/@/@\xE2\x80\x8B/g'`, U+200B) in the title and detail
  so model text cannot emit live GitHub mentions.
- **W4 — same-run duplicate titles deduped.** Immediately after `goals.json`
  passes the contract guard and before `COUNT`/`CODE_COUNT` are computed, the
  step runs `jq 'unique_by([.kind,.title])' goals.json > /tmp/goals.dedup.json
  && mv … goals.json`, then recomputes counts. `RAW_COUNT` (pre-dedupe length) is
  captured for N1.
- **W5 — loud ticket-list validation.** After fetching `EXISTING_TICKETS_JSON`,
  a plain `printf '%s' "$EXISTING_TICKETS_JSON" | jq -e 'type=="array"'
  >/dev/null` runs so a garbled/empty body trips the `ERR` trap; the dedupe
  `jq` no longer uses `2>&1` (the `>/dev/null` is kept because `jq -e`'s
  false-result exit status is the branch condition).
- **W6 — triage clears stale `kind/*`** (`.github/workflows/agent-triage.yml`).
  Before adding `kind/${KIND}` the step loops
  `for k in feature bug task requirement user-story` and runs
  `gh issue edit "$ISSUE_NUMBER" --remove-label "kind/$k" 2>/dev/null || true`,
  so a re-classification replaces the prior kind instead of accumulating. All
  five self-heal `gh label create` lines are kept.
- **W7 — review is code-only** (`.github/workflows/agent-review.yml`). The
  system prompt now says only `kind: code` goals reach review (non-dev kinds are
  `ai-ticket` issues and never enter the loop), and a defensive guard after the
  `tl:v1` schema check escalates a non-code `kind` to a loud comment +
  `needs-human` + `exit 1` before any LLM call (symmetric with the Programmer's
  guard). The `TL_SCHEMA` enum is deliberately left as-is so the guard produces
  the specific message.
- **W8 — STATE-MACHINE `kind/*` contradiction resolved**
  (`.agents/orchestrator/STATE-MACHINE.md`). The old "triage-owned, the goal loop
  never sets a `kind/*`" wording now states: goal **issues** never carry
  `kind/*`; orchestrator-emitted `ai-ticket` issues carry
  `{docs, analysis, requirement, user-story}`; triage-classified issues carry
  `{feature, bug, task, requirement, user-story}`. §11 documents W3 sanitizing,
  W2 trusted-first bodies, B1 exact-marker dedupe, W4 goal dedupe, and the B2
  guard; the triage section notes the enum intentionally omits `docs`/`analysis`
  and that re-classification replaces the prior `kind/*`.

### Nitpick

- **N1 — >6 proposals surfaced.** When the pre-dedupe array length exceeds 6 the
  step logs `::notice::…` and adds a note to the summary comment (in addition to
  the existing `[:6]` cap), so a dropped 7th goal is visible.

## Verification (actual output)

- `ruby -ryaml -e "YAML.load_file('<f>')"` → `YAML OK` for
  `agent-orchestrate.yml`, `agent-triage.yml`, `agent-review.yml`.
- All `run:` blocks extracted via Ruby YAML and `bash -n` each →
  `bash -n OK` for all 6 (orchestrate) + 4 (triage) + 4 (review) = 14.
  (`shellcheck` not installed on the host.)
- **Unit (`jq`/bash) — 19/19 + 1 corrected cap check pass:**
  - **B1:** own marker `<!-- agent-ticket:v1 origin:#1 -->` matches `true`;
    parent `#12`'s body matches `false` (while the old `Origin: #1` substring
    would have matched `true` — reproduced for contrast); a body carrying only
    an injected `Origin: #1` (no marker) matches `false`.
  - **B2:** all-done children → `UNFINISHED=0` (allow); one `goal/building`
    child → `1` (block); no children → `0`; another parent's `(from #77)` child
    → `0`; a `null` title does not crash (null guard).
  - **W4:** `unique_by([.kind,.title])` reduces 4 items (2× code/A, docs/A,
    code/B) to 3 and keeps `docs/A` alongside `code/A`.
  - **W3:** `  hello\nworld\t  foo   bar  ` → `hello world foo bar`; a 200-char
    title caps at 120 chars after assignment; `@alice`/`@bob` produce the
    `40 e2 80 8b` byte sequence after each `@` (two `@` glyphs kept);
    `strip_trusted_lines` drops `Parent:`/`Kind:`/`Origin:`/`<!--` lines and
    keeps `normal line`.
  - **W6:** the removal loop and the exact `--remove-label "kind/$k"` line are
    present; the non-current set for `kind=bug` is
    `feature task requirement user-story`.
- **Mock `gh` + the extracted on-disk delegate step — 19/19 assertions pass:**
  - A (docs-only, duplicate title + injected `Parent: #999`/`Origin: #1`/`Kind:`
    /`<!-- evil -->` + `@alice`): exactly **1** create (W4); body begins with
    the exact marker then trusted `Origin: #1` and `Kind: requirement`; injected
    `Parent:`/the detail's `Origin:`/`<!-- evil -->` are gone; ZWSP byte present
    and literal `@alice` absent; `parent-done:v1` + `status:done` +
    `triage/accepted` applied.
  - B (docs-only + one `goal/building` child): 1 ticket still created, **no**
    `parent-done:v1`, **no** `status:done`, notice logged (B2).
  - B2 (all children `goal/done`): `parent-done:v1` posted (allow).
  - C (B1): body with `<!-- agent-ticket:v1 origin:#12 -->` does **not** block
    parent `#1` → ticket created.
  - D (B1): body with the exact `origin:#1` marker → skipped, no create.
  - E (W5): `tickets_list.json` = `NOT JSON {{{` → `ERR` trap, one
    `orchestrator:v1-error` comment, 0 creates, exit 5.
- **W7 mock (extracted review step, mock `gh` + sentinel `llm_json.sh`):** a
  `tl:v1` payload with `kind: docs` → `::error::tl:v1 kind is not code (docs)`,
  loud comment, `--remove-label goal/review --add-label needs-human`, exit 1,
  **no** LLM call. With `kind: code` the guard does **not** fire (proceeds to
  the next check). Prompt grep: the code-only wording is present and the old
  "deliver a markdown artifact on the integration branch" wording is gone.
- `git status --short` / `git diff --stat` touch only the 5 allowed paths.

## Commit + push record (dev only — NEVER main)

- Message: `fix(agents): Phase 5 audit fixes — exact ticket dedupe, docs-only
  child guard, trusted-first bodies, triage kind reset, review code guard`.
- Fix commit `b2dc203` — `git push origin dev` OK
  (`fa0ef2f..b2dc203  dev -> dev`). Files in the fix commit (4):
  `.github/workflows/agent-orchestrate.yml`,
  `.github/workflows/agent-triage.yml`, `.github/workflows/agent-review.yml`,
  `.agents/orchestrator/STATE-MACHINE.md`.
- This notes-record entry is a second, notes-only commit recording the SHA
  (its own SHA is recorded post-push, not invented here). Total diff for the
  round is the 5 paths listed above.

## Open risks / follow-ups

- **Live runner unverified.** YAML/`bash -n`/`jq` unit tests + mocked
  `gh`/delegate/review flows prove syntax and control flow only. The real
  Actions runner, the OpenRouter path, and real `gh issue
  list/create/comment/edit` behaviour have not run.
- **Title sanitizing changes the dedupe key.** `sanitize_title` +
  `neutralize_mentions` are applied before the title is used for both dedupe and
  creation, so re-runs are self-consistent. A goal/ticket created before Phase 5c
  whose model title contained unusual whitespace or an `@` may not match the new
  sanitized title and could be recreated once; the `Origin:`/`endswith` scoping
  still prevents cross-parent collisions.
- **W4 `unique_by` sorts.** `jq unique_by` orders by `[kind,title]`, so the
  "first 6" kept after dedupe are no longer in the LLM's original order. Bounded
  and visible via N1; acceptable for v1.
- **W2 strips legitimate-looking detail lines.** A detail line that legitimately
  starts with `Kind:`/`Parent:`/`Origin:`/`Integration branch:` or `<!--` is
  dropped. That is the intended anti-shadowing trade-off; the marker/heading and
  trusted lines are preserved.
- **`sed` `\xHH` escape is GNU-oriented.** `sed 's/@/@\xE2\x80\x8B/g'` was
  verified to emit the U+200B bytes on the host `sed` as well as GNU sed on
  `ubuntu-latest`; if a future runner used a POSIX-only `sed` it should be
  replaced with a `printf`-built ZWSP.
- **B2 relies on the list API.** A `gh issue list --label ai-goal` transport
  failure trips the `ERR` trap (loud), never a silent "no children"; the
  `agent-orchestrate-<n>` concurrency group serializes runs.
- **W7 leaves `TL_SCHEMA` permissive.** A non-code `tl:v1` is caught by the guard
  (friendly message) rather than by the schema; intentionally unchanged so the
  failure names the kind.

## Auth change: OpenRouter key rotation (OPENROUTER_API_KEY[_2.._5])

`OPENCODE_API_KEY` is no longer used anywhere in the agentic loop. Auth now uses
up to five OpenRouter bearer tokens — `OPENROUTER_API_KEY`, `OPENROUTER_API_KEY_2`
… `OPENROUTER_API_KEY_5` — collected in that order by
`.github/scripts/llm_json.sh` and passed per-POST so no global secret is in scope
at curl time.

Rotation rules implemented in `post_with_retries BODY PHASE`:
- HTTP 200 → success; logs the key index (`ki/N`) and attempt, never the value.
- HTTP 401/402/403 (`is_key_failure`) → log "rejected HTTP <code>; rotating" and
  move to the next configured key.
- Transport failures (000/429/500/502/503/504) → retry the SAME key with the
  existing jittered backoff / capped Retry-After; once its attempts are
  exhausted, log and rotate to the next key.
- Any other non-200 (400/404/422, …) → `fail` immediately WITHOUT rotating: the
  request/model is wrong, not the key.
- No key configured at all → `fail "no API key configured ..."`.
- No key succeeds → `fail "all <N> API key(s) failed on <phase>"`.

Model stays `thinkingmachines/inkling:free`; endpoint stays the OpenRouter
default `https://openrouter.ai/api/v1/chat/completions`. The five workflows
(`agent-orchestrate`, `agent-techlead`, `agent-programmer`, `agent-review`,
`agent-triage`) now pass all five secrets in their `env:` blocks, and the
pre-flight guards fail unless at least one is set (triage has no guard and stays
non-fatal). `STATE-MACHINE.md` never named `OPENCODE_API_KEY`, so it was
unchanged.

### Verification
- `bash -n .github/scripts/llm_json.sh` → OK; script remains mode `0755`.
- `ruby -ryaml -e 'YAML.load_file(...)'` for all 5 changed workflows → OK.
- `bash -n` on every extracted `run:` block (23 blocks) → all OK.
- Rotation unit tests with a fake `curl` (23 assertions, all pass):
  1. key1 401 → key2 200 → exit 0, uses key 2/2.
  2. key1 402 → key2 403 → key3 200 → exit 0, uses key 3/3.
  3. all five 401 → exit 1, "all 5 API key(s) failed on primary".
  4. key1 500×3 (transport exhausted) → key2 200 → exit 0.
  5. key1 400 → exit 1 without trying key2 (non-rotatable).
  6. only `OPENROUTER_API_KEY_4` set → used directly (key 1/1).
  7. no dummy key value appears in stdout/stderr.
- `git diff --stat` → only the 6 allowed code/workflow paths (+ this NOTES.md).

Commit: `4b84e6b`; push: `origin/dev` `19d5ac1..4b84e6b` (fast-forward, no
force). This NOTES section is added in a follow-up commit.

## Model config: repo Variable MODEL + provider-error diagnostics

`thinkingmachines/inkling:free` is **OpenRouter-gated to approved "agentic
harness" apps**; a direct API call (including from GitHub Actions) returns
**HTTP 403** and can never succeed, so relying on it was a guaranteed failure.
The previous rotation logic also treated 403 as a key failure, cycling through
all five keys pointlessly and hiding OpenRouter's actual reason.

Changes:
- **Configurable model.** The five role workflows
  (`agent-triage`, `agent-orchestrate`, `agent-techlead`, `agent-programmer`,
  `agent-review`) now set `MODEL: ${{ vars.MODEL || 'nex-agi/nex-n2.5-pro:free' }}`.
  Override by defining the GitHub repository **Variable** `MODEL`; the default
  is `nex-agi/nex-n2.5-pro:free`. `llm_json.sh`'s own default is now
  `nex-agi/nex-n2.5-pro:free` (env `MODEL` still wins).
- **403 no longer rotates.** `is_key_failure` now returns true only for `401`
  (bad key) and `402` (no credits). `403`/`400`/`404`/`422` are fatal,
  non-retryable, non-rotating failures — the model/request is wrong, not the key.
- **Provider error surfaced.** New `api_error_message` reads
  `.error.message // .error // .message` from the last response body (one line,
  ≤300 chars, never headers/key). It is appended to the fatal non-retryable
  diagnostic and to the terminal `all N API key(s) failed` message.

Model-list findings with the user's key: working free models included
`nex-agi/nex-n2.5-pro:free` and `nvidia/nemotron-3.5-lightning:free`;
`openrouter/thinkingmachines/inkling:free` is **not** a valid API model id
(HTTP 400).

### Verification
- `bash -n .github/scripts/llm_json.sh` → OK; file mode remains `0755`.
- `ruby -ryaml -e 'YAML.load_file(...)'` for all 5 workflows → OK. Each has
  exactly one `MODEL: ${{ vars.MODEL || 'nex-agi/nex-n2.5-pro:free' }}` line and
  no remaining `MODEL: thinkingmachines/inkling:free`.
- `bash -n` on every extracted `run:` block (23 blocks) → all OK.
- Fake-`curl` tests of `llm_json.sh` (7 cases, all pass):
  1. key1 403 with `{"error":{"message":"model gated to harnesses"}}` → exit 1
     quickly; stderr contains `model gated to harnesses`; key2 is **never**
     called (403 is fatal).
  2. key1 401, key2 200 → exit 0, used key2 (rotation preserved).
  3. key1 402, key2 200 → exit 0.
  4. key1 500×3 then key2 200 → exit 0 (transport exhaustion rotates; key1 hit
     exactly 3 times).
  5. all five 401 → exit 1, `all 5 API key(s) failed on primary: <provider msg>`.
  6. no key env set → exit 1, `no API key configured ...`.
  7. no dummy key value appears in stdout/stderr.
  Default-model check: with `MODEL` unset the request body carries
  `nex-agi/nex-n2.5-pro:free`; with `MODEL` set it carries the override.
- `git diff --stat` → only the 7 allowed paths (5 workflows, `llm_json.sh`,
  `STATE-MACHINE.md`), plus this NOTES section.

`STATE-MACHINE.md` §1 pinned the old model per role; the three role rows now
read `${{ vars.MODEL }}` (default `nex-agi/nex-n2.5-pro:free`).

Commit: `3270853`; push: `origin/dev` `f75d814..3270853` (fast-forward, no
force). This NOTES section is added in a follow-up commit.

## Model selection: default switched to nex-agi/nex-n2.5-mini:free

**Why.** Free OpenRouter models were benchmarked live against the user's
OpenRouter key on 2026-09-11, exercising the three real JSON schemas the loop
uses (object-classify, goal-array, programmer-file). The default was changed
from `nex-agi/nex-n2.5-pro:free` to `nex-agi/nex-n2.5-mini:free`, which was the
fastest model to pass all three schemas (1–3s).

Benchmark (free models; object-classify / goal-array / programmer-file schemas):

| Model | object-classify | goal-array | programmer-file |
|---|---|---|---|
| `nex-agi/nex-n2.5-mini:free` | OK 1s | PASS 2s | PASS 3s |
| `nex-agi/nex-n2.5-pro:free` | OK 3s | PASS 22s | PASS 29s |
| `nvidia/nemotron-3.5-lightning:free` | OK 7s | PASS 41s | — |
| `dots-studio/dots-3-note-preview:free` | OK 3s | PASS 12s | PASS 21s |
| `cohere/north-mini-code:free` | OK 1s | PASS 2s | PASS 6s |
| `inclusionai/ling-3.0-flash-fin:free` | OK 2s | FAIL (emitted ```` ```json ```` fences; `llm_json.sh` strips fences so it may still pass) | — |
| `nvidia/nemotron-3-ultra-550b-a55b:free` | OK 3s | HTTP 200 with upstream-overload error body (no content) | — |
| `nvidia/nemotron-3-super-120b-a12b:free` | HTTP 200 upstream overload (no content) | — | — |
| `poolside/laguna-s-2.1:free`, `google/gemma-4-26b-a4t-it:free`, `google/gemma-4-31b-it:free` | HTTP 429 | — | — |

**Decision.** `nex-agi/nex-n2.5-mini:free` is the default (fast + passes all
three schemas). `nex-agi/nex-n2.5-pro:free` remains a higher-quality-but-slower
alternative, selectable at any time via the repository Variable `MODEL`.

**Known gap (recorded, not fixed here).** Some providers return HTTP 200 with an
`{"error": ...}` body and no choices content (e.g. the nemotron overload above).
`llm_json.sh` currently fails that as "HTTP 200 but response contained no message
content" without retrying or trying another model.

**Gated model.** `thinkingmachines/inkling:free` is OpenRouter-gated (HTTP 403
"only available on agentic harnesses") and cannot be used from raw curl.

---

## Single-entry dispatch-only chaining

`agent-triage` is now the **only** workflow on the `issues: types: [labeled]`
trigger; the four downstream role workflows are `workflow_dispatch`-only.

**Reason.** Every role workflow carried `on: issues: types: [labeled]`, so
adding *any* label to an issue started a run of *every* role workflow; each
job's `if:` then skipped the roles whose label did not match. The result was a
wall of skipped runs for a single label add. With triage as the single entry
point — it classifies/labels and its final step already dispatches
`agent-orchestrate` — the downstream `issues: labeled` triggers (and their
now-dead `github.event.issue.*` job `if:` guards) are unnecessary, and the
existing dispatch chain takes over.

**Files changed (Commit 1, `c7be8f0`):**
- `.github/workflows/agent-orchestrate.yml`
- `.github/workflows/agent-techlead.yml`
- `.github/workflows/agent-programmer.yml`
- `.github/workflows/agent-review.yml`
- `.agents/orchestrator/STATE-MACHINE.md` (§8 rewritten)

In each of the four workflows: removed the `issues: types: [labeled]` trigger
(only `workflow_dispatch` remains), removed the job-level `if:` guard, and
replaced every `${{ github.event.issue.number || inputs.issue_number }}` with
`${{ inputs.issue_number }}` (the `concurrency.group` and the `ISSUE_NUMBER`
envs). The top-of-file comment blocks now state the workflow is started only by
an explicit `workflow_dispatch` (from the previous role's chain, or manually
via Actions -> Run workflow) and that triage is the sole `issues: labeled`
entry point. Permissions, `cancel-in-progress: false`, `timeout-minutes`, the
required `issue_number` input, the dispatch steps, and all other logic are
unchanged.

`agent-triage.yml` was **not** modified (still the one `issues: types:
[labeled]` workflow, with its `actions: write` hand-off to `agent-orchestrate`).
`agent-build.yml`, `branch-lint.yml`, `ci-smoke.yml`, `key-test.yml`,
`llm_json.sh`, and `labels.yml` were not touched.

**Human-resume implication.** Because the downstream label triggers are gone,
re-applying `goal/tl` / `goal/ready` / `goal/review` no longer starts a run. To
resume a `needs-human` goal, run the relevant role workflow manually from the
Actions UI (Run workflow -> `issue_number`) or via
`gh workflow run <role>.yml -f issue_number=<N>`. Re-running `agent-triage`
(remove/re-add the `ai-triage` label) restarts the whole chain idempotently.
Trade-off: no more skipped-run noise, at the cost of the old label-click resume
convenience.

**Chain:** `agent-triage` -> `agent-orchestrate` -> (per code goal)
`agent-techlead` -> `agent-programmer` -> `agent-review` -> (on revise)
`agent-techlead`.

**Verification (actual output):**
- `ruby -ryaml -e "YAML.load_file(...)"` -> `YAML OK` for all four workflows
  plus `agent-triage.yml`.
- All `run:` blocks extracted (Ruby YAML) and `bash -n` each -> `bash -n OK`
  for all 19 (orchestrate 6, techlead 4, programmer 5, review 4).
  (`shellcheck` not installed on the host.)
- `grep -n "issues:"` on the four files matches only the `issues: write`
  permission and the new doc comments — the trigger declaration is gone:
  `grep -nE '^  issues:'` and `grep -F 'types: [labeled]'` return no matches on
  the four, while `grep -nE '^  issues:' agent-triage.yml` still shows line 11.
- `grep -n "github.event.issue"` on the four -> no matches. A scan for
  `github.event_name` / `github.event.sender` / `labels.*` -> no matches.
- `grep -n "workflow_dispatch"` -> present in each of the four.
- `git status --short` before each commit shows only the intended files.

**Commit + push (dev only — NEVER main):**
- Commit 1 `c7be8f0` —
  `refactor(agents): triage is the sole label entry; downstream roles dispatch-only`;
  `git push origin dev` OK (`3f344f4..c7be8f0  dev -> dev`).
- Commit 2 (this NOTES record) —
  `docs(agents): record dispatch-only chaining and manual resume`; its own SHA
  and push range are recorded in the task report (not invented here).

---

# Fix — HTTP 200 with empty content is retried/rotated (`dev` only — NEVER main)

**Symptom.** `agent-orchestrate` run #22 (issue #29) failed with
`llm_json: HTTP 200 (primary) on key 1/5, attempt 1/3` immediately followed by
`Error: llm_json: HTTP 200 but response contained no message content`. This is
the "known gap" recorded in the model-selection section above: a provider can
return HTTP 200 carrying an `{"error":...}` overload body (or an empty/truncated
message) with no `choices[0].message.content`, and `llm_json.sh` treated **any**
HTTP 200 as success — it checked content exactly once and failed fatally, with
no retry and no key rotation.

**Fix (`.github/scripts/llm_json.sh` only).**
- New `extract_content()`: reads `.choices[0].message.content`, handles both the
  plain-string and array-of-parts shapes, returns "" when absent. Now the single
  extraction path for both the primary and correction replies.
- New `finish_reason()`: `[finish=...]` diagnostic (never prints the body).
- `post_with_retries` now treats HTTP 200 with empty content as **transient**:
  jittered backoff up to `LLM_MAX_ATTEMPTS`, then rotate keys — identical to the
  transport path. The provider `error.message` and `finish_reason` are included
  in the diagnostic, so `finish=length` (reasoning consumed the token budget) is
  distinguishable from a transient overload. Exhaustion still exits 1 loudly.
- New `is_key_cap()`: a `429` whose body has
  `error.metadata.limit_source == "openrouter_free_tier_daily"` is a key-scoped
  cap, not a transient provider hiccup — the key is rotated immediately instead
  of spending the backoff budget on a key that cannot succeed again today.

**Verification (actual output).**
- `bash -n` OK (`shellcheck` not installed on the host).
- Mock-`curl` harness drove the helper end-to-end, **15/15 assertions pass**:
  empty-200 then valid → 2 calls, exit 0, schema-valid output; HTTP-200 error
  body then valid → retry, exit 0; all-empty across 3 keys × 2 attempts → 6
  calls, exit 1, "empty-content exhausted" rotation logged; `429` free-tier cap
  → key 2 used on attempt 1 (no backoff), exit 0; valid first call → 1 call,
  exit 0; array-of-parts content extracted.
- No live call was possible: the local OpenRouter key was rate-limited
  (free-models-per-day 50, HTTP 429) at fix time. The next real
  `agent-orchestrate` run exercises the live path.

**Follow-up.** Porting this helper to a zero-dependency Node (`llm_json.mjs`)
with a `node:test` parity suite is filed as `[T-0009]`. Bash remains the right
tool for the `gh`/`git`/label glue.

**Commit + push (dev only — NEVER main):**
- `fix(agents): retry HTTP 200 empty-content + rotate on free-tier cap` to
  `origin/dev`; SHA + push range recorded in the task report (not invented here).

---

# Duplicate-run fix: label-scoped triage + idempotent orchestration (`dev` only — NEVER main)

## Symptom

Recent runs showed duplicate work for a single issue: several `agent-triage`
runs, then 3 `agent-orchestrate` runs, then duplicate `agent-techlead` runs.

## Root causes

1. **`agent-triage` `if:` was "label present".** The job-level `if:` first
   clause was
   `contains(github.event.issue.labels.*.name, 'ai-triage')`, so **any** later
   label added to an already-triaged issue (e.g. `kind/*`, `priority/*`) made
   the `issues: labeled` job match and re-run triage successfully. Each success
   re-dispatched `agent-orchestrate` for the same issue.
2. **`agent-orchestrate` had no idempotency guard.** A second dispatch (e.g. a
   manual run racing the triage-dispatched run) re-ran the LLM and re-dispatched
   `agent-techlead` for the same goals.

## Changes

- **`.github/workflows/agent-triage.yml`** — the job `if:` first clause is now
  `github.event.label.name == 'ai-triage'` (label-scoped: fires only when the
  `ai-triage` label itself is added), keeping
  `github.event.issue.user.type != 'Bot' && github.event.sender.type != 'Bot'`.
  The adjacent comment explains that other labels on an already-triaged issue no
  longer re-run triage / re-dispatch the orchestrator. Nothing else in the file
  changed (permissions, hand-off step, etc.).
- **`.github/workflows/agent-orchestrate.yml`**
  1. New `workflow_dispatch` input `force` (boolean, default `false`,
     `"Re-run orchestration even if goals already exist"`); `issue_number`
     unchanged.
  2. New `Idempotency check` step (`id: guard`) immediately after the
     `Document pure GitHub workflow agent` step, before the LLM. It sets
     `skip=true` when the parent has the `<!-- orchestrator:v1 -->` success
     marker **and** at least one child goal (`ai-goal`, title ending
     `(from #<n>)`) or ticket (`ai-ticket`, body carrying the exact
     `<!-- agent-ticket:v1 origin:#<n> -->` marker) exists. `FORCE=true`
     bypasses it. Query failures are soft and treated as "proceed".
  3. `if: steps.guard.outputs.skip != 'true'` added to each of `Break issue into
     goals (LLM, loud failure)`, `Delegate goals as sub-issues`, and `Dispatch
     next role (Tech Lead)`; their bodies are unchanged.
  4. Top-of-file comment notes the idempotency guard / `force` input.
- **`.agents/orchestrator/STATE-MACHINE.md`** — the triage section now states
  triage fires only when the `ai-triage` label is added
  (`github.event.label.name == 'ai-triage'`); §8 documents the orchestrator
  idempotency guard, the `force=true` override, and that this prevents duplicate
  TL dispatches. Nothing else changed.
- **`.agents/orchestrator/NOTES.md`** (this section).

## `force=true` escape hatch

A manual Actions -> Run workflow with `force` checked (or
`gh workflow run agent-orchestrate.yml -f issue_number=<N> -f force=true`)
bypasses the guard and re-runs orchestration. Existing goals/tickets are still
deduped by the delegate step, so the forced re-run does not duplicate children.

## Verification (actual output)

- `ruby -ryaml -e "YAML.load_file('<f>')"` -> `triage YAML OK`,
  `orchestrate YAML OK`.
- All `run:` blocks extracted (Ruby YAML) and `bash -n` each -> `bash -n OK` for
  all 12 (5 triage + 7 orchestrate).
- `grep -n "github.event.label.name" .github/workflows/agent-triage.yml` ->
  line 21 present.
- `grep -n "contains(github.event.issue.labels"` -> no match.
- `grep -nE "skip != 'true'|id: guard|inputs.force"` on
  `agent-orchestrate.yml` -> `id: guard` (line 68), `FORCE: ${{ inputs.force ||
  false }}` (line 71), three `if: steps.guard.outputs.skip != 'true'` lines
  (121, 180, 419).
- Guard simulation against the extracted step with a mock `gh` (real `jq`):
  - (a) `FORCE=true` -> `skip=false`
  - (b) `MARKER=true GOALS=2` -> `skip=true`
  - (c) `MARKER=true GOALS=0 TICKETS=0` -> `skip=false`
  - (d) `MARKER=false GOALS=0` -> `skip=false`
  - (e) query failure (`gh` exits 1) -> `skip=false` (proceeds)
  - (f) `MARKER=true TICKETS=1 GOALS=0` -> `skip=true`
  All pass.
- `git status --short` before each commit shows only the intended files.

## Commit + push record (dev only — NEVER main)

- Commit 1 `3028174` —
  `fix(agents): label-scoped triage + idempotent orchestrator to stop duplicate
  runs`; files: `.github/workflows/agent-triage.yml`,
  `.github/workflows/agent-orchestrate.yml`,
  `.agents/orchestrator/STATE-MACHINE.md`.
  `git push origin dev` OK (`e792a60..3028174  dev -> dev`).
- Commit 2 (this NOTES record) —
  `docs(agents): record duplicate-run fix and force escape hatch`; its own SHA
  and push range are recorded in the task report (not invented here).

## Open risks / follow-ups

- **Live runner unverified.** The guard logic is proven by YAML/`bash -n` and a
  mock-`gh` simulation only; the real `gh issue view/list` behaviour and the
  `workflow_dispatch` boolean input have not run. First live check = a manually
  re-dispatched `agent-orchestrate` on an already-orchestrated issue, confirming
  the run is a no-op (no second LLM call, no duplicate TL dispatch), then
  `force=true` to confirm the override.
- **Guard query failure softens to "proceed".** A transient `gh` error with the
  marker actually present would allow a duplicate orchestration; the delegate
  step's per-goal/per-ticket dedupe keeps that from duplicating children, and the
  `agent-orchestrate-<n>` concurrency group serializes runs per issue.
- **`label.name` is only populated on a `labeled` event.** The triage workflow's
  trigger is `issues: types: [labeled]`, so this is always set for the events it
  handles; no other event can reach the job.

---

## Goal-key dedupe hardening

**What changed.** `agent-orchestrate`'s Delegate step now computes a
deterministic per-parent **goal key** and stamps every created child (goal or
ticket) with it as the body's FIRST line:

```
<!-- agent-goal-key:v1 parent:#<N> kind:<kind> key:<key> -->
```

where `<key>` is the normalized `"<kind>:<title>"` — lowercased; each run of any
character outside `[a-z0-9]` collapsed to `-`; leading/trailing `-` trimmed;
capped at 80 chars (`goal_key()` uses `tr`, `sed -E`, `cut`). Before creating a
child, the step skips it when ANY existing `ai-goal` **or** `ai-ticket` body
contains that exact marker. The two lists are concatenated once into
`EXISTING_ALL_JSON` (`jq -n --argjson g ... --argjson t ... '$g + $t'`). Both the
goal and ticket `printf` body formats were reordered so the key marker is emitted
first.

**Rationale.** The previous dedupe keyed on the EXACT generated title (plus the
`agent-ticket:v1` marker), and the LLM re-phrases titles across runs. A
`force=true` re-run — or a first run that failed after creating one child but
before posting the `<!-- orchestrator:v1 -->` marker — could therefore create
semantically-duplicate children. A normalized per-parent key makes those runs an
idempotent **reconcile**: children whose key already exists are reused (the
summary links them as `_(existing, key)_`) and only genuinely new keys are
created. The exact-title fallbacks are kept so children created before this
hardening are still deduped.

**Files changed (exactly 3):**

- `.github/workflows/agent-orchestrate.yml` — header note; `ALL_GOALS_JSON`
  (unfiltered goals list kept for key lookup); ticket fetch gains `url`;
  `EXISTING_ALL_JSON`; `goal_key()`; per-loop `KEY`/`KEY_MARKER`; key-based skip
  in both the code and non-code branches; key marker first in both body formats.
- `.agents/orchestrator/STATE-MACHINE.md` — §2 per-key dedupe bullet, §4
  source-of-truth table row, §8 `force=true` reconcile note, §11 goal-key dedupe
  bullet.
- `.agents/orchestrator/NOTES.md` (this section).

**Verification (actual output).**

- `ruby -ryaml -e "YAML.load_file('.github/workflows/agent-orchestrate.yml')"` →
  `YAML OK`.
- All 7 `run:` blocks extracted (Ruby YAML) and `bash -n` each → all `OK`.
- `goal_key` extracted verbatim and run under real bash:
  - `"Create an isolated 50-NPC proof of concept"` and
    `"create an ISOLATED 50 NPC proof of concept!!"` → both
    `create-an-isolated-50-npc-proof-of-concept` (identical);
  - `"  ...Hello, World!!!  "` → `hello-world` (edges trimmed);
  - a 120-char title → key length exactly 80 (capped);
  - `goal_key "!!!"` → empty string (no crash — `sed`/`cut` yield ""); in the
    workflow the input is always `${KIND}:${TITLE}`, so a `"!!!"` title yields
    the bare kind (e.g. `code`), never empty.
- Mock `gh` (persistent JSON issue store) + mock `git` + real `jq` drove the
  **extracted Delegate step**: **29/29 assertions pass**:
  - (a) fresh mixed run → 2 children created; both bodies' FIRST line is the
    exact key marker (`parent:#1 kind:code key:code-build-api-endpoint`,
    `parent:#1 kind:docs key:docs-write-the-docs`), ticket's second line is the
    `agent-ticket:v1` marker;
  - (b) `force`-style re-run with **re-phrased** titles
    (`"  BUILD   api  endpoint!! "`, `"write THE docs."`) → 0 created, both links
    say `_(existing, key)_` (key dedupe, not the title fallback);
  - (c) pre-hardening child (exact title, no key marker) → skipped via the title
    fallback (`_(existing)_`, not `_(existing, key)_`);
  - (d) a genuinely new kind/title → created with its key marker;
  - (e) a `parent:#300` marker does NOT satisfy a `parent:#30` lookup (and vice
    versa) → the #30 child is created.
- `grep`: the exact marker literal appears in the `KEY_MARKER` assignment and
  `$KEY_MARKER` is emitted first in both body `printf`s; the only `git push` is
  `git push -u origin "issue/${ISSUE_NUMBER}"`; no `--force`, no `gh pr merge`,
  no `git merge` into `dev`/`main`.
- `git status --short` before the feature commit showed exactly the 3 files
  (`.github/workflows/agent-orchestrate.yml`,
  `.agents/orchestrator/STATE-MACHINE.md`, `.agents/orchestrator/NOTES.md`); it
  is clean after both commits.

**Commit + push record (dev only — NEVER main).**

- Commit 1 (`feat(orchestrator): deterministic per-parent goal-key dedupe
  (idempotent force reconcile)`) — `.github/workflows/agent-orchestrate.yml`
  only. SHA `04e6250`; `git push origin dev` → `6bc4fd1..04e6250  dev -> dev`.
- Commit 2 (this NOTES + STATE-MACHINE docs) —
  `docs(orchestrator): record goal-key dedupe hardening`; its own SHA/push range
  recorded in the task report post-push.

**Residual limitation.** Semantic paraphrases with a very different *normalized*
title still produce a different key and therefore a new child (e.g. reordering
words or substituting synonyms: `build-api-endpoint` vs
`create-the-http-api-route`). The goal-key dedupe only catches re-phrasings that
normalize identically. The `<!-- orchestrator:v1 -->` idempotency guard (which
skips the LLM + delegate entirely unless `force=true`) remains the primary
protection against duplicate runs.

---

## Fuzzy (token-overlap) goal dedupe

**What changed.** `agent-orchestrate`'s Delegate step gained a **supplementary**
token-overlap (Jaccard) dedupe next to the deterministic goal-key dedupe, for
near-duplicate titles that normalize to different keys. After `goal_key()` the
step defines:

- `FUZZY_THRESHOLD="${FUZZY_DEDUPE_THRESHOLD:-0.6}"` — threshold, env-overridable.
- `title_tokens()` — lowercases the title, replaces every run of non-alphanumerics
  with a space, splits, drops empty tokens, and `unique`s them (compact JSON).
- `fuzzy_match_url()` — computes the candidate title's token set; if it has
  **< 3 tokens** it prints nothing and returns. Otherwise it scopes to existing
  children whose body contains `parent:#<ISSUE_NUMBER> kind:<kind> ` (note the
  trailing space, matching the exact `agent-goal-key:v1` marker), computes the
  Jaccard similarity `|intersection| / |union|` against each scoped child title,
  keeps those `>= threshold`, and prints the best-scoring child's `url` (or `""`).

In BOTH the `code` branch and the non-code `else` branch, AFTER the existing
exact-title and exact-key skip blocks and BEFORE building `SUB_BODY`:

```bash
FUZZY_URL="$(fuzzy_match_url "$TITLE" "$KIND")"
if [ -n "$FUZZY_URL" ]; then
  printf '%s\n' "- ${SUB_TITLE} - ${FUZZY_URL} _(existing, fuzzy)_" >> /tmp/goal_links.md   # or ticket_links.md
  echo "Skipping fuzzy-duplicate goal: ${SUB_TITLE} ~ ${FUZZY_URL}"                          # or "... ticket: ..."
  continue
fi
```

The file header comment now documents the supplementary fuzzy dedupe.

**Rationale.** The deterministic key dedupes case/spacing/punctuation variants
of the same title, but the LLM re-phrases titles across runs (adds/removes/
reorders words). A `force=true` reconcile — or a run that failed after creating
one child but before the `<!-- orchestrator:v1 -->` marker — could still create a
semantically-duplicate child. A scoped token-overlap check catches those
near-duplicates while never crossing parents or kinds. Exact-title and exact-key
matches run first and win; fuzzy only fills the gap.

**Files changed (exactly 3):**

- `.github/workflows/agent-orchestrate.yml` — header note; `FUZZY_THRESHOLD`,
  `title_tokens()`, `fuzzy_match_url()`; fuzzy skip in both loop branches.
- `.agents/orchestrator/STATE-MACHINE.md` — §2 fuzzy-dedupe bullet next to the
  per-key bullet.
- `.agents/orchestrator/NOTES.md` (this section).

**Spec deviation (important).** The mandated snippet computed the union as
`([ ($new + $b) | unique ] | length)`. The outer `[...]` wraps the array that
`unique` already returns, so that length is always **1**; the code therefore
computed the raw **intersection count**, not Jaccard, and `write THE docs` vs
`Write the documentation` (true Jaccard `0.5`) matched at the default threshold —
contradicting the contract (`|intersection| / |union|`) and the mandated test.
Fixed minimally to `(($new + $b) | unique | length)`. No other change to the
mandated snippet; the fix is required for the stated semantics and tests.

**Verification (actual output).**

- `ruby -ryaml -e "YAML.load_file('.github/workflows/agent-orchestrate.yml')"` →
  `YAML OK`.
- All **7** `run:` blocks extracted (Ruby YAML) and `bash -n` each → all
  `bash -n OK`. (`shellcheck` not installed on the host.)
- Extracted `title_tokens`/`fuzzy_match_url` verbatim and drove them with real
  bash + jq against a synthetic `EXISTING_ALL_JSON` whose markers are
  `parent:#7 kind:code`, `parent:#7 kind:docs`, `parent:#70 kind:code`. **8/8
  assertions pass:**
  - `"Implement an isolated 50-NPC rendering proof of concept"` vs existing
    `"Create an isolated 50-NPC proof of concept"` → actual Jaccard **0.7**
    (7/10; the tokenizer splits `50-NPC` into `50`+`npc`, so the task's stated
    `5/8 = 0.625` is a miscount) → **MATCH**, returns `https://ex/code7`.
  - `"write THE docs"` vs existing `"Write the documentation"` → Jaccard
    **0.5** → **NO match** (`""`).
  - same-parent **different kind**: candidate `code` `"Write the documentation"`
    does **not** match the `parent:#7 kind:docs` entry → `""` (that entry's
    Jaccard is 1.0, proving scope, not threshold, is what excludes it).
  - **different parent**: candidate vs the `parent:#70 kind:code` entry
    `"Unrelated zebra quantum pancake"` → Jaccard 0.8 but `""` (excluded by
    scope).
  - `<3`-token titles (`"write docs"`, `"isolated proof"`) → `""` (early return).
  - exact key: `goal_key "code:<title>"` = `code-create-an-isolated-50-npc-proof-of-concept`;
    the key-marker `contains` lookup finds the existing url — the deterministic
    key path is checked **before** fuzzy in both branches (line order: existing
    title < key < fuzzy).
  - threshold override `FUZZY_THRESHOLD=0.4` makes the 0.5 case match.
- Push/merge audit: the only `git push` in the file is
  `git push -u origin "issue/${ISSUE_NUMBER}"`; **no** `--force`, **no**
  `git merge`, **no** `gh pr merge`; no new push targets.
- `git diff --stat` for the round touches exactly the 3 intended paths;
  `git status --short` clean after both commits.

**Commit + push record (dev only — NEVER main).**

- Commit 1 `93e8314` —
  `feat(orchestrator): fuzzy token-overlap dedupe for re-phrased goal titles`;
  files: `.github/workflows/agent-orchestrate.yml` only.
  `git push origin dev` OK (`3babe76..93e8314  dev -> dev`).
- Commit 2 (this NOTES + STATE-MACHINE docs) —
  `docs(orchestrator): record fuzzy goal dedupe`; its own SHA/push range recorded
  in the task report post-push (not invented here).

**Residual limitation.** The fuzzy check is lexical only: a semantic paraphrase
whose token overlap is below the threshold (e.g. synonyms with no shared words)
still creates a new child. The threshold is a tunable trade-off — lower catches
more re-phrasings but risks false merges of genuinely distinct goals; raise
`FUZZY_DEDUPE_THRESHOLD` to reduce false positives. Fuzzy matching is scoped to
existing children that already carry the `parent:#N kind:<kind> ` goal-key
marker, so pre-hardening children (no marker) are never fuzzy candidates.

