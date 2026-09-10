# PR — session → dev

## Task ID
<!-- e.g. T-010 (one task per PR) -->
T-XXX

## SPEC link
<!-- repo-relative, e.g. SPEC/T-010-hero.md -->
SPEC/T-XXX-<slug>.md

## Fixes
<!-- e.g. Fixes #12 -->
Fixes #

## What / Why
<!-- What changed, why it was needed (1-3 lines). -->
-

## Changes
<!-- File list / key diffs. -->
-

## How tested (local run)
<!-- Commands + result, e.g. python3 -m http.server, node --check script.js, viewport(s). -->
- [ ] `python3 -m http.server` — preview OK, no console errors
- [ ] `node --check script.js` — pass
- Notes:

## AC map
<!-- Map each SPEC AC to evidence (screenshot/section/SHA). -->
- [ ] AC1: ...
- [ ] AC2: ...

## QA request
<!-- Ask tech-lead for pre-PR QA; qa-tester verifies post-merge on dev SHA → TEST-REPORT/. -->
- [ ] Tech-lead pre-PR QA requested
- [ ] Post-merge qa-tester QA expected on `dev` SHA → `TEST-REPORT/T-XXX-<slug>.md`

## Checklist
- [ ] Diff < 400 lines (one task / one branch)
- [ ] Base is `dev`, head is `session/(T-|B-)-<id>-<slug>-YYYYMMDD-<init>`
- [ ] Conventional commit(s) (`feat/fix(scope): T-XXX ...`)
- [ ] No secrets committed (no keys/tokens/private keys/`.env`)
- [ ] No `../../../` escapes in SPEC paths (repo-relative `SPEC/...` only)
- [ ] Local-run preview done (no Pages/Vercel)
