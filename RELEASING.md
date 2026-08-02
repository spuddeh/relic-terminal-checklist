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

1. **API key — a real secret.** Create a Nexus personal API key at
   <https://www.nexusmods.com/settings/api-keys> and add it as the repository secret
   **`NEXUSMODS_API_KEY`** (Settings > Secrets and variables > Actions > **Secrets**).

2. **File id — a repository VARIABLE, not a secret, and not in this repo.**

   | Artifact | Variable |
   | --- | --- |
   | `rtc` | **`NEXUS_FILE_ID_RTC`** |

   Set them under Settings > Secrets and variables > Actions > **Variables**.

   > **The first Nexus upload must be done BY HAND.** A `file_id` does not exist until a file has
   > been uploaded to the mod page once — so this pipeline can publish a mod's **updates**, never its
   > **first** file. That is also why the id is not committed: before the first upload there is nothing
   > to commit but a lie. Until the variable is set, the workflow hard-fails rather than uploading into
   > the void.
   >
   > **Where to get it:** the mod page's **Files** tab > **API Info** (or the Manage Files edit menu),
   > where Nexus still labels it **"Group ID"**. It is only visible to you, as the mod's author.
   >
   > **Do NOT take it from the public v1 API.** That endpoint has a field also called `file_id`, it is a
   > **different id space**, and the wrong value looks entirely plausible — it fails only at release time.
   >
   > **Why a variable and not a secret:** it is an identifier, not a credential. It authorizes nothing
   > without `NEXUSMODS_API_KEY`, and anyone holding that key could enumerate the ids anyway. Masking it
   > as a secret would buy no safety and would render it `***` in the logs — making a wrong id, the one
   > mistake that is actually easy to make here, much harder to diagnose.

## Cutting a new release

1. Make and commit your changes; bump the version in the mod (and `@changelog.md` / Nexus files).
2. Create a GitHub Release whose **tag** follows `<artifact>-v<version>`:
   ```pwsh
   gh release create rtc-v3.0.0 --title "Relic Terminal Checklist v3.0.0" --notes "..."
   ```
   The release body feeds two Nexus fields, split by a `<!-- nexus-description-end -->` marker on its own line. Everything **before** the marker becomes the **file description** (capped at 255 chars — for example a new requirement, or "delete the old folder first"); everything **after** it is appended to the mod page's **changelog**. With no marker at all, the whole body becomes the changelog and no file description is sent.
3. On publish, the workflow:
   - parses the tag -> looks up the artifact in the manifest,
   - stages `contentDir` -> `installDir` and zips it as `<fileBaseName>_v<version>.zip` (e.g. `relic_terminal_checklist_v3.0.0.zip`),
   - attaches the zip to the GitHub Release,
   - uploads to Nexus (`category`, `display_name`, `archive_existing_version: true`, etc.).
4. **On the Nexus mod page:** the workflow sets the **Mod Version** field and appends the
   **changelog** entry itself. Only the mod **description** is still manual.
   The changelog endpoint APPENDS rather than replaces, so publishing the same release twice
   leaves the entry on the page twice and nothing here can remove it. A `workflow_dispatch`
   re-run never posts a changelog.

You can also run it manually from the **Actions** tab (workflow_dispatch) with `artifact` +
`version` inputs (and an optional existing `tag` to attach the zip to).

## Notes

- The Nexus upload uses [`Nexus-Mods/upload-action`](https://github.com/Nexus-Mods/upload-action),
  pinned to `v1.0.0-beta.10` (the Nexus v3 upload API). The `createModFileVersion` endpoint it
  uses replaces the old `createUpdateGroupVersion`, which Nexus **removes on 2026-09-09** — so a
  pin older than beta.8 stops uploading after that date. beta.9 added `update_mod_version`, beta.10
  the changelog endpoint; both are wired up here. The API is still labelled evaluation-only, so bump
  the pin when a stable release appears (watch for further input renames).
- `archive_existing_version: true` archives the previous file when a new version is uploaded.
- `show_requirements_pop_up: true` shows the requirements popup on download (this mod requires CET
  and 0-Engine).
