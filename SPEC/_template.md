# SPEC Template — T-XXX <short slug>

> Owner: `product-owner` (drafts SPEC, owns DoR + Status) → `tech-lead` (sole writer of `SPEC/TASKS.md` mirror; GitHub Issues/Projects canonical). Copy this file to `T-XXX-<slug>.md` for each new task. Keep it small; link evidence, don't paste dumps.

## 1. Problem

<!-- 2-4 sentences. What is broken/missing? What is the user-visible impact? Reference repo paths or TASKS.md line if applicable. -->

- Context:
- Impact if not done:

## 2. Users

<!-- Who benefits? e.g. visitor, maintainer, agent-loop. -->

- Primary:
- Secondary (optional):

## 3. User stories

<!-- 1-3 stories in "As a … I want … so that …" form. -->

- [ ] As a … I want … so that …
- [ ] As a … I want … so that …

## 4. Acceptance criteria

<!-- Checkbox list. Must be verifiable on session branch preview (local run `python3 -m http.server`) + post-merge `dev` SHA. `qa-tester` checks each box. Keep 3-7 items, each independently testable. DoR hint: Status → `Ready` only when ACs testable, scope ≤400-line slice, no missing inputs. -->

- [ ] AC-1: …
- [ ] AC-2: …
- [ ] AC-3: …

## 5. Non-goals

<!-- Explicitly out of scope for this task. Prevents scope creep. -->

- NG-1: …
- NG-2: …

## 6. Test plan (hooks for qa-tester)

<!-- How `qa-tester` verifies: session branch preview (local run `python3 -m http.server`) + merged `dev` SHA. Map each AC to a check. Prefer manual + static checks for this static-site repo; add automated commands where they exist. User loop: preview → `/approve` (proceed to merge) | `/changes` (revise, no cap — User is owner/merger, loop until `/approve`). -->

| AC | How to verify | Command / URL | Expected |
|----|---------------|---------------|----------|
| AC-1 | … | … | … |
| AC-2 | … | … | … |
| AC-3 | … | … | … |

- Smoke steps:
  1. …
  2. …
- Regression guard (files that must NOT change, if any):
  - …

## 7. Risks

<!-- What could go wrong? Merge conflicts, scope creep, env gaps, missing remote, etc. + mitigation. -->

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| … | Low/Med/High | … |

---

### Meta

- Task ID: `T-XXX`
- Source backlog item: `…/TASKS.md` → …
- Branch convention: `session/T-XXX-<slug>-<YYYYMMDD>-<init>`
- Target: PR → `dev` (User/human sole merger; `qa-tester` verifies on merged `dev` SHA → `TEST-REPORT/T-XXX-<slug>.md`)
