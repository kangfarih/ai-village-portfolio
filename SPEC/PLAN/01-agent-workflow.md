# PLAN 01 — Simplified Agent Workflow: 3-Agent Pipeline

> Status: **ACTIVE** — simplified 3-agent flow replaces the old 6-agent pipeline.
> Agents: `triage` → `tech-lead` → `programmer`

## Overview

The old 6-agent pipeline (PO, TL, Programmer, QA, DevOps, Orchestrator) has been replaced with a simpler 3-agent flow that handles all technical work through a chat session model.

## Flow

```
User creates issue + ai-triage label
  → agent-triage (classify technical vs non-technical)
      ├─ non-technical → create deliverable issue → status:done
      └─ technical → kind/technical + tl/ready → dispatch agent-techlead
                      (chat session mode)
                      ├─ 1st run: classify coding vs research
                      │   ├─ research → LLM findings → post comment → done
                      │   └─ coding → write tl:v1 spec → cut session/{id}-dev → dispatch programmer
                      └─ subsequent runs: read latest comment → dispatch programmer if needed → detect PR merge → done
                            │
                            ▼ (coding only)
                          agent-programmer
                          - Read tl:v1 spec
                          - Code on session/{id}-dev
                          - Push + create PR → dev
                          - Post BUILT comment
```

## Roles

| Agent | Role |
|---|---|
| `triage` | Classifies issues as technical vs non-technical. Entry point. |
| `tech-lead` | Handles ALL technical work: classification, specification, delegation, monitoring. Chat session mode. |
| `programmer` | Sole code writer on `session/*` branches. Implements specs, creates PRs. |

## Labels

| Label | Purpose |
|---|---|
| `ai-triage` | Entry trigger (human adds this) |
| `kind/technical` | Requires technical work |
| `kind/non-technical` | Admin/organizational |
| `tl/ready` | Tech-lead should pick up |
| `tl/building` | Tech-lead/programmer working |
| `tl/done` | Work complete (terminal) |
| `status:done` | Issue complete |

## Key Decisions

- **Tech-lead handles ALL technical work** (coding + research/analysis)
- **Chat session mode**: tech-lead re-runs on every new comment (`issue_comment` trigger)
- **PR auto-update**: tech-lead detects PR feedback, re-dispatches programmer
- **Merge detection**: tech-lead checks `gh pr list --state merged --head session/{id}-dev`
- **Non-coding deliverable**: creates a separate GitHub issue
- **Branch naming**: `session/{issue-number}-dev`
- **Reuses existing `llm_json.sh`** for all LLM calls

## Files

| File | Purpose |
|---|---|
| `.github/workflows/agent-triage-active.yml` | Triage workflow |
| `.github/workflows/agent-techlead.yml` | Tech-lead workflow (chat session) |
| `.github/workflows/agent-programmer.yml` | Programmer workflow |
| `.agents/triage.md` | Triage agent prompt |
| `.agents/tech-lead.md` | Tech-lead agent prompt |
| `.agents/programmer.md` | Programmer agent prompt |

## Superseded Files

The following files from the old 6-agent pipeline are superseded:
- `agent-orchestrate.yml`, `agent-review.yml`, `agent-triage.yml`
- `.agents/orchestrator/`, `.agents/product-owner.md`, `.agents/qa-tester.md`, `.agents/devops.md`

## Conventions

- **Session branch**: `session/{issue-number}-dev`
- **Commits**: `feat(scope): {issue-number} {summary}`
- **Human-only merge**: agents never merge their own PR
- **Evidence over claims**: every Status move cites branch name + PR URL + merge SHA
