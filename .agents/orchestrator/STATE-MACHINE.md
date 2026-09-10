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
| **Programmer** | `agent-programmer` | `goal/ready` | **medium** for code, **low** for docs/analysis | `thinkingmachines/inkling:free` |

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
  └── PO verdict REVISE → goal/revise
                           attempt+1, re-enter at goal/tl
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
| `goal/review` | `goal/revise` | PO | verdict REVISE |
| `goal/revise` | `goal/tl` | PO | revision queued, attempt+1 |

### Goal creation (PO)

The orchestrator creates sub-issues titled `[GOAL] <title> (from #<parent>)`:

- **Labels applied:** `ai-goal` **and** `goal/tl`. `ai-goal` is the
  orchestrator's bookkeeping label; `goal/tl` hands the goal to the TL workflow.
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
  `<!-- attempts:N -->`. The PO increments it each time it moves a goal to
  `goal/revise`; the TL/Programmer read it to size the revision.
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
