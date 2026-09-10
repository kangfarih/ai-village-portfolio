# PLAN 01 — Agent Workflow: PO → Tech-Lead → Programmer loop

> Status: **DRAFT** — pending `dev` branch creation + `gh` auth (no `dev` branch exists; only `main`/`origin/main`. `gh` CLI not installed). Do NOT treat as agreed/done until those land.
> Sources (repo-relative): `SPEC/_template.md`, `SPEC/T-007-pilot.md`, `.agents/` (canonical); `SPEC/TASKS.md` (mirror only, tech-lead sole writer); `.opencode/agents/planner-project-manager.md` SUPERSEDED.
> TODO (missing targets — NOT done): `AGENTS.md` (absent), `docs/` incl. `docs/GIT-FLOW.md` + `docs/ROLES.md` (absent), `TEST-REPORT/` (absent). No `.github/agents/` mirror (definitions live in `.agents/`).
> Note: all broken deep-relative (old triple-parent) paths from the prior revision were fixed (from `SPEC/PLAN/` the repo root is two levels up, not three). This revision uses repo-relative paths only.

## Roles (replaces old 6 flat agents)

The old flat split (`planner` / `coder` / `fixer` / `tester` / `task-manager` / `devops`) is **retired**. The loop is now:

| Agent | Role |
|---|---|
| `product-owner` | Watches GitHub Issues/Projects (canonical tracker). Writes `SPEC/T-XXX-<slug>.md` from `SPEC/_template.md`. Owns Status `Backlog → Ready → Done`. Defines DoR + ACs. Closes only on evidence. |
| `tech-lead` | Decomposes work to ≤400-line slices. Sole writer of `SPEC/TASKS.md` mirror. Cuts `session/<ID>-<slug>-YYYYMMDD-<init>` from fresh `dev`. Delegates to `programmer`. Pre-PR QA. Creates PR → `dev`. Requests local preview docs from `devops`. Relays user `/approve` \| `/changes` loop. |
| `programmer` | **Sole code writer** on `session/*`. Conventional commits `feat/fix(scope): T-XXX …`. One task per PR, diff < ~400 lines. Never merges. |
| `qa-tester` | QA only. Verifies merged `dev` SHA vs SPEC ACs, files `TEST-REPORT/T-XXX-<slug>.md` with `QA: PASS` or `QA: FAIL`. Never fixes product code. |
| `devops` | Owns `dev` branch, CI, and local-run preview docs (`python3 -m http.server`, no Pages/Vercel). Provisions local-run steps on `tech-lead` request. |
| `User` (human) | **Sole acceptor + merger (owner/manager).** Reviews local preview, replies `/approve` or `/changes` (no cap — loop until `/approve`). Only human merges PR → `dev`. |

Definitions live in `.agents/` (`product-owner.md`, `tech-lead.md`, `programmer.md`, `qa-tester.md`, `devops.md`); `.opencode/agents/planner-project-manager.md` is SUPERSEDED (left in place, do not use).

## Pipeline

```
Issue (GitHub canonical; `SPEC/TASKS.md` mirror) → PO SPEC + DoR → TL feasible → programmer build → TL QA → PR → user preview /approve|/changes (no cap, loop until /approve) → human merge to dev → qa-tester QA on dev SHA → PO close
```

1. **Issue → PO SPEC + DoR.** `product-owner` triages the GitHub Issue, writes `SPEC/T-XXX-<slug>.md` from `SPEC/_template.md`, sets Definition-of-Ready (ACs testable, scope ≤400-line slice, no missing inputs). Status → `Ready` only when DoR holds.
2. **TL feasible.** `tech-lead` confirms feasibility; if infeasible/oversized, sends back to PO with reason (no code yet).
3. **Programmer build.** `tech-lead` cuts `session/<ID>-<slug>-YYYYMMDD-<init>` from fresh `dev`, `programmer` implements on that branch only.
4. **TL QA → PR.** `tech-lead` runs pre-PR QA (ACs + conventions); on PASS creates PR → `dev` and requests local-run preview steps from `devops` (`python3 -m http.server`, no Pages/Vercel).
5. **User preview loop.** `User` reviews local preview: `/approve` → proceed to merge; `/changes` → `tech-lead` → `programmer` revises (no cap — user is owner/manager, loop until `/approve`). QA 2nd-`FAIL` → PO escalation stays separate.
6. **Human merge → qa-tester QA → PO close.** Human merges PR → `dev`. `qa-tester` verifies the merged `dev` SHA against SPEC ACs, writes `TEST-REPORT/T-XXX-<slug>.md` (`QA: PASS` or `QA: FAIL`, bug loop files `B-###` on `FAIL`; 2nd `FAIL` escalates to `product-owner`). `product-owner` moves Status → `Done` only on `qa-tester` `PASS` + merge SHA.

## Definition of Done (single ordered — retires old post-merge-only DoD)

The old "merge then test then Done" shorthand is **retired**. DoD is this ordered gate, in sequence:

1. ACs met on the session branch (per `SPEC/T-XXX-<slug>.md`).
2. `tech-lead` QA **PASS** (pre-PR).
3. `User` **approve** on local preview (`/approve`).
4. Human merge to `dev` (agents never merge).
5. `qa-tester` **PASS** on the merged `dev` SHA (`TEST-REPORT/T-XXX-<slug>.md`).
6. `product-owner` moves Status → `Done`.

Any gate failing sends the task back to its owner step; skipping a gate is not Done.

## Conventions (kept)

- Session branch: `session/<TASK-ID>-<slug>-<YYYYMMDD>-<init>` (e.g. `session/T-042-auth-refresh-20260910-a`). Bugs: `B-###`; retries: `session/T-###-fixN-...`. Always cut from fresh `dev`; never push to `dev`/`main` directly.
- Commits: `<type>(<scope>): <TASK-ID> <short>` (e.g. `feat(auth): T-042 add refresh rotation`). Bug fixes add `Root cause:` + `Fixes #<issue>`. No `WIP`. One task per PR, diffs < ~400 lines.
- Human-only merge: agents never merge their own PR. `User` is the sole merger to `dev`.
- Evidence over claims: every Status move cites branch name + PR URL + merge SHA + QA report path (`TEST-REPORT/T-XXX-<slug>.md`).
