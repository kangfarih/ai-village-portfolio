# PENDING 02 — Open / Blocked Tasks (AWAITING ORDER)

> Status: **AWAITING ORDER.** Source: root `../TASKS.md` Backlog + Blocked. Not cleared for execution.

## T-002 — Branch bootstrap (blocked: remote URL)

- Scope: initial commit, rename `master→main`, create `dev`, add remote, push, branch
  protection (no direct push, require PR + CI + 1 approval). Owner: `@devops`.
- Blocked on: Q6 (forge choice GitHub vs GitLab + remote URL from human). No remote configured; 0 commits.

## T-005 — CI gate for static site

- Scope: `.github/workflows/ci-dev.yml` (htmlhint/stylelint/eslint/link check/smoke)
  + branch-name + commit lint. Owner: `@devops`.
- Note: workflow dirs (`.github/workflows/`, `.opencode/workflows/`) do not exist yet.

## T-006 — Task-status automation (full sync TODO)

- Scope: full sync logic for `scripts/sync-tasks.sh` still TODO; `--check` mode only. Owner: `@task-manager`.

## T-007 — First pilot task (SPEC written, execution pending T-002)

- Scope: SPEC done (`../T-007-pilot.md`: zero-risk `../../README.md`);
  run branch→MR→merge→QA→Done once T-002 unblocked. Owner chain: `@planner`→`@coder`→`@tester`.
