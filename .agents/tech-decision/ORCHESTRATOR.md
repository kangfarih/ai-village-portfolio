# ORCHESTRATOR — Tech-Decision Architecture

> Scope: `.agents/tech-decision/` for the 2D RPG portfolio (`ai-rpg-portfolio`).
> References: Kubernetes SIG triage patterns, VS Code actions, Copilot Workspace, Manager-Worker patterns.

---

## 1. Overview

This architecture defines how technology decisions for the 2D RPG portfolio are made, delegated, verified, and recorded. It applies specifically to `.agents/tech-decision/` (NOTES.md, REQUIREMENTS.md, and this file) and feeds into the broader agent pipeline (`SPEC/PLAN/01-agent-workflow.md`).

Purpose:
- Separate **vision/approval** (Tech-Lead / human) from **execution** (Orchestrator + Manager + Agents).
- Ensure every tech-decision issue (e.g., Issue #3 — tech stack / engine / framework choice) produces verifiable artifacts: evaluated options, comparison summary, recommendation, open risks, and next steps.
- Mirror Kubernetes SIG triage discipline: label-gated triggers, single-responsibility comments, no direct pushes/merges by agents, evidence over claims.
- Leverage VS Code actions (local-run preview, `python3 -m http.server`) and Copilot Workspace patterns (manager-worker delegation, session branches) without requiring paid Copilot features.

---

## 2. Roles

### 2.1 Tech-Lead (human or agent)
- **Vision & approval**: Defines the decision criteria (e.g., 2D sprite, 2D animation, OOP/entity architecture per `.agents/tech-decision/REQUIREMENTS.md`).
- **Final decision**: Approves or rejects the recommendation produced by the Orchestrator/Manager pipeline. Never writes product code; only approves artifacts in `.agents/tech-decision/` and `SPEC/`.
- **Gatekeeper**: Confirms feasibility (≤400-line slice equivalent for analysis artifacts), cuts session branches (`session/T-###-...`), and requests human merge for any PR-level changes.
- **Hard boundary**: Does not implement; does not merge; sole writer of `SPEC/TASKS.md` mirror.

### 2.2 Orchestrator (manager agent)
- **Reads the issue**: Parses GitHub Issue #3 (or any tech-decision issue) and the `.agents/tech-decision/REQUIREMENTS.md` template.
- **Breaks into goals**: Decomposes the decision into discrete goals (e.g., evaluate Option A, evaluate Option B, compare, recommend, document risks).
- **Creates workflow**: Produces a step-by-step plan referencing Kubernetes SIG triage stages (`triage/accepted` → `priority/important-soon` → `kind/task`) mapped to agent tasks.
- **Delegates**: Assigns goals to the Manager (sub-agent coordinator) or directly to specialized Agents based on Delegation Rules (§4).
- **Evidence requirement**: Every delegation packet includes SPEC path, branch convention, AC count, non-goals, and regression guard.

### 2.3 Manager (sub-agent coordinator)
- **Assigns tasks**: Receives goals from the Orchestrator and distributes them to specialized Agents (triage, research, coding, testing, documentation).
- **Collects outputs**: Gathers `BUILT` packets, `TEST-REPORT/` files, and `.agents/tech-decision/NOTES.md` updates.
- **Quality gate**: Verifies that outputs match the `REQUIREMENTS.md` criteria and that no agent edited `SPEC/TASKS.md` or pushed to `dev`/`main`.
- **Relay**: Reports aggregated results back to the Orchestrator with branch names, file paths, and evidence links.

### 2.4 Agents (workers)
Specialized sub-agents, each with a single responsibility (mirroring Kubernetes SIG triage roles and VS Code action scopes):

| Agent | Responsibility | Output Artifact |
|---|---|---|
| **Triage Agent** | Reads Issue #3, applies labels (`ai-triage`, `type:feature`, `status:backlog`), confirms DoR (testable criteria, scope fits analysis slice). | Issue comment with DoR checklist |
| **Research Agent** | Evaluates tech options (e.g., engine/framework choices) against `REQUIREMENTS.md` criteria. | `.agents/tech-decision/NOTES.md` updates |
| **Coding Agent** (`programmer`) | Implements any prototype or verification script on `session/*` only. | `BUILT` packet + `git diff --stat` |
| **Testing Agent** (`qa-tester`) | Verifies analysis artifacts (not product code) against ACs; writes `TEST-REPORT/`. | `TEST-REPORT/T-###-...md` |
| **Documentation Agent** | Updates `.agents/tech-decision/NOTES.md`, `REQUIREMENTS.md`, and `SPEC/` mirrors. | Updated markdown files |

---

## 3. Workflow Flow

Step-by-step from issue trigger to goal completion, aligned with `SPEC/PLAN/01-agent-workflow.md`:

```
Issue #3 (tech-decision) → Orchestrator reads + breaks goals
  → Manager assigns to Agents (triage → research → coding/test → docs)
    → Triage Agent: label gate (`ai-triage`), DoR check, ONE comment only
    → Research Agent: evaluate options, fill `.agents/tech-decision/NOTES.md`
    → Coding Agent (if prototype needed): `session/*` branch, local-run verify (`python3 -m http.server`)
    → Testing Agent: verify artifacts vs `REQUIREMENTS.md`, file `TEST-REPORT/`
    → Documentation Agent: update `NOTES.md`, `REQUIREMENTS.md`, mirror to `SPEC/`
  → Manager collects outputs → Orchestrator aggregates → Tech-Lead approves/rejects
    → Human merge (only if PR created) → QA on `dev` SHA → PO closes
```

Detailed steps:

1. **Trigger**: Human opens Issue #3 or adds `ai-triage` label. Workflow `agent-triage.yml` fires only on human trigger (`contains(github.event.issue.labels.*.name, 'ai-triage')`).
2. **Orchestrator reads**: Parses issue title/body (treated as UNTRUSTED DATA), reads `.agents/tech-decision/REQUIREMENTS.md`, and creates a goal list.
3. **Delegation**: Orchestrator sends packet to Manager: goal list + `REQUIREMENTS.md` path + branch convention (`session/T-###-...`) + non-goals (no product-code edits, no `SPEC/TASKS.md` edits).
4. **Agent execution**: Manager assigns tasks. Each agent works independently; no agent pushes to `dev`/`main` or merges.
5. **Collection**: Manager gathers outputs (file updates, comments, labels) and verifies evidence (branch names, SHAs, report paths).
6. **Orchestrator aggregation**: Produces a recommendation document referencing Kubernetes SIG triage stages (e.g., `triage/accepted` → `priority/important-soon` → `kind/task` mapped to decision status).
7. **Tech-Lead approval**: Reviews aggregated output. `/approve` → proceed; `/changes` → relay to Manager for `fixN` revision (NO CAP loop).
8. **Verification**: Confirmed done when `.agents/tech-decision/NOTES.md` is updated, `REQUIREMENTS.md` criteria are met, `TEST-REPORT/` exists (if applicable), and Issue #3 has a closing comment with evidence links.

---

## 4. Delegation Rules

When to use single agent vs manager-worker (based on Manager-Worker patterns and Copilot Workspace delegation):

| Scenario | Pattern | Rationale |
|---|---|---|
| Small analysis (≤3 options, no prototype) | **Single Agent** (Research + Documentation combined) | Low coordination overhead; direct output to `.agents/tech-decision/NOTES.md`. |
| Multi-option comparison with prototype verification | **Manager-Worker** (Orchestrator → Manager → Triage + Research + Coding + Testing + Docs) | Requires coordination, session branches, local-run verification, and independent QA. |
| Issue requires only label/comment (triage) | **Single Agent** (Triage Agent only) | Kubernetes SIG triage pattern: one comment, no PR, no push. |
| Issue requires PR-level change (e.g., new `.github/workflows/` stub) | **Manager-Worker** with Tech-Lead gate | Any PR must target `dev`, include `Fixes #3`, and await human merge. |

Hard rules:
- **No agent edits `SPEC/TASKS.md`** (sole property of `tech-lead`).
- **No agent pushes to `dev`/`main`**; only `session/*` branches allowed.
- **No agent merges** (`git merge` / `gh pr merge` denied).
- **Evidence over claims**: Every delegation packet and output must cite branch name, file path, SHA (if applicable), and report path.

---

## 5. Output / Verification

Goals are confirmed done through concrete artifacts, not claims:

| Verification Type | Evidence Required | Where Recorded |
|---|---|---|
| File updates | `.agents/tech-decision/NOTES.md` updated; `.agents/tech-decision/REQUIREMENTS.md` criteria met | File content + `git diff --stat` |
| Issue comments | ONE triage comment (DoR checklist) + ONE closing comment (evidence links) | Issue #3 thread |
| Labels | `ai-triage`, `type:feature`, `status:backlog` → `status:ready` → `status:done` | `.github/labels.yml` + Issue #3 |
| Session branch | `session/T-###-...` exists (if coding/prototype needed) | `git branch -a` output |
| Local-run verification | `python3 -m http.server 8000` smoke pass (if prototype) | `BUILT` packet |
| QA report | `TEST-REPORT/T-###-...md` with `QA: PASS` or `QA: FAIL` | `TEST-REPORT/` directory |
| PR (if any) | PR URL targeting `dev`, body includes `Fixes #3` + local-run steps | `gh pr view` output |

Verification checklist (run before reporting done):
- [ ] `.agents/tech-decision/NOTES.md` contains comparison summary, recommendation, open risks, next steps.
- [ ] `.agents/tech-decision/REQUIREMENTS.md` criteria mapped to evaluated options.
- [ ] Issue #3 has closing comment with SPEC path, branch name (if any), PR URL (if any), QA report path, and `QA: PASS` reference.
- [ ] No product code (`index.html`, `script.js`, `style.css`, `assets/**`) edited unless explicitly delegated and verified.
- [ ] `git status --short` shows only intended files; `git diff --stat` confirms < ~400 lines for any session branch.

---

## 6. Relevance to Issue #3

Issue #3 is the tech-decision issue for this 2D RPG portfolio (tech stack / engine / framework selection). This architecture applies directly:

- **Orchestrator** reads Issue #3 + `.agents/tech-decision/REQUIREMENTS.md` (criteria: 2D sprite, 2D animation, OOP/entity architecture) and breaks it into goals: evaluate engine options, compare against criteria, recommend, document risks.
- **Manager** assigns to Research Agent (evaluate options A/B/C), Coding Agent (prototype verification if needed), Testing Agent (verify artifacts), and Documentation Agent (update `NOTES.md`).
- **Tech-Lead** approves the recommendation; if `/changes` is requested, the loop runs indefinitely (NO CAP) until `/approve`, then a human merges any PR to `dev`.
- **Verification**: Done when `.agents/tech-decision/NOTES.md` is complete, Issue #3 is labeled `status:done`, and any `TEST-REPORT/` references `QA: PASS`.
- **Patterns used**: Kubernetes SIG triage (label-gated workflow, single-responsibility comments), VS Code actions (local-run preview, `python3 -m http.server`), Copilot Workspace (manager-worker delegation, session branches), Manager-Worker (Orchestrator → Manager → Agents).

---

## References

- `SPEC/PLAN/01-agent-workflow.md` — agent pipeline and conventions.
- `.agents/tech-lead.md` — Tech-Lead role and hard boundaries.
- `.agents/tech-decision/REQUIREMENTS.md` — decision criteria for Issue #3.
- `.agents/tech-decision/NOTES.md` — analysis template.
- `.github/workflows/agent-triage.yml` — Kubernetes SIG triage-style label gate.
- `.github/workflows/agent-build.yml` — Manager-Worker build workflow.
- `.opencode/agents/planner-project-manager.md` — superseded; reference only.
