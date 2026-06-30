### [2026-05-19] v3.0.0 — 0-Engine migration + native relic detection

> Consolidated. Supersedes the unreleased internal v2.1.0 work (canMappin / OnAreaEnter
> handoff / `_detectedCache`), which was an intermediate design replaced by native
> detection before release. RTC was never published above v2.0.1.

- **[Major] Proximity backend migrated from Cron polling to 0-Engine reactive primitives** (SpatialSet + per-entry detection zones). Removed `Cron.lua`, the `ProximityScan` loop, and the `scanner_interval` config. `init.lua` rewritten: `GetMod` inside `onInit`, `Mod.WhenReady` priority 2, `GameSession.OnEnd` for `isSessionActive` gating. `Automation.lua` is a thin wrapper over the shared `ChecklistCore` (byte-identical across all 4 mods).
- **[New] Required dependency**: 0-Engine (Nexus 27967, pure CET-only build, 0.18.6+). 0-Engine itself requires CET 1.32+, Codeware 1.12+, redscript 0.5.19+.
- **[Change] RTC draws no custom proximity mappin.** When the `PerkTraining` device streams in, `Core.onZoneTick` triggers the game's own native relic detection (`PerkTrainingControllerPS:SetDeviceAsDetected` + `PerkTraining:TryShowMappin`); the game owns the icon and its teardown-on-grant. The native marker appears as soon as the device streams in (earlier than vanilla's small per-terminal trigger volume). No `canMappin` / `_detectedCache` / `OnAreaEnter` observer (all part of the abandoned intermediate design).
- **[New] Instant activation** via `ObserveAfter("PerkTrainingControllerPS", "TryGrantPerk")`. `CheckPerkGrants` retroactive scan on `Mod.WhenReady` + overlay open marks terminals already `IsPerkGranted` (covers pre-install collections once the device streams in / player is in Dogtown).
- **[Change] No `PlayerInvalidated` teardown subscriber.** 0-Engine's `SpatialHash.Reset()`/`Proximity.Reset()` do not unregister sets/zones; calling `UnregisterItemSet()` there converts a transient false-invalidation into permanent breakage. Registrations persist; 0-Engine auto-resumes polling on Lifecycle recovery. (Wiki: `learnings/0-engine-playerinvalidated-no-teardown`.)
- **[Change] "Set Pin" decoupled** into a standalone `init.lua` manual waypoint (`DefaultStaticMappin` + `CustomPositionVariant`), independent of Core. Net user-facing behaviour unchanged vs 2.0.1; restructured so 0-Engine churn cannot desync it. (Wiki: `decisions/user-pin-decoupled-from-core`.)
- **[New] DB aliasing**: `entry.entityID` mirrored to `entry.container_id` so Core's `ResolveEntity` works unchanged.
- **[New] `GameUI.lua`** (psiberx CET Kit) added for fast loading-screen detection.
- **[Dev] `DebugTarget`** tool preserved (`match.data.name` fix retained); `CreateMappin` debug log under `_isDebug`.

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
