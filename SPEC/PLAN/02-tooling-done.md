# PLAN 02 — Done Tooling (summary)

> Status: **DRAFT** — tooling described below is NOT landed; most targets are missing. Do NOT treat as done.
> Sources (repo-relative): `SPEC/_template.md`, `SPEC/TASKS.md`, `SPEC/PENDING/02-open-tasks.md`, `01-agent-workflow.md`.
> TODO (missing targets — NOT done): `scripts/` (absent; only empty `.scripts/` exists), `.github/pull_request_template.md` (absent), `TEST-REPORT/` incl. `TEST-REPORT/_template.md` (absent), `.gitignore` (absent), `AGENTS.md` (absent), `docs/` incl. `docs/GIT-FLOW.md` + `docs/ROLES.md` (absent).
> Note: all broken deep-relative (old triple-parent dot-dot-slash x3) paths from the prior revision were fixed (from `SPEC/PLAN/` the repo root is two levels up, not three). This revision uses repo-relative paths only.

## 5 session scripts (`scripts/` — TODO, absent)

> TODO: `scripts/` does not exist; only empty `.scripts/` exists. None of the scripts below are landed.

- `scripts/new-session.sh` — (TODO) cut a fresh `session/<TASK-ID>-<slug>-<date>-<init>` branch from `dev`.
- `scripts/open-mr.sh` — (TODO) open the MR/PR targeting `dev` (uses the PR template).
- `scripts/verify-dev.sh` — (TODO) verify `dev` health after client merge (used by `@devops` / `@tester`).
- `scripts/smoke.sh` — (TODO) smoke-check the static site renders/serves.
- `scripts/sync-tasks.sh` — (TODO) task-status helper; **full sync logic still TODO, `--check` mode only**
  (tracked as open item T-006; see `SPEC/PENDING/02-open-tasks.md`).

## Templates + conventions (mostly TODO)

- `.github/pull_request_template.md` — (TODO, absent) MR body: Task ID, Spec link, What/Why, Changes,
  How tested, acceptance-criteria mapping, merge-target confirmation, QA request.
- `SPEC/_template.md` — exists: blank SPEC (problem, users, stories, ACs, non-goals, test plan, risks).
- `TEST-REPORT/_template.md` — (TODO, absent) QA report with AC matrix + final `QA: PASS|FAIL` verdict line.
- `AGENTS.md`, `docs/GIT-FLOW.md`, `docs/ROLES.md` — (TODO, all absent) workflow + roles (see `01-agent-workflow.md`).
- `.gitignore` — (TODO, absent) intended: `node_modules/`, `.DS_Store`, `*.log`.

## QA note (corrected 2026-09-10)

- T-001 / T-003 / T-004 marked QA PASS 2026-09-10 in `SPEC/TASKS.md` (file-asserted only; no root `TASKS.md`).
- Prior revision claimed "0 commits and no remote" — corrected: repo has 1 commit `1c837c5`
  (`init: ai-village-portfolio`) and remote `origin` (`https://github.com/kangfarih/ai-village-portfolio.git`).
  No merge SHA exists for these verdicts (file-asserted only).
- Branches: only `main` (+ `origin/main`); no `dev` branch. `gh` CLI not installed.
- `.agents/` (canonical, 5 files): `.agents/product-owner.md`, `.agents/tech-lead.md`,
  `.agents/programmer.md`, `.agents/qa-tester.md`, `.agents/devops.md` (plus `.agents/PLAN-01/NOTES.md`).

## NOTES (verification 2026-09-10)

- `rg '\.\./\.\./\.\./' SPEC/PLAN/02-tooling-done.md` = 0 matches (no triple-parent escapes remain).
- `wc -l SPEC/PLAN/02-tooling-done.md` = 42 lines.
- Evidence: `ls scripts/` absent (only empty `.scripts/`); `.github/pull_request_template.md`, `TEST-REPORT/`, `.gitignore`, `AGENTS.md`, `docs/` all absent; `git log --oneline` = 1 commit `1c837c5`; `git remote -v` = `origin`; `git branch -a` = only `main` + `origin/main`; `gh` not installed; `.agents/` = 5 role files + `PLAN-01/NOTES.md`.
