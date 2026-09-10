# triage-fix notes

## Root cause (failing run for issue #10)
- `Apply triage labels` step ran `gh issue edit` with NO `GH_TOKEN` in its `env:` block, so `gh` exited code 4 ("set the GH_TOKEN environment variable").
- `Post triage comment` step set `GH_TOKEN: ${{ secrets.GH_TOKEN }}` (custom repo secret of unknown value) instead of the built-in token.
- Trigger was flipped to `types: [opened]` (commit 6f2caae), so the workflow fired on open rather than once on the `ai-triage` label.

## What changed (`.github/workflows/agent-triage.yml` only)
1. `on: issues: types:` → `[labeled]` (reverted `[opened]`).
2. `Apply triage labels` step: added `GH_TOKEN: ${{ github.token }}` to `env:` (kept ISSUE_NUMBER/ISSUE_TITLE).
3. `Post triage comment` step: `GH_TOKEN: ${{ secrets.GH_TOKEN }}` → `GH_TOKEN: ${{ github.token }}`.
4. No PR/push/merge steps added. Permissions unchanged (`issues: write`).

## Verification
- `python3 -c "import yaml..."`: FAILED — no `yaml` module installed (ModuleNotFoundError). Fallback used.
- `ruby -ryaml -e "YAML.load_file(...)"`: `YAML OK`.
- `git diff --stat`: 1 file changed, 3 insertions(+), 2 deletions(-); hunks match the three required edits exactly (see commit diff).

## Commit / push
- Commit: `17b27ad` — "fix(triage): GH_TOKEN=github.token on both gh steps; trigger [labeled]"
- Push: `git push origin dev` → OK (`6f2caae..17b27ad  dev -> dev`). Dev only; no merge to main.

## Cleanup
- The custom `GH_TOKEN` repo secret is now unused and can be deleted.

## Self-healing labels fix (missing labels on GitHub)
- Root cause: `Apply triage labels` step failed with `'priority/important-soon' not found` because those three labels were never created on GitHub. Repo convention lives in `.github/labels.yml`, which is manual-only (no label-sync Action), and `labels.yml` does not even list `priority/important-soon`, `kind/task`, or `triage/accepted`. Auth was fine — no `GH_TOKEN` lines changed.
- Fix (`.github/workflows/agent-triage.yml` only, `Apply triage labels` step): inserted three idempotent self-healing creates BEFORE the existing `gh issue edit` line (echo + edit lines unchanged, order: echo → 3x create → edit; `GH_TOKEN: ${{ github.token }}`, trigger `types: [labeled]`, permissions unchanged; no PR/push/merge steps):
  - `gh label create "priority/important-soon" --color "0E8A16" --description "Triage priority: needs staffing soon" 2>/dev/null || true`
  - `gh label create "kind/task" --color "1D76DB" --description "Task or decision item" 2>/dev/null || true`
  - `gh label create "triage/accepted" --color "0E8A16" --description "Triage accepted, ready for work" 2>/dev/null || true`
- Verification: `ruby -ryaml -e "YAML.load_file(...)"` → `YAML OK`; `git diff` shows exactly 3 added lines in the `Apply triage labels` run block, nothing else touched.
