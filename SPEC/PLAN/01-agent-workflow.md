# PLAN 01 — Agreed Agent Workflow (summary)

> Sources: `../../../AGENTS.md`, `../../../docs/GIT-FLOW.md`, `../../../docs/ROLES.md`, `../../../.opencode/agents/`, `../../../.github/agents/`.
> This file summarizes; it does not paste the full sources. Status: agreed/done.

## 6 agents

Definitions live in `.opencode/agents/` mirrored to `.github/agents/` (keep in sync).
`../../../docs/ROLES.md` is the 1-page cheat sheet; rule of thumb: planner thinks, coder builds,
fixer repairs, tester proves, task-manager tracks, devops ships the plumbing.

| Agent | Role |
|---|---|
| `@planner` | Brainstorm + requirements. Writes `../<TASK-ID>-<slug>.md`. Read-only, never codes. |
| `@coder` | Feature implementer. One task per session branch, conventional commits, MR to `dev`. |
| `@fixer` | Bug fixer. Reproduce first, minimal fix + regression test, `fix:` MR to `dev`. |
| `@tester` | QA. Verifies merged `dev` vs SPEC, files `QA: PASS/FAIL`. Never fixes product code. |
| `@task-manager` | Sole writer of root `../../../TASKS.md`. Moves tasks only on git evidence. |
| `@devops` | Environment + pipeline: branches, remote, CI, `scripts/`. |

## Pipeline

```
IDEA → SPEC → TASK → session branch → MR to dev → CLIENT merge → TEST → Done
```

- `@planner` drafts SPEC from `../_template.md`; `@task-manager` tracks it in `../../../TASKS.md`
  (Backlog → In Progress → In Review → Done, only on evidence).
- Session branch → MR/PR to `dev` → **human (client) merges only** → `@tester` verifies on
   `dev`, writes `../../../TEST-REPORT/T-XXX-<slug>.md` with `QA: PASS|FAIL`.
- Bug loop: `QA: FAIL` (+ repro) → `B-###` → `@fixer` session branch → `fix:` MR → re-test
  (2nd failure escalates to `@planner`). See `../../../docs/GIT-FLOW.md`.

## Conventions

- Session branch: `session/<TASK-ID>-<slug>-<YYYYMMDD>-<init>`
  (e.g. `session/T-042-auth-refresh-20260910-a`). Bugs: `B-###`; retries: `session/T-###-fixN-...`.
  Always from fresh `dev`; never push to `dev`/`main` directly.
- Commits: `<type>(<scope>): <TASK-ID> <short>` (e.g. `feat(auth): T-042 add refresh rotation`).
  Bug fixes add `Root cause:` + `Fixes #<issue>`. No `WIP`. One task per MR, diffs < ~400 lines.
- Human-only merge: agents never merge their own MR. `@tester` QA `PASS` on merged `dev`
  is required before `@task-manager` moves a task to Done. Evidence over claims
  (branch names, MR URLs, SHAs).
