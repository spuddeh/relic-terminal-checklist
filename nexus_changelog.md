# Relic Terminal Checklist — Nexus Changelogs

### 2.1.0
- New: Reactive activation detection. The mod now hooks into the game's terminal-grant event directly, so the checklist updates the instant you finish the personal-link interaction. No more waiting for the periodic scan to catch up.
- New: Game's native relic icon now takes over inside roughly 25m. The mod's marker steps out of the way at close range so you don't see two icons stacked.
- New: 0-Engine integration. The proximity scanner has been rewritten on top of 0-Engine's spatial hash and proximity zones. Zero CPU cost when far from any terminal; precise boundary callbacks when near.
- New: Required dependency on 0-Engine (Nexus ID 27967, pure CET-only build).
- Removed: scanner interval setting. No longer applicable with the new architecture.
- Major code improvements.

### 2.0.1
- Fixed scanner loop not stopping correctly when all terminals are collected.

### 2.0.0
- Proximity Scanning System: A passive proximity scanner that runs in the background to let you know when uncollected Relic Terminals are near.
- Proximity Scanning System: Dynamic Mappins - when you get close to an uncollected terminal, a custom icon will appear on your HUD along with notification text letting you know which terminal, and where.
- Optimization: The scanner uses weak references and optimized timers so it has negligible impact on your FPS, even with scanning enabled.
- Improved Directions: Updated text descriptions and fixed some typos.
- Various UI improvements.

### 1.0
- Initial Upload

---
## Notes

No issues flagged.

---
## Stickied Comment BBCode

```
[color=#ffff00][size=5][b]- Changes -[/b][/size][/color]

[b][size=3]Version 2.1.0[/size][/b]
[list][*]New: Reactive activation detection. The checklist updates the instant you finish the personal-link interaction.
[*]New: Game's native relic icon now takes over inside roughly 25m. The mod's marker steps out of the way at close range so you don't see two icons stacked.
[*]New: 0-Engine integration. Zero CPU cost when far from any terminal; precise boundary callbacks when near.
[*]New: Required dependency on 0-Engine (Nexus ID 27967, pure CET-only build).
[*]Removed: scanner interval setting. No longer applicable with the new architecture.
[*]Major code improvements.
[/list]
[b][size=3]Version 2.0.1[/size][/b]
[spoiler][list][*]Fixed scanner loop not stopping correctly when all terminals are collected.
[/list][/spoiler]
[b][size=3]Version 2.0.0[/size][/b]
[spoiler][list][*]Proximity Scanning System: A passive proximity scanner that runs in the background to let you know when uncollected Relic Terminals are near.
[*]Proximity Scanning System: Dynamic Mappins - when you get close to an uncollected terminal, a custom icon will appear on your HUD along with notification text letting you know which terminal, and where.
[*]Optimization: The scanner uses weak references and optimized timers so it has negligible impact on your FPS, even with scanning enabled.
[*]Improved Directions: Updated text descriptions and fixed some typos.
[*]Various UI improvements.
[/list][/spoiler]
[b][size=3]Version 1.0[/size][/b]
[spoiler][list][*]Initial Upload
[/list][/spoiler]
```

> Character count: ~1500 / 5000