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
