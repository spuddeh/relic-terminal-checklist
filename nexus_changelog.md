# Relic Terminal Checklist — Nexus Changelogs

### 3.0.0
- New required dependency: 0-Engine (Nexus mod 27967, pure CET-only build). See the requirements section in the description. The mod will not run without it.
- The proximity scanner was rebuilt on 0-Engine. It reacts to you crossing into range instead of polling on a timer, so there is no CPU cost when you are away from any terminal, and detection is tighter up close.
- Relic terminals now use the game's own relic marker instead of a separate mod icon, and it shows up as soon as the terminal area loads in rather than only once you are nearly on top of it.
- Terminal activation is now detected the instant you finish the personal link, instead of on the next scan.
- Terminals you activated before installing the mod now get checked off automatically once you are near them in Dogtown.
- Removed the scanner interval setting. The new system has no polling interval so it no longer applies.

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

[b][size=3]Version 3.0.0[/size][/b]
[list][*]New required dependency: 0-Engine (Nexus mod 27967, pure CET-only build). The mod will not run without it. See the requirements section in the description.
[*]The proximity scanner was rebuilt on 0-Engine. No CPU cost when you are away from any terminal, and tighter detection up close.
[*]Relic terminals now use the game's own relic marker instead of a separate mod icon, showing as soon as the terminal area loads in.
[*]Terminal activation is detected the instant you finish the personal link.
[*]Terminals you activated before installing now get checked off automatically once you are near them in Dogtown.
[*]Removed the scanner interval setting (the new system has no polling interval).
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