# Releasing

This repo publishes the mod to **GitHub Releases** and **Nexus Mods** automatically via
[`.github/workflows/release.yml`](.github/workflows/release.yml), driven by
[`release-manifest.json`](release-manifest.json).

This is a CET-only mod, so it is packaged by zipping straight from source (no WolvenKit step). The
workflow stages the artifact's `contentDir` into its `installDir` (the in-game path) and zips that,
so `bin/...` lands at the zip root exactly as the game expects.

## Artifacts

| Artifact id | What | Nexus mod | File on Nexus |
| --- | --- | --- | --- |
| `rtc` | Relic Terminal Checklist | 25755 | main |

## One-time setup

1. **API key (secret).** Create a Nexus personal API key at
   <https://www.nexusmods.com/settings/api-keys> and add it as the repository secret
   **`NEXUSMODS_API_KEY`** (Settings > Secrets and variables > Actions).
2. **File ID (manifest).** On the mod page, open the **Files** tab > **API Info** (or the Manage
   Files edit menu) to get the file ID, then replace the `REPLACE_WITH_RTC_FILE_GROUP_ID` placeholder
   in `release-manifest.json` (the `file_id` field). Nexus still labels this value **"Group ID"** on
   the page, but it is what the upload action's `file_id` input wants. File IDs are not secret, so
   they live in the manifest.

## Cutting a new release

1. Make and commit your changes; bump the version in the mod (and `@changelog.md` / Nexus files).
2. Create a GitHub Release whose **tag** follows `<artifact>-v<version>`:
   ```pwsh
   gh release create rtc-v3.0.0 --title "Relic Terminal Checklist v3.0.0" --notes "..."
   ```
   The release body is the GitHub release notes (write the full changelog here; also paste it into the Nexus Changelogs tab manually). For the **Nexus file description** (capped at 255 chars), put a `<!-- nexus-description-end -->` marker on its own line: everything **before** it becomes the file description (for example a new requirement, or "delete the old folder first"). Omit the marker, or leave nothing before it, to send no file description.
3. On publish, the workflow:
   - parses the tag -> looks up the artifact in the manifest,
   - stages `contentDir` -> `installDir` and zips it as `<fileBaseName>_v<version>.zip` (e.g. `relic_terminal_checklist_v3.0.0.zip`),
   - attaches the zip to the GitHub Release,
   - uploads to Nexus (`category`, `display_name`, `archive_existing_version: true`, etc.).
4. **Manually on the Nexus mod page** (the API does NOT do these): bump the **Mod Version** field,
   add the changelog entry, and update the description if needed. The upload-action only sets the
   *file* version; it never touches the mod's headline version, changelog, or description.
   Recommended order: do these page edits *before* cutting the release.

You can also run it manually from the **Actions** tab (workflow_dispatch) with `artifact` +
`version` inputs (and an optional existing `tag` to attach the zip to).

## Notes

- The Nexus upload uses [`Nexus-Mods/upload-action`](https://github.com/Nexus-Mods/upload-action),
  pinned to `v1.0.0-beta.8` (the Nexus v3 upload API). beta.8's `createModFileVersion` endpoint
  replaces the old `createUpdateGroupVersion`, which Nexus **removes on 2026-09-09** — so this pin
  is required to keep uploading after that date. This API is still labelled evaluation-only, so bump
  the pin when a stable release appears (watch for further input renames).
- `archive_existing_version: true` archives the previous file when a new version is uploaded.
- `show_requirements_pop_up: true` shows the requirements popup on download (this mod requires CET
  and 0-Engine).
