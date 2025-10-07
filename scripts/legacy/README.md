Archived scripts moved here because they had no direct textual references in the repository scan.

Why archived
- These files were flagged as having NO_EXTERNAL_REFS by an automated repo scan. That can mean they are unused, deprecated, or referenced dynamically at runtime.
- Moving them to `scripts/legacy/` is a safe, non-destructive archival step. It preserves history for review and allows easy restoration with `git mv` if needed.

How to proceed
- Inspect the scripts in this folder and the oldest commit that changed them before permanent removal.
- If you want to delete them permanently, remove this folder and commit the change.
- To restore a script back to `scripts/`, run: `git mv scripts/legacy/<script> scripts/` and commit.

Date archived: 2025-10-07
