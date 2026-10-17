# Contributing

Thanks for helping improve duo-rewards.

## Reporting bugs

Open a [bug report](https://github.com/DuoTheDev/duo-rewards/issues/new?template=bug_report.yml) with your versions, steps to reproduce and the `[duo-rewards]` console output. Strip credentials and webhook URLs from logs before posting.

## Pull requests

1. Fork and branch from `main`.
2. Keep changes focused. Config additions need a comment in `config.lua` and a row in the README tables.
3. Run the same checks CI runs before pushing:
   ```bash
   luacheck . --config .luacheckrc
   node --check nui/js/app.js
   ```
4. Add a line to `CHANGELOG.md` under an `## [Unreleased]` heading.
5. Never commit real API keys, tokens or webhook URLs. CI fails if it finds any.

## Style

* Lua: 4-space indent, single quotes, `local` everything that is not deliberately shared between files (shared globals are listed in `.luacheckrc`).
* Database access goes through oxmysql with parameterised queries only.
* Anything rendered into the NUI from user-controlled data must go through `escapeHtml`.

## Releasing (maintainers)

1. Bump `version` in `fxmanifest.lua` and move the `Unreleased` section in `CHANGELOG.md` to the new version with today's date.
2. Commit, then tag and push:
   ```bash
   git tag v1.2.0
   git push origin main --tags
   ```
3. The **Release** workflow builds `duo-rewards.zip` and publishes the GitHub release with the changelog section as notes.
