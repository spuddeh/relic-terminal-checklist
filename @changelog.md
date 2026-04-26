### [2026-04-26] v2.1.0 — 0-Engine Integration

- **[Refactor] Replaced Cron-based polling with 0-Engine reactive primitives.**
  - `Engine.RegisterSpatialSet` (`scanner_radius`, default 100m) handles "approaching terminal" notifications + mod mappin lifecycle.
  - Removed `Cron.lua`, removed `_cronTimerId`, removed `ProximityScan` loop, removed `_lastScanTime`, removed `_observersInitialized` gate.
- **[New] Reactive activation detection via `ObserveAfter("PerkTrainingControllerPS", "TryGrantPerk", ...)`.** Fires the instant the player completes the personal-link interaction. Replaces the `IsPerkGranted()` polling loop entirely.
- **[New] Native-mappin handoff via `ObserveAfter("PerkTraining", "OnAreaEnter", ...)`.** Observes the game's per-terminal trigger volume (sizes vary 5-25m, were inconsistent under a fixed snap radius); when crossed, flips `_detectedCache[id] = true` and removes the mod mappin so the game's native relic icon takes over without duplicates.
- **[New] `canMappin` config gate (Core API).** Narrower than the existing `canShow` (which blocks both mappin and notification): `canMappin` blocks only mappin creation. RTC uses it to suppress duplicate mod mappins on subsequent SpatialSet boundary crosses after a terminal has been detected, while still firing the notification on every re-entry.
- **[New] `_detectedCache` reset in `Automation.Init`.** Lua module state persists across save reloads (only cleared by full game restart). Without the reset, loading an earlier save where a terminal hadn't been crossed yet would inherit a stale `true` from a prior session and incorrectly suppress the mod mappin.
- **[New] `CheckPerkGrants()` retroactive scan** runs on `Mod.WhenReady` and overlay open. Marks any terminals whose `IsPerkGranted` is already true at session start (covers pre-mod-install collections when player is in Dogtown).
- **[Refactor] `Automation.lua` is now a thin wrapper (~150 lines)** delegating to the shared `ChecklistCore`. Mod-specific surface: `BuildEntries`, `OnItemEnter`, `CanMappin`, `IsCollected`, `CheckPerkGrants`, `SetupObservers`, `DebugTarget`.
- **[New] DB field aliasing**: `entry.entityID` is mirrored to `entry.container_id` in `BuildEntries` so Core's `ResolveEntity` works without DB schema changes.
- **[New] `IconGlyphs.DataMatrixScan`** prefix moved from per-mod hardcoded `Utils.lua` to `init.lua` (Utils is now byte-identical across all 4 checklist mods).
- **[New] `GameUI.lua`** added (psiberx CET Kit) for fast loading-screen detection.
- **[New] Required dependency**: 0-Engine (Nexus ID 27967, pure CET-only build, v0.17.2+ — recommend v1.18.1 hotfix). CET 1.32+, Codeware 1.12+, Redscript 0.5.19+.
- **[Removed] `scanner_interval` config** — no longer applicable with SpatialSet boundary events.
- **[Dev] `DebugTarget` dev tool preserved** with observer-candidate probe + DB hash match. Bug fix: changed `match.data.label` (nil) to `match.data.name` so the analysis no longer silent-crashes mid-output.
- **[Dev] `CreateMappin` debug log** in Core: emits entry id, name, position, and handle when `_isDebug` is set. Diagnostic for "mappin not appearing" reports.

### [2026-02-22] Initial
- Repository created from workspace restructure.

---

## Historical Changelog (Pre-Restructure)

### v1.0
- Initial Upload

### v2.0.0
- Proximity Scanning System: A passive proximity scanner that runs in the background to let you know when uncollected Relic Terminals are near.
- Proximity Scanning System: Dynamic Mappins - when you get close to an uncollected terminal, a custom icon will appear on your HUD along with notification text letting you know which terminal, and where.
- Optimization: The scanner uses weak references and optimized timers so it has negligible impact on your FPS, even with scanning enabled.
- Improved Directions: Updated text descriptions and fixed some typos.
- Various UI improvements.

### v2.0.1
- Fixed scanner loop not stopping correctly when all terminals are collected.
