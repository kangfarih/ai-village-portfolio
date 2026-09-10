# SPEC Template — T-XXX <short slug>

> Owner: `@planner` (drafts) → `@task-manager` (tracks). Copy this file to `T-XXX-<slug>.md` for each new task. Keep it small; link evidence, don't paste dumps.

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

<!-- Checkbox list. Must be verifiable on `dev` after merge. @tester checks each box. Keep 3-7 items, each independently testable. -->

- [ ] AC-1: …
- [ ] AC-2: …
- [ ] AC-3: …

## 5. Non-goals

<!-- Explicitly out of scope for this task. Prevents scope creep. -->

- NG-1: …
- NG-2: …

## 6. Test plan (hooks for @tester)

<!-- How @tester verifies on `dev` post-merge. Map each AC to a check. Prefer manual + static checks for this static-site repo; add automated commands where they exist. -->

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
- Target: MR/PR → `dev` (client merges; `@tester` verifies on `dev`)
