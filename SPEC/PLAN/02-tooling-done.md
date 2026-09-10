# PLAN 02 — Done Tooling (summary)

> Status: done. Sources: `../../../scripts/`, `../../../.github/pull_request_template.md`, `../_template.md`,
> `../../../TEST-REPORT/_template.md`, `.gitignore`, root `../../../TASKS.md` Done section.

## 5 session scripts (`scripts/`)

- `new-session.sh` — cut a fresh `session/<TASK-ID>-<slug>-<date>-<init>` branch from `dev`.
- `open-mr.sh` — open the MR/PR targeting `dev` (uses the PR template).
- `verify-dev.sh` — verify `dev` health after client merge (used by `@devops` / `@tester`).
- `smoke.sh` — smoke-check the static site renders/serves.
- `sync-tasks.sh` — task-status helper; **full sync logic still TODO, `--check` mode only**
  (tracked as open item T-006; see `../PENDING/02-open-tasks.md`).

## Templates + conventions

- `.github/pull_request_template.md` — MR body: Task ID, Spec link, What/Why, Changes,
  How tested, acceptance-criteria mapping, merge-target confirmation, QA request.
- `../_template.md` — blank SPEC (problem, users, stories, ACs, non-goals, test plan, risks).
- `../../../TEST-REPORT/_template.md` — QA report with AC matrix + final `QA: PASS|FAIL` verdict line.
- `../../../AGENTS.md`, `../../../docs/GIT-FLOW.md`, `../../../docs/ROLES.md` — workflow + roles (see `01-agent-workflow.md`).
- `.gitignore` — `node_modules/`, `.DS_Store`, `*.log`.

## QA note

- T-001 / T-003 / T-004 marked QA PASS 2026-09-10 in root `../../../TASKS.md` (file-asserted only).
- Repo has **0 commits and no remote**, so no merge SHA exists for these verdicts.
