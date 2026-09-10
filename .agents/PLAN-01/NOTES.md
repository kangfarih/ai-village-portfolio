# NOTES — PLAN 01 rewrite (PO → Tech-Lead → Programmer loop)

Date: 2026-09-10. Rewrote `SPEC/PLAN/01-agent-workflow.md` in place (no new PLAN 03).

## What changed
- Retired 6 flat agents (`planner/coder/fixer/tester/task-manager/devops`); replaced with `product-owner` / `tech-lead` / `programmer` / `qa-tester` / `devops` / `User` (human sole acceptor + merger) with ownership as specced.
- Replaced pipeline `IDEA → SPEC → TASK → session → MR → CLIENT merge → TEST → Done` with `Issue → PO SPEC+DoR → TL feasible → programmer build → TL QA → PR → user preview /approve|/changes (max 3, escalate to PO) → human merge → tester QA on dev SHA → PO close`.
- Status changed `agreed/done` → `DRAFT` (blocked on `dev` branch + `gh` auth; verified 2026-09-10: only `main`/`origin/main` exist, `gh` not installed).
- Fixed ALL broken `../../../` paths (4 hits → 0); switched to repo-relative paths (`SPEC/...`, `TEST-REPORT/...`, `.opencode/agents/`).
- Flagged missing targets as TODO not done: `AGENTS.md`, `docs/` (`docs/GIT-FLOW.md`, `docs/ROLES.md`), `TEST-REPORT/`, `.github/agents/`.
- Replaced old post-merge-only DoD with single ordered 6-gate DoD (ACs → TL QA PASS → user approve → merge → tester PASS → PO Done); old DoD explicitly retired.
- Kept conventions: session branch regex, conventional commits + `Fixes #`, 1 task/MR <400 lines, human-only merge, evidence-over-claims (branch+MR+SHA+QA report).

## Verification (to run)
- `ls SPEC/PLAN/01-agent-workflow.md`, `rg '../../../' SPEC/PLAN/01-agent-workflow.md` (expect 0 hits), `wc -l SPEC/PLAN/01-agent-workflow.md`.

## Open conflicts needing user decision
- Tracker source, merge owner, preview, iteration cap — see report.

---

## 2026-09-10 — Created `.agents/` 5-agent set (supersedes legacy planner)

Created (user explicitly chose `.agents/` local repo, NOT `.opencode/agents`):

- `.agents/product-owner.md` — watches Issues/comments via `gh`, writes `SPEC/T-XXX`
  from `SPEC/_template.md`, owns Status Backlog→Ready→Done, handoff READY-FOR-BUILD to
  tech-lead. Read-only on product code, writes `SPEC/**` only. Denies
  `git push/commit/merge`, `gh pr merge`.
- `.agents/tech-lead.md` — decomposes ≤400-line slices, cuts
  `session/<ID>-<slug>-YYYYMMDD-<init>` from fresh `dev`, delegates to programmer,
  pre-PR QA, creates PR→`dev` with `Fixes #`, relays user `/changes` (no cap) to
  programmer `fixN`, requests human merge. Sole writer of `SPEC/TASKS.md` mirror.
- `.agents/programmer.md` — sole code writer on `session/*` only, conventional commits
  `feat/fix(scope): T-XXX`, one task/branch, replies BUILT packet. Denies `dev`/`main`
  push, `gh issue`/`pr merge`, board edits.
- `.agents/qa-tester.md` — verifies merged `dev` SHA vs SPEC ACs, writes
  `TEST-REPORT/T-XXX` with `QA: PASS|FAIL`, never fixes code. 2nd FAIL escalates to PO.
- `.agents/devops.md` — owns `dev` branch, local-run docs, CI smoke/branch-lint stubs,
  branch-protection docs. Never implements features.

Each file: frontmatter `mode: subagent`, `temperature` 0.1-0.2, explicit
`permission.edit` + `permission.bash` allow/deny. Each references
`SPEC/PLAN/01-agent-workflow.md` pipeline + GitHub-canonical tracker + local-run preview.

Decisions applied (locked, do not re-litigate):

- Tracker: GitHub Issues/Projects canonical, `SPEC/TASKS.md` is mirror only
  (tech-lead sole writer).
- Preview: local run only (`python3 -m http.server`, no Pages/Vercel).
- Iteration: NO CAP — user is owner/manager, loop until user `/approve`; PO watches
  ticket and re-queues to tech-lead indefinitely. (QA FAIL still escalates to PO on
  2nd FAIL; user-loop itself has no cap.)
- Legacy `.opencode/agents/planner-project-manager.md` **SUPERSEDED** by this
  `.agents/` set — file left in place, NOT deleted. Do not use it for new work;
  `product-owner.md` replaces its SPEC role and `tech-lead.md` replaces its tracking
  role (TASKS mirror).

---

## 2026-09-10 — Applied 4 locked user decisions to `SPEC/PLAN/01-agent-workflow.md` (still 54 lines)

- Tracker: GitHub Issues/Projects canonical; `SPEC/TASKS.md` mirror only, tech-lead sole writer (Sources line + roles + pipeline).
- Agents: definitions live in `.agents/` (5 files); `.opencode/agents/planner-project-manager.md` marked SUPERSEDED, no `.github/agents/` mirror TODO.
- Preview: local run only (`python3 -m http.server`, no Pages/Vercel); tech-lead requests, devops provisions docs (roles + steps 4-5 + DoD).
- Iteration: NO CAP — user is owner/manager, loop on `/changes` until `/approve`; QA 2nd-`FAIL`→PO escalation kept separate (pipeline + step 5 + step 6).
- Reviewer nits: `tester`→`qa-tester`, `MR`/`MR-PR`→`PR`, `QA: PASS|FAIL`→`QA: PASS` or `QA: FAIL`, single `DRAFT` (title tag removed, Status line keeps it), tech-lead-requests/devops-provisions clarified.
- Verify: `rg -F '../../../' SPEC/PLAN/01-agent-workflow.md` = 0 hits, `ls .agents/*.md` = 5 files, `wc -l` = 54.

## 2026-09-10 — Fixed reviewer W1+N1 warnings (agent-name grep consistency)

- Replaced `tester QA` → `qa-tester QA` in pipeline one-liners of all 5 `.agents/*.md`
  files (`product-owner.md:50`, `tech-lead.md:56`, `programmer.md:52`, `devops.md:55`,
  `qa-tester.md:50`).
- Fixed `.agents/qa-tester.md:2` frontmatter `description: QA tester` →
  `description: qa-tester` for grep consistency.
- Verify: `rg 'tester QA' .agents/*.md` = 0 hits, `rg 'qa-tester QA' .agents/*.md` = 5 hits,
  `ls .agents/*.md` = 5 files.

---

## 2026-09-10 — Updated `SPEC/_template.md` owners to PO→TL loop (still 72 lines)

- Owner line: `@planner` → `product-owner` (drafts SPEC, owns DoR + Status);
  `@task-manager` → `tech-lead` sole writer of `SPEC/TASKS.md` mirror, GitHub
  Issues/Projects canonical.
- `## 4` AC comment: `verifiable on dev after merge` → session branch preview
  (local run `python3 -m http.server`) + post-merge `dev` SHA; `@tester` →
  `qa-tester`; added DoR hint (Ready only when ACs testable, scope ≤400-line
  slice, no missing inputs).
- `## 6` heading + comment: `@tester` → `qa-tester`; verify = session preview +
  merged `dev` SHA; added user `/approve` | `/changes` loop note (no cap, User
  is owner/merger, loop until `/approve`).
- Meta Target: `MR/PR → dev (client merges; @tester verifies)` → `PR → dev
  (User/human sole merger; qa-tester verifies on merged dev SHA →
  TEST-REPORT/T-XXX-<slug>.md)`.
- Structure kept: 7 `##` sections + `### Meta` intact, 72 lines unchanged.
- Verify: `rg 'planner|task-manager|@tester' SPEC/_template.md` = 0 hits (exit 1),
  `wc -l SPEC/_template.md` = 72, section headings grepped 1-7 + Meta OK.
- Touched ONLY `SPEC/_template.md` (+ this NOTES append); no other SPEC files.

---

## 2026-09-10 — Scaffolded minimal GitHub automation for PO→TL→Programmer loop

Pre-check: `ls .github/workflows/` was empty (only the empty dir existed); `.github/` had no templates.

Created (6 files, all untracked under `.github/`, no commit/push/merge, no `dev` branch):
- `.github/ISSUE_TEMPLATE/feature.yml` — Issue Form with Problem, user story (As/I want/so that), AC checkboxes, SPEC link, area dropdown; auto-labels `type: feature` + `status:backlog`.
- `.github/ISSUE_TEMPLATE/bug.yml` — same fields adapted for bugs (Expected/Actual + repro in Problem); auto-labels `type: bug` + `status:backlog`.
- `.github/ISSUE_TEMPLATE/config.yml` — `blank_issues_enabled: false` + contact link to `SPEC/_template.md` (GitHub-canonical tracker note).
- `.github/pull_request_template.md` — Task ID, SPEC link, Fixes #, What/Why, Changes, How tested (local run), AC map, QA request, checklist (diff<400, base `dev`, session-branch naming, conventional commits, no secrets, no `../../../`).
- `.github/workflows/ci-smoke.yml` — on PR→`dev`: no `../../../` escapes in `SPEC/`, `node --check script.js`, secrets grep (patterns + `.env/.pem/.key` filenames in diff), diff size guard (<400 lines via `origin/<base>...HEAD` numstat). Shell + `github` context only, no `gh` auth.
- `.github/workflows/branch-lint.yml` — on PR→`dev`: base must be `dev`, head must match `^session/(T|B)-[0-9]+-[a-z0-9-]+-[0-9]{8}-[a-z]+$` (e.g. `session/T-010-hero-20260910-ab`). No `gh` auth.

Conventions applied (locked, do not re-litigate): GitHub Issues canonical + `SPEC/TASKS.md` mirror, local-run preview only (`python3 -m http.server`, no Pages/Vercel), user-loop NO CAP (`/changes` until `/approve`).

Verify: `ls .github/**/*` = 6 files above; `ruby -ryaml YAML.load_file` OK ×5; `node --check script.js` pass; `grep -rF '../../../' SPEC/` = 0 hits (exit 1); branch regex accepts `session/T-010-hero-20260910-ab` + `session/B-003-cta-fix-20260910-cd`, rejects `feature/foo`; secrets grep clean; `git branch -a` = only `main` + `origin/main` (no `dev` created, no push, no merge).

---

## Appendix — Human bootstrap: create + protect `dev` (run by human, NOT agent)

Status verified 2026-09-10 (read-only, no push/merge by agent):
- `git branch -a` → only `main` + `remotes/origin/main` (no local or remote `dev`).
- `git remote -v` → `origin https://github.com/kangfarih/ai-village-portfolio.git (fetch/push)`.
- `git status --short --branch` → `## main...origin/main` + modified SPEC files + untracked `.agents/ .github/ .opencode/` (work uncommitted, nothing pushed).
- Local preview smoke → `node --check script.js` PASS (exit 0); `python3 -m http.server 8901` + `curl http://localhost:8901/index.html` → `HTTP:200 SIZE:32125`; `rg '../../../' SPEC/` → 0 hits.
- `gh` → NOT installed (`command not found`, exit 127).

Human runs these exact commands in order (agent must NOT run them):

```sh
# 1. Sync + create dev from main (from repo root)
git fetch origin
git checkout main
git pull --ff-only origin main
git checkout -b dev
git push -u origin dev

# 2. Confirm
git branch -a   # expect: * dev, main, remotes/origin/dev, remotes/origin/main

# 3. Install gh (macOS, this machine) + auth
brew install gh
gh auth login   # follow prompts: GitHub.com → HTTPS → login via browser
gh auth status  # expect: Logged in

# 4. Protect dev: PR-only + CI must pass + 1 approval (repo: kangfarih/ai-village-portfolio)
gh api -X PUT repos/kangfarih/ai-village-portfolio/branches/dev/protection \
  -H "Accept: application/vnd.github+json" \
  -f required_pull_request_reviews[required_approving_review_count]=1 \
  -F required_pull_request_reviews[dismiss_stale_reviews]=true \
  -F required_pull_request_reviews[require_code_owner_reviews]=false \
  -f required_status_checks[strict]=true \
  -f required_status_checks[checks][][context]='smoke' \
  -f required_status_checks[checks][][context]='branch-lint' \
  -F enforce_admins=true \
  -F required_linear_history=true \
  -F allow_force_pushes=false \
  -F allow_deletions=false

# 5. Verify protection
gh api repos/kangfarih/ai-village-portfolio/branches/dev/protection --jq '{required_reviews: .required_pull_request_reviews.required_approving_review_count, checks: [.required_status_checks.checks[].context], enforce_admins: .enforce_admins.enabled}'
```

Alternative (no `gh`): GitHub web → Settings → Branches → Add classic branch protection rule → Branch name pattern `dev` → check `Require a pull request before merging` (required approvals = 1, dismiss stale reviews) + `Require status checks to pass before merging` (select `smoke`, `branch-lint`, require branches up to date) + `Do not allow bypassing the above settings`.

After this, agent workflow unblocks: session branches PR → `dev`, human sole merger, qa-tester verifies merged `dev` SHA.
