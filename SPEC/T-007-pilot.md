# SPEC T-007 — First Pilot Task: Documentation README

> Task ID: `T-007` · Owner chain: `@planner` → `@coder` → `@tester` → `@task-manager`. Pilot loop: IDEA → SPEC → session branch → MR → merge → QA → Done.

## 1. Problem

- Context: `./TASKS.md` Backlog lists **Documentation — Update README and comments** alongside larger items (World Expansion, NPC System, Quest System, Mobile Touch Controls, etc.). The `rpg-portfolio/` folder currently has no `README.md` (`index.html`, `script.js`, `style.css`, `assets/`, `PHASE1_PLAN.md`, `PLANNING.md`, `TASKS.md` only), so new contributors and future agent sessions lack a 2-minute orientation.
- Impact if not done: onboarding stays slow, agent sessions re-discover controls/map structure each time, and the first full IDEA→SPEC→MR→QA loop never gets exercised on a safe task.

## 2. Users

- Primary: future contributors / agent sessions opening `rpg-portfolio/` for the first time.
- Secondary: `@task-manager` / `@tester` — need a trivial, zero-risk task to prove the pipeline before touching gameplay code.

## 3. User stories

- [ ] As a new contributor I want a short `rpg-portfolio/README.md` so that I can run and explore the portfolio in under 5 minutes.
- [ ] As a task-manager I want the pilot to touch zero gameplay code so that the first MR→merge→QA loop is safe and reviewable.

## 4. Acceptance criteria

- [ ] AC-1: New file `rpg-portfolio/README.md` exists on `dev` after merge (≤150 lines, markdown).
- [ ] AC-2: README documents: what it is, how to run locally (2+ options, e.g. `python3 -m http.server` / `npx serve` / open `index.html`), controls table, map/buildings overview, and where to find `./TASKS.md` + `./` (this SPEC folder).
- [ ] AC-3: README contains no dead links (all relative links resolve; all listed files exist) and no secrets.
- [ ] AC-4: Zero changes to product code — `git show --stat <merge SHA>` shows only `rpg-portfolio/README.md` (plus optionally 1-line `rpg-portfolio/TASKS.md` checkbox note; NO `index.html`/`style.css`/`script.js` changes).

## 5. Non-goals

- NG-1: No gameplay, CSS, or JS changes (Mobile Touch Controls, NPC/Quest/Inventory/Save systems explicitly out).
- NG-2: No JSDoc/comment sweep of `script.js` — README only; code comments are a follow-up.
- NG-3: No root `./TASKS.md` edits in the pilot branch (architect owns it this round); no CI/workflow changes.

## 6. Test plan (hooks for @tester)

| AC | How to verify | Command / URL | Expected |
|----|---------------|---------------|----------|
| AC-1 | File present on fresh `dev`, line count | `git checkout dev && git pull && ls rpg-portfolio/README.md && wc -l rpg-portfolio/README.md` | Exists, ≤150 lines |
| AC-2 | Read README, check 5 sections present | Open `rpg-portfolio/README.md` on `dev` | What-is + run + controls + map + TASKS/SPEC pointers all present |
| AC-3 | Link/file check | `grep -n -i -E '\[.*\]\(.*\)' rpg-portfolio/README.md`; verify each target with `ls` | Every relative target exists; no `http://localhost` hardcode as only option; no secrets (`grep -ri -E 'api[_-]?key|token|password' rpg-portfolio/README.md` empty) |
| AC-4 | Diff scope check | `git show --stat <merge SHA> --oneline` + `git diff <base>...dev --name-only` | Only `rpg-portfolio/README.md` (+ optional TASKS checkbox); `index.html`/`style.css`/`script.js` untouched |

- Smoke steps:
  1. Follow README's quickest run option; page loads with map + HUD.
  2. Press listed controls (arrows/WASD + E/Space); character moves and one building dialog opens.
- Regression guard (must NOT change):
  - `rpg-portfolio/index.html`, `rpg-portfolio/style.css`, `rpg-portfolio/script.js`

## 7. Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Scope creep into code comments / touch controls | Med | AC-4 + NG-1/NG-2 enforced by @tester diff check |
| README goes stale (controls/map drift) | Low | Keep controls + building list high-level; link `./PENDING/03-phase1-and-vision.md` as source of truth |
| T-002 remote missing blocks MR push | Med | Pilot branch + MR can be prepared locally; MR link recorded as `n/a (no remote)` until @devops unblocks T-002 |

---

### Meta

- Task ID: `T-007`
- Source backlog item: `./TASKS.md` → `Documentation - Update README and comments` (scoped to README only)
- Chosen over: `Mobile Touch Controls - Optimize for mobile devices` — rejected for pilot because it touches `script.js`/`style.css`, needs device matrix + manual mobile QA, and risks regressions; docs pilot proves the loop with zero product-code risk.
- Branch convention: `session/T-007-readme-<YYYYMMDD>-<init>`
- Target: MR/PR → `dev` (client merges; `@tester` verifies on `dev`, writes `../../TEST-REPORT/T-007-readme.md`, `@task-manager` moves T-007 to Done only on `QA: PASS`)
