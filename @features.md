## Implemented (v3.0.0)
- [x] In-game checklist tracking all 9 Relic Terminals in Dogtown.
- [x] 0-Engine proximity scanner: event-driven (no polling interval), notifies as you come within `scanner_radius` (default 50m, adjustable 25-100m). No CPU cost when away.
- [x] Native relic detection: triggers the game's own relic mappin (`SetDeviceAsDetected` + `TryShowMappin`) as the device streams in; game owns the icon. No custom mod mappin.
- [x] Instant activation detection via `TryGrantPerk` observer.
- [x] Retroactive tracking: terminals already activated before install are checked off once near them in Dogtown (reads the game's own grant state).
- [x] Smart Pause: scanner suppressed during loading screens, fast travel, and menus.
- [x] Survives saves/autosaves and vendor opens (no PlayerInvalidated teardown).
- [x] Set Pin waypoint (standalone manual map waypoint, decoupled from Core).
- [x] Teleport to any uncollected terminal (Lazy Mode); Unstuck.
- [x] Per-character save persistence.

## Planned
