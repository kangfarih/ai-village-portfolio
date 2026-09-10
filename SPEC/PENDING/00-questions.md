# PENDING 00 — Alignment Questions (AWAITING ORDER)

> Status: **AWAITING ORDER — NO ANSWERS YET, do not assume.**
> Nothing below is decided. Each answer unblocks the noted follow-up.

## Q1 — Stack: vanilla MVP now + Phaser-gated later, vs Phaser immediately?

- Context: current `../../` (rpg-portfolio/) is a static vanilla HTML/CSS/JS site; T-010..T-015
  are scoped as vanilla work. A Phaser migration is parked in `../IDEAS/00-ideas.md`.
- Options: (a) vanilla MVP first, Phaser only if gated milestones are met; (b) start Phaser now.
- Unblocks: engine choice for all T-010..T-015 implementation SPECs.

## Q2 — Scope: 6 buildings only, vs +Blacksmith/Well in Phase 1?

- Context: `./03-phase1-and-vision.md` adds Blacksmith + Well buildings in Weeks 1-2;
  current map scope otherwise covers the existing buildings.
- Options: (a) keep the existing 6 buildings only for MVP; (b) include Blacksmith/Well in Phase 1.
- Unblocks: T-013 map scope and T-007/README building list.

## Q3 — Directions: L/R-flip 2-dir sprite scheme OK?

- Context: Zerie sprite plan flips left/right frames; `./03-phase1-and-vision.md` lists Idle/Walk
  (left/right via flip), Attack, Hurt, Death. T-011 animation depends on this.
- Options: (a) accept 2-dir L/R-flip; (b) require fuller directional sets.
- Unblocks: T-010 asset wiring + T-011 animation SPEC.

## Q4 — Touch: D-pad + ACTION button enough?

- Context: T-012 scopes 4-dir D-pad + ACTION on coarse pointers plus keyboard
  (WASD/arrows + Enter/E + Esc). Full joystick/gesture rewrite is parked in IDEAS.
- Options: (a) D-pad + ACTION suffices for MVP; (b) require joystick/gestures now.
- Unblocks: T-012 controls SPEC and mobile QA scope.

## Q5 — Assets: Zerie credit footer + no new binaries + URL-encode paths?

- Context: Zerie pack allows personal/commercial use, credit appreciated but not required
  (`./03-phase1-and-vision.md` Notes). T-010 includes `ATTRIBUTION.md`, URL-encoded paths, CSS fallback.
- Options: (a) confirm credit footer + no new binaries + URL-encoded paths; (b) different terms.
- Unblocks: T-010 asset SPEC (blocked until licensing/attribution is settled).

## Q6 — Git forge: GitHub vs GitLab + remote URL?

- Context: T-002 (branch bootstrap: initial commit, `master→main`, create `dev`, add remote,
  push) is blocked on the human providing the forge choice + remote URL. No remote configured.
- Options: (a) GitHub + URL; (b) GitLab + URL.
- Unblocks: T-002, then T-007 pilot execution and all MR-based work.
