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
- Commit: (SHA filled after commit)
- Push: `git push origin dev` (dev only; no merge to main).

## Cleanup
- The custom `GH_TOKEN` repo secret is now unused and can be deleted.
