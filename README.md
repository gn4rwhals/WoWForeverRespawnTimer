# WoWForeverRespawnTimer

[![Tests](https://github.com/gn4rwhals/WoWForeverRespawnTimer/actions/workflows/test.yml/badge.svg)](https://github.com/gn4rwhals/WoWForeverRespawnTimer/actions/workflows/test.yml)

WoW Forever mob respawn timer add-on. Mouse over a creature, dead or alive, to see its respawn time.

The game has no respawn API, so the add-on learns: it records deaths you witness (target, mouseover, nameplates) and the gap until a new mob of the same kind appears nearby. Estimates are kept per spawn area (by where you stood at the kill), falling back to all samples for that mob type. Every number is an estimate and runs slightly high, since it measures until you noticed the respawn.

Tooltip examples:

- `Died 1m 12s ago, respawn in ~3m 48s` (corpse you saw die)
- `Typical respawn ~2m 30s (3 samples here)` (live mob)
- `Respawn: no data yet`

## Install

Download `WoWForeverRespawnTimer-<version>.zip` from [Releases](https://github.com/gn4rwhals/WoWForeverRespawnTimer/releases) and unpack it into `World of Warcraft\_forever_\Interface\AddOns\`. Do not use the "Source code" zip: it holds the whole repo, not the add-on folder.

From the repo instead: copy or link the `WoWForeverRespawnTimer` folder into `World of Warcraft\_forever_\Interface\AddOns\`. For development, a junction keeps the game in sync with the repo:

```powershell
New-Item -ItemType Junction -Path "C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\WoWForeverRespawnTimer" -Target "C:\Repos\WoWForeverRespawnTimer\WoWForeverRespawnTimer"
```

## Commands

| Command | Effect |
|---|---|
| `/rst status` | Estimate and samples for your target's mob type |
| `/rst set <seconds>` | Manual respawn time for your target's mob type |
| `/rst clear` | Delete learned data for your target's mob type |
| `/rst debug` | Toggle debug log (chat + SavedVariables) |
| `/rst note <text>` | Add a timestamped note to the log (always logged) |
| `/rst log` | Show log size and last 5 lines |

## Limits

- Combat log is blocked on Forever and GUIDs are obfuscated, so nothing is read from the server; only what you see.
- Learns only from deaths you see and respawns you notice nearby. Layering and dynamic respawn rates add noise.
- Death records last one session; learned estimates persist in `RespawnTimerDB`.
- Inside instances unit data is secret, so the add-on shows nothing there.

## Reporting bugs and ideas

Found a bug, a wrong respawn time, or have a feature idea? [Open an issue](https://github.com/gn4rwhals/WoWForeverRespawnTimer/issues/new). Pull requests are not accepted, so issues are the way to suggest changes.

For bugs, please include:

- Add-on version (from the add-on list or `## Version` in `WoWForeverRespawnTimer.toc`)
- What you did, what you expected, and what happened instead
- Zone and mob name, if it is about a specific creature
- Any Lua error text (turn on error popups with `/console scriptErrors 1`)
- Output of `/rst status` while targeting the mob, if relevant
- Optional: your debug log. Turn it on with `/rst debug`, reproduce the problem, `/reload`, then attach the `log` section from `WTF\Account\<ACCOUNT>\SavedVariables\WoWForeverRespawnTimer.lua`

## Development

- `WoWForeverRespawnTimer/Util.lua`, `Estimator.lua`: pure logic, unit tested.
- `WoWForeverRespawnTimer/Tracker.lua`, `Tooltip.lua`, `Core.lua`: WoW API glue.
- Tests: [busted](https://lunarmodules.github.io/busted/) on Lua 5.1, run from repo root: `busted spec`.
- Release: bump `## Version:` in the `.toc` on main, then push a matching tag (`git tag v0.2.0 && git push origin v0.2.0`). The Release workflow runs the tests, checks the tag against the TOC and publishes the zip.
- Editor: VS Code with the "WoW API" extension (Ketho) for autocomplete.

## Testing

- Unit tests: `busted spec`.
- In game: [docs/testing/in-game-test-plan.md](docs/testing/in-game-test-plan.md). Session results go in `docs/testing/results/`.
