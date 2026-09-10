# Agentic Loop — Frozen State Machine (v1)

> Contract shared by **all** role workflows in this repo:
> `agent-orchestrate` (PO), `agent-review` (PO), `agent-techlead` (TL),
> `agent-programmer` (Programmer).
>
> This file is the single source of truth for label names, marker strings, and
> loop caps. Do **not** rename a label/marker or change a cap without updating
> every role workflow AND this file in the same change. Treat it as frozen.

---

## 1. Roles, triggers, budgets

| Role | Workflow(s) | Entry trigger | Effort | Model |
|---|---|---|---|---|
| **PO** | `agent-orchestrate`, `agent-review` | `ai-orchestrate`; PO verdict pass on `goal/review` | **high** | `thinkingmachines/inkling:free` |
| **TL** | `agent-techlead` | `goal/tl` | **medium** | `thinkingmachines/inkling:free` |
| **Programmer** | `agent-programmer` | `goal/ready` | **medium** for `kind: code`, **low** for non-development kinds (`docs`/`analysis`/`requirement`/`user-story`) | `thinkingmachines/inkling:free` |

Rules:

- **One LLM call per role per issue.** `llm_json.sh` may internally make a
  single extra schema-correction call, but no role calls the model more than
  once for a given issue.
- All model traffic goes through `.github/scripts/llm_json.sh` (transport
  backoff + schema validation + one correction). No role inlines its own curl.
- Missing config or exhausted retries = **loud failure** (issue comment +
  non-zero exit); there is no template/silent fallback.

---

## 2. Goal-issue state machine

A **goal issue** is a sub-issue created by the PO for a parent
(`ai-orchestrate`) issue. It carries BOTH `ai-goal` (the orchestrator's own
bookkeeping label) and `goal/tl` (the TL workflow's entry trigger), so a
freshly created goal is picked up by the TL immediately.

```
ai-goal
  │  (TL picks up)
  ▼
goal/tl        TL decomposes / writes spec + `<!-- tl:v1 -->`
  │  (TL done)
  ▼
goal/ready     ready for the Programmer
  │  (Programmer picks up)
  ▼
goal/building  Programmer working
  │  (Programmer done, posts `<!-- result:v1 -->`)
  ▼
goal/review    awaiting PO verdict
  │
  ├── PO verdict PASS  → goal/done      (terminal)
  │                        PO posts `<!-- verdict:v1 -->`
  │
  └── PO verdict REVISE → goal/tl       (re-enter at the TL)
                           attempt+1; there is NO `goal/revise` label
                           (PO posts `<!-- verdict:v1 -->`)
```

Transitions (each is an issue-label edit by the workflow that owns the step):

| From | To | Actor | Condition |
|---|---|---|---|
| `ai-goal` | `goal/tl` | PO | goal created / re-entered after revise |
| `goal/tl` | `goal/ready` | TL | decomposition/spec written |
| `goal/ready` | `goal/building` | Programmer | work started |
| `goal/building` | `goal/review` | Programmer | result posted |
| `goal/review` | `goal/done` | PO | verdict PASS |
| `goal/review` | `goal/tl` | PO | verdict REVISE (attempt+1; re-enters at the TL — there is no `goal/revise` state) |

### Goal creation (PO)

The orchestrator creates sub-issues titled `[GOAL] <title> (from #<parent>)`:

- **Labels applied:** `ai-goal` **and** `goal/tl`. `ai-goal` is the
  orchestrator's bookkeeping label; `goal/tl` hands the goal to the TL workflow.
- **Kind:** each goal carries a `kind` in its body (`Kind: <kind>`) and in the
  `tl:v1` spec, one of `code | docs | analysis | requirement | user-story`.
  `code` changes repository source/config/files; every other kind is
  **non-development** and produces a markdown artifact (§9).
- **Cap 6 goals** per parent (the LLM is asked for 3–6; the loop slices `[:6]`).
- **Per-title dedupe:** before creating, the PO lists existing `ai-goal` issues
  whose title contains `from #<parent>` and skips any whose expected title is
  already present. Dedupe is per goal, so a partial prior run or a later-deleted
  goal is recovered without duplicating the rest. A failed lookup is a loud
  failure (no `|| true`), never treated as "no existing goals".
- **Loud failure:** any failure before/while creating goals posts a parent
  comment beginning `<!-- orchestrator:v1-error -->` and exits non-zero.
  `triage/accepted` is added to the parent only at the very end, after success.

### Upstream triage labels (owned by triage, NOT the goal loop)

`triage/accepted`, `priority/important-soon`, and `kind/task` are **triage-owned**
labels applied by `agent-triage`. The goal loop never sets
`priority/important-soon` or `kind/task`; its only use of `triage/accepted` is as
a parent completion signal added *after* successful delegation. Do not treat
these as goal-state labels.

### Caps

- `MAX_REVISE=3`.
- The revise counter lives in a **goal-issue comment marker**:
  `<!-- attempts:N -->`. On a `revise` verdict the PO increments it and moves the
  goal straight back to `goal/tl` (re-entered at the TL); the TL/Programmer read
  it to size the revision. There is **no** `goal/revise` label.
- On exceeding the cap (`N > MAX_REVISE`): stop looping, add `needs-human`,
  and post a loud comment naming the attempt count and asking for a human.

---

## 3. Parent issue

When **all** child goals of a parent issue are `goal/done`:

1. Add `status:done` to the parent.
2. Post a summary comment (goal list + links + evidence).

No auto-close — a human closes the parent.

---

## 4. State source of truth

**Chosen: issue labels for state + HTML-comment markers for counters/specs.**

| Concern | Representation | Where |
|---|---|---|
| Current state | one of the `goal/*` labels | issue labels |
| TL spec/version | `<!-- tl:v1 -->` | issue comment |
| Programmer result | `<!-- result:v1 -->` | issue comment |
| PO verdict | `<!-- verdict:v1 -->` | issue comment |
| Revision counter | `<!-- attempts:N -->` | issue comment |
| Orchestrator run | `<!-- orchestrator:v1 -->` | parent comment |
| Orchestrator failure | `<!-- orchestrator:v1-error -->` | parent comment |

Justification (vs a committed state file):

- **Labels are atomic and concurrent-safe.** GitHub mutates labels
  server-side, so two role workflows racing on the same issue cannot clobber a
  shared JSON blob. A committed state file would require a branch write + push
  + merge for every transition — exactly the push/PR path the agent roles are
  forbidden to take.
- **Markers are append-only.** Counters and specs are recorded as immutable
  comments (the latest marker wins), so a partial run never corrupts prior
  history and idempotency checks are simple string searches.
- **No credentials beyond `issues: write`.** Labels + comments need only the
  least-privilege job permission the workflows already declare; a state file
  would need `contents: write`.

## 5. Concurrency

- Every role workflow uses exactly one concurrency group per issue:
  `group: agent-<role>-<issue_number>` with `cancel-in-progress: false`.
- This serializes a role against itself on one issue while allowing different
  roles and different issues to run in parallel.
- `cancel-in-progress: false` is deliberate: a cancelled mid-flight run could
  leave a label applied without its marker comment (or vice versa), so runs
  queue instead of being killed.

---

## 6. Comment payload format (v1)

Every role artifact is a comment of the form:

```
<!-- <marker> -->
<single-line base64 of the compact JSON payload>
<!-- /<marker> -->

<human-readable markdown rendering>
```

Markers: `tl:v1` (TL spec), `result:v1` (Programmer), `verdict:v1` (PO review).
Because the base64 line is isolated between marker lines, arbitrary model text in
the readable section can never break extraction.

Read the LATEST payload with:

```bash
RAW="$(gh issue view "$ISSUE_NUMBER" --json comments --jq '[.comments[].body] | map(select(contains("<!-- tl:v1 -->"))) | last // ""')"
PAYLOAD="$(printf '%s' "$RAW" | sed -n '/<!-- tl:v1 -->/{n;p;}')"
JSON="$(printf '%s' "$PAYLOAD" | base64 -d 2>/dev/null || true)"
```

The workflow injects the attempt number after parsing:
`JSON="$(printf '%s' "$JSON" | jq --argjson a "$ATTEMPT" '. + {attempt:$a}')"`;
payloads therefore always carry `attempt` (number). Read the attempt counter from
the last comment matching `<!-- attempts:N -->` (default 0) via
`sed -n 's/.*<!-- attempts:\([0-9]*\) -->.*/\1/p'`, empty→0.

---

## 7. Review verdict + termination (v1)

`agent-review` (PO) is the only role that can end a goal. It fires on
`goal/review`, reads the latest `tl:v1` spec and latest `result:v1` deliverable
via the §6 extraction, and makes **one** model call at `--effort high` to obtain
a verdict. If either payload is missing or fails its schema, the review is a
loud failure: comment + `needs-human` (removing `goal/review`) + `exit 1`.

### Verdict semantics

The model returns:

```
{"verdict":"done"|"revise","reason":string,"missing":[string],"guidance":string}
```

- `done` is returned **ONLY if the deliverable satisfies every acceptance item**
  in the `tl:v1` spec (`objective`/`steps`/`files`/`acceptance`).
- Otherwise the verdict is `revise`, and `missing[]` names the specific unmet
  item(s); `reason` and `guidance` carry the readable explanation.

The verdict is posted as `<!-- verdict:v1 -->` (base64 payload + readable
rendering) with `attempt` injected (§6).

### Revision counter ownership

The **PO owns** the `<!-- attempts:N -->` counter. Only `agent-review` writes it;
the TL and Programmer only read the latest marker (§2/§6). On a `revise` verdict
the PO:

1. computes `NEXT = ATTEMPT + 1`;
2. posts a separate comment whose body is **exactly** `<!-- attempts:NEXT -->`;
3. moves the goal `goal/review` → `goal/tl` (re-enters the TL).

### Escalation

`MAX_REVISE=3` is a job env var in `agent-review.yml`. When `NEXT > MAX_REVISE`,
the PO stops looping: it posts a loud escalation comment naming the attempt
count and moves the goal `goal/review` → `needs-human`. The goal is **never**
sent back to `goal/tl`, so no further automated revision occurs.

### Idempotency

A `verdict:v1` payload whose `.attempt` equals the current `ATTEMPT` short-
circuits the LLM: the stored verdict's transition is re-applied only. Re-running
`agent-review` on the same attempt therefore never double-calls the model.

Before any LLM call the review also requires the latest `result:v1` payload's
`.attempt` to equal the current `ATTEMPT`. A queued/duplicate dispatch that
arrives after a revise advanced the counter carries a **stale** result: the
review logs a "not ready for this attempt" note and exits 0 with **no** LLM call
and **no** label/marker change (idempotent no-op), so a stale result can never
burn a revision.

### Parent termination

Runs only after a `done` verdict:

1. Discover children with the REST-backed list + a local exact-suffix filter
   (`gh issue list --label ai-goal --state all --limit 200 --json
   number,title,url,labels`, then keep only titles ending exactly with
   `(from #<parent>)`). Never `--search`: its index can lag and miss a freshly
   labeled child.
2. The parent is complete **iff** the filtered list is non-empty **AND every**
   child's `labels[].name` contains `goal/done`.
3. On completion, post a parent comment beginning `<!-- parent-done:v1 -->`
   (goal list + links) and add `status:done`.
4. Idempotent: skip if the parent already has a `<!-- parent-done:v1 -->` marker
   or `status:done`; the marker is re-read immediately before posting so a racing
   review cannot double-post, and `--add-label` is itself idempotent.
5. **No auto-close** — see §3; a human closes the parent.

A failed child lookup is a loud failure (no `|| true` treated as empty); the
review step wraps its work in an `ERR` trap that posts a visible comment and
exits non-zero.

---

## 8. Role chaining via `workflow_dispatch` (v1)

### Why label-only chaining fails

Every role advances the loop by editing an issue label with `GITHUB_TOKEN`
(e.g. the PO creates a goal and applies `goal/tl`; the TL applies `goal/ready`;
the Programmer applies `goal/review`; the PO applies `goal/tl` on revise).
GitHub suppresses workflow runs for events a `GITHUB_TOKEN` produces:

> "When you use the repository's `GITHUB_TOKEN` to perform tasks, events
> triggered by the `GITHUB_TOKEN` will not create a new workflow run, with the
> following exceptions: `workflow_dispatch` and `repository_dispatch` events
> always create workflow runs."

So the `issues: labeled` triggers alone leave the automated
PO → TL → Programmer → PO-review chain dead: the next role never starts.
(The bot-sender `if:` guard is a second, independent reason the token-made
label edit would not be picked up even if the run *were* created. Goal issues
are Bot-authored, so the guard checks the event **sender**, not the issue
author — a human re-applying a role's entry label must still run the role.)

### Chosen mechanism: explicit `workflow_dispatch`

`workflow_dispatch` is an official exception to the suppression rule, so each
role explicitly dispatches the next one after its own work succeeds. No App or
PAT identity is introduced — the same `GITHUB_TOKEN` is used, and the guard
short-circuits on `github.event_name == 'workflow_dispatch'` so the dispatch
path never evaluates `github.event.issue.*`.

- Every role workflow adds a `workflow_dispatch` trigger with a required
  `issue_number` input, alongside the original `issues: types: [labeled]`.
- Every role job adds `actions: write` to its job permissions (the minimum
  needed to call `gh workflow run`); `contents: read` and `issues: write` stay.
- Every concurrency group and every `ISSUE_NUMBER` env uses
  `${{ github.event.issue.number || inputs.issue_number }}` so both triggers
  resolve the issue. `cancel-in-progress: false` is unchanged (§5).
- The final step of each role dispatches the next role with
  `gh workflow run <next>.yml --repo "<repo>" --ref dev -f issue_number="<N>"`
  and `GH_TOKEN: ${{ github.token }}`. A failed dispatch posts a loud comment
  on the issue and exits non-zero.
- Because `workflow_dispatch` has no `github.event.issue`, no step may read
  `github.event.issue.*` outside the job `if:`; the `ISSUE_NUMBER` env is the
  only source of the issue number.

### Dispatch chain

| Role (`workflow`) | On success dispatches | Notes |
|---|---|---|
| PO `agent-orchestrate` | `agent-techlead` for each goal | Per goal still at `goal/tl`; goals already at a later state are skipped. |
| TL `agent-techlead` | `agent-programmer` | After the spec is written and the goal is at `goal/ready`. |
| Programmer `agent-programmer` | `agent-review` | Only when the success path moved the goal to `goal/review`; `needs-human` dispatches nothing. |
| PO `agent-review` | `agent-techlead` | Only on a `revise` verdict; a `done` verdict is terminal (parent termination runs inline) and an escalation to `needs-human` dispatches nothing. |

### Label triggers remain

The `issues: labeled` triggers are kept on every role for human/manual starts
and re-runs (a human adding `ai-orchestrate`, or re-applying `goal/tl` /
`goal/ready` / `goal/review` after fixing a failure). `workflow_dispatch` is
additive, not a replacement; both paths share the same role logic.

### Trade-off

Chaining costs **one extra Actions run per handoff** (the dispatching run and
the dispatched run are separate workflow runs). With the free-tier LLM, a
burst of hand-offs across many goals can hit provider rate limits (`429`); this
is mitigated by `.github/scripts/llm_json.sh`, which retries transport errors
with jittered backoff and honors `Retry-After` (§1). The concurrency groups
(`agent-<role>-<issue>`, `cancel-in-progress: false`) still serialize a role
against itself per issue, so a re-dispatch cannot run a role twice in parallel
on the same issue.

### Idempotency and retries

Each role remains idempotent per attempt (§6/§7): re-running a role for an
attempt that already has its marker short-circuits the LLM and only re-applies
the transition. Repeated dispatches are therefore safe, and a failed hand-off
can be retried by re-applying the role's entry label or re-running the
workflow manually with `issue_number`.

---

## 9. Branch model (v1)

All automated work happens on branches. **Agents never push `dev` or `main`,
never force-push, and never merge to `dev`/`main`.** A human merges the final
integration PR.

### `issue/<parent#>` — integration branch

- Cut from a **fresh `origin/dev`** by the PO (`agent-orchestrate`), once per
  parent issue, before any goal is created.
- The Programmer treats existence as a fallback: it runs
  `git fetch --no-tags origin dev` and, if
  `git ls-remote --exit-code --heads origin "refs/heads/issue/<parent#>"`
  fails, creates the branch locally from `origin/dev`. The branch is published
  by the integration-update push below (with the goal's merge). This is
  race-safe: if a sibling creates the branch first, the push is rejected and the
  bounded retry (see *Integration update retry*) re-fetches and uses the
  sibling's branch instead of failing. Idempotent and never `--force`s.
- Every goal's work lands here (directly or by merge); the branch is the single
  integration point for the parent.

### Integration update retry (bounded)

The Programmer's merge into `issue/<parent#>` races sibling goals of the same
parent (concurrency is per-goal, §5). A rejected (non-fast-forward) integration
push is retried, bounded at **`MAX_INTEGRATION_ATTEMPTS=5`** with a short
`IATTEMPT*2`-second backoff:

```
fetch origin <INTEGRATION>
  → git checkout -B <INTEGRATION> origin/<INTEGRATION>
  → git merge --no-ff <TASK> -m <msg>
  → git push origin <INTEGRATION>
```

- On a rejected push: re-fetch `origin/<INTEGRATION>`, re-checkout, re-merge the
  (unchanged) `task/<goal#>` branch, and push again.
- Fallback branch not yet on `origin`: the first attempt merges into the
  locally created `issue/<parent#>` (from `origin/dev`); if a sibling created it
  first, that push is rejected and the retry fetches/uses the sibling's branch.
- **Real merge CONFLICT:** `git merge --abort` → loud comment + `needs-human` +
  `exit 1`; the integration branch is unchanged.
- **Retries exhausted:** loud comment + `needs-human` + `exit 1`.
- **NO `--force`**, and the only push targets are `issue/<parent#>` and
  `task/<goal#>` — **never `dev`/`main`**.

### `task/<goal#>` — per-goal branch

- Cut by the **Programmer** from the goal's integration branch
  `issue/<parent#>` when the goal is `goal/ready`.
- The Programmer writes the changeset's real files, commits them
  (`feat(goal-#N)` for `kind: code`, else `docs(goal-#N)`), pushes
  `task/<goal#>`, then auto-merges it into `issue/<parent#>` with
  `git merge --no-ff` and pushes the integration branch (bounded retry on a
  concurrent sibling push — see *Integration update retry*). The goal's merge
  target is the integration branch, not `dev`.
- **Stale branch handling:** before cutting `task/<goal#>`, the Programmer
  deletes the local and remote task branch
  (`git branch -D task/<goal#>` / `git push origin --delete task/<goal#>`) and
  recreates it from the integration branch. This means a re-run never needs a
  force-push, and only the agent-owned `task/<goal#>` is ever deleted.
- **Loud failures:** a merge conflict aborts the merge
  (`git merge --abort`) and leaves `issue/<parent#>` unchanged; an empty
  changeset (`git diff --cached --quiet`) or a conflict posts a loud comment,
  moves the goal to `needs-human`, and exits non-zero.

### Safety guards (before writing anything)

Before any file is written, the Programmer rejects the WHOLE changeset (loud
comment + `needs-human` + `exit 1`) if ANY file path fails a strict
**allowlist** applied to the **normalized** path:

- strip a single leading `./` first (so `./.github/workflows/x` and
  `./.git/config` cannot bypass the guard);
- reject an empty path or an absolute path (`/…`);
- reject any path that does not fully match the conservative charset
  `^[A-Za-z0-9._/+@-]+$` (this rejects whitespace, newlines, and control
  characters);
- reject any `..` path segment;
- reject any `.git` path **component**, including nested ones (`sub/.git/x`);
- reject a leading `.` segment that is not an allowed dot-directory
  (`.agents/` and `.github/` are allowed; `.github/workflows/**` is separately
  forbidden);
- reject the `.github/workflows/` prefix or any `.github/workflows` component
  sequence (privilege-escalation guard);
- reject a changeset over **25 files** or **200000 total content bytes**.

No file is ever silently dropped.

### Programmer result payload

The `<!-- result:v1 -->` payload carries `attempt`, `summary`, `kind`, `files`
(repo-relative **paths only**, never contents), `changes`, `evidence`, `commit`
(task-branch SHA), `merge_commit` (integration-branch SHA), `task_branch`,
`integration_branch`, `needs_human`, and `needs_human_reason`. A
`needs_human:true` result moves the goal to `needs-human` (no `goal/review`);
otherwise the goal moves to `goal/review`.

### Non-development goals

Goals whose `kind` is `docs`, `analysis`, `requirement`, or `user-story` are
non-development. The Programmer ignores the model's path and collapses the
changeset to exactly one markdown artifact committed to

```
.agents/issue-<parent#>/goal-<goal#>.md
```

on the integration branch `issue/<parent#>`. `kind: code` is the only kind that
alters repository source/config/files.

### Final integration PR

When **every** child goal of a parent is `goal/done` (§3/§7), the review role
opens **ONE** pull request `issue/<parent#>` → `dev` for human review and merge
(Phase 4b-2). The agent **never** merges that PR and **never** pushes `dev` or
`main`; the human is the only actor who merges.

### Hard rules

- **No workflow edits by agents.** Agents must not modify
  `.github/workflows/**` (privilege-escalation guard). Enforced by the
  Programmer's changeset path guard.
- **No `dev`/`main` pushes, no force-push.** The only branches an agent may
  push are `issue/<parent#>` and `task/<goal#>`.
- **Permission note.** Branch creation and merge require job
  `permissions: contents: write` (the orchestrator and the Programmer both
  declare it). Opening the final PR requires `pull-requests: write` for the
  review role. `issues: write` remains for labels and comments, and
  `actions: write` for `workflow_dispatch` chaining (§8).

---

## 10. Final PR & human gate (Phase 4b-2)

When **every** child goal of a parent is `goal/done` (§3/§7), `agent-review`
opens **exactly one** pull request from the parent's integration branch to `dev`
and stops. This is the ONLY PR the agent loop opens, and it is **human-gated**:

1. The review (already running for the final `done` goal) resolves
   `integration = issue/<parent#>`.
2. It computes `ahead_by` from the fetched git refs, not the compare API:
   `git fetch --no-tags origin dev` (and the integration branch when present),
   branch existence via
   `git ls-remote --exit-code --heads origin "refs/heads/issue/<parent#>"`, then
   `git rev-list --count origin/dev..origin/issue/<parent#>`. A missing branch
   reads as `0`; a fetch/transport failure is **loud** (ERR trap), never
   silently read as `0`. (The compare API cannot take the raw `/` in
   `issue/<n>` as a path param without encoding, which previously made the
   ahead count `0` and suppressed the PR.)
3. **If `ahead_by > 0`:** it opens
   `gh pr create --base dev --head issue/<parent#>` with a title
   `[Issue #<parent#>] <parent title>` and a body listing the child goals +
   links and stating *"Human review required; the agent will not merge. Do not
   merge until reviewed."* Idempotent by open PR head:
   `gh pr list --head issue/<parent#> --state open` — an existing open PR is
   reused, never duplicated. Creation is **tolerant**: if `gh pr create` fails
   because a racing review already opened the PR, the role re-lists, reuses the
   winner's URL, and does not fail; if no PR exists after the failure it
   surfaces the error through the ERR trap.
4. **If the branch is missing or `ahead_by == 0`:** no PR is opened; the
   `<!-- parent-done:v1 -->` comment records "no changes to propose".
5. In both cases the parent gets `status:done` + the `<!-- parent-done:v1 -->`
   marker (idempotent: skipped when the marker or `status:done` already exists;
   the marker is re-read immediately before posting to defeat a racing review).
   The issue is **not** auto-closed.

Before opening the PR the review also performs a **mechanical file check**: each
`result:v1` path is looked up on the fetched integration branch via
`git cat-file -e origin/issue/<parent#>:<path>` (read-only git; the job keeps
`contents: read` and no git auth beyond the read-only checkout token). A
`MISSING` path makes the prompt instruct a non-`done` verdict, and a model that
still returns `done` is force-downgraded to `revise`. The `ahead_by` count and
the file evidence are included in the verdict prompt using the **resolved**
integration branch (the `result.v1.integration_branch` value, or the
`issue/<parent#>` fallback).

Hard rules:

- **Agents never merge.** There is no `gh pr merge`, no `git merge` into
  `dev`/`main`, and no push of `dev`/`main` anywhere in the review role. The
  human is the only actor who merges the PR.
- **Review permissions.** Opening (and listing) the PR requires the review job's
  `pull-requests: write`; it keeps `contents: read` (it never writes repo
  contents), `issues: write` (labels/comments) and `actions: write`
  (`workflow_dispatch` chaining, §8). It explicitly does **not** add
  `contents: write`.
- **Non-development artifacts are not lost.** Goals of `kind` `docs`,
  `analysis`, `requirement`, or `user-story` commit their markdown artifacts
  (`.agents/issue-<parent#>/goal-<goal#>.md`, §9) to the same integration
  branch, so a parent whose goals are all non-development still produces a
  non-empty `issue/<parent#>` → `dev` PR carrying those markdown files.
- **Result contract.** The review accepts the Phase 4b-1 `result:v1` shape
  (paths-only `files`, `commit`, `merge_commit`, `task_branch`,
  `integration_branch`, `needs_human`, `needs_human_reason`, `attempt`). A
  missing/invalid payload or `needs_human:true` escalates to `needs-human`
  without an LLM call.
