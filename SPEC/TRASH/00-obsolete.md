# TRASH 00 — Obsolete Items (ignore; audit trail only)

> Each item below is obsolete or contradicted by evidence. Do not act on these claims.

## (a) "Phase One: Asset Integration" checked done — unzip ≠ integrate

- Claim: `rpg-portfolio/TASKS.md:15` checks off "Phase One: Asset Integration" (49 files, 100x100 tiles).
- Evidence: zero Soldier/Orc references in product code outside plans/tasks/assets
  (`grep -ril "soldier|orc" rpg-portfolio/` excluding `assets/`, `PHASE1_PLAN.md`,
  `PLANNING.md`, `TASKS.md` → no hits). Files present ≠ wired into `index.html`/`script.js`/`style.css`.

## (b) Duplicate `## Done` sections

- Evidence: `rpg-portfolio/TASKS.md` has `## Done` at both line 25 and line 36
  (second section lists unchecked initial-map items). Consolidate if the file is ever revised.

## (c) Blacksmith/Well treated as existing

- Evidence: `grep -rin "blacksmith|well" rpg-portfolio/index.html rpg-portfolio/script.js
  rpg-portfolio/style.css` → no hits. They exist only in `PHASE1_PLAN.md` scope, not in product code.

## (d) QA PASS dates with 0 commits (no SHA possible)

- Evidence: `TASKS.md:31-33` claim QA PASS 2026-09-10; `rpg-portfolio/TASKS.md:27` claims
  QA PASS 2026-09-09 — but `git log` reports "no commits yet" and `git remote -v` is empty,
  so no merge SHA or MR link can exist. File-asserted only.

## (e) Stray session token `ses_f774ff36...` with no mapping

- Evidence: `rpg-portfolio/TASKS.md:15` ends with `ses_f774ff36cffeMU62hulSIVe75K`;
  only hit for `ses_` repo-wide (excluding `.git`/`node_modules`). No session/branch/MR maps to it.

## (f) T-001 mirror claim vs `architect.md` extra in `.opencode` only

- Claim: `TASKS.md:31` says 6 defs + 6 mirrors.
- Evidence: `.opencode/agents/` has 7 files (incl. `architect.md`); `.github/agents/` has 6
  (`ls .opencode/agents/ .github/agents/`). The "6 + 6 mirrors" line ignores the extra `architect.md`.
