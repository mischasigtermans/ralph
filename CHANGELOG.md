# Changelog

## [1.1.1] - 2026-01-28
- Auto-detect roadmap.json and prompt to run in roadmap mode (defaults to yes)

## [1.1.0] - 2026-01-28
- Added Loopception: `--roadmap` flag for multi-phase project orchestration (a loop within a loop)
- Added `--pause` flag to pause between phases for review
- `/ralph` now detects scope and offers to create a roadmap for large tasks
- Roadmap stored as `.ralph/roadmap.json` for reliable jq parsing
- Default iterations changed to infinite (use `ralph 50` to limit)
- Added `ralph update` to refresh symlink after plugin updates
- Added `ralph --version` and `ralph --help`
- Refactored bash script with reusable functions

## [1.0.1] - 2026-01-27
- Installer now creates symlink instead of copying files
- Bash script reads prompt directly from plugin cache (with fallback to ~/.claude/)
- Broken symlink detection removed (no longer needed)
- Re-run installer after plugin updates to fix symlinks

## [1.0.0] - 2026-01-27
- Initial release with `/ralph` skill and autonomous loop bash script
