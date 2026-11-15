# In-game test plan

Checklist for a long test session in WoW Forever. Do Part A once at the start, then the test cases in order. Results from each session go in `docs/testing/results/<date>.md`, written after the log is analyzed.

## A. Logging setup (~5 min)

1. **Load the latest code.** The add-on folder in `_forever_\Interface\AddOns\WoWForeverRespawnTimer` is a junction to this repo, so nothing needs copying. If the game is already open, type `/reload`.
2. **Turn on Lua error popups** (built into the game): type `/console scriptErrors 1`. Any add-on error now shows a popup. Optional: install BugGrabber + BugSack from CurseForge if they list Forever support.
3. **Turn on debug logging:** `/rst debug`. Chat says `debug ON (logged to SavedVariables)`. The setting is saved, so it stays on after reloads. Typing `/rst debug` again turns it off.
4. **Check that logging works:**
   1. `/rst note T0 setup check`
   2. `/rst log`. Chat shows `log: N lines (debug ON)` and the `NOTE T0 setup check` line.
   3. `/reload`
   4. Open `C:\Program Files (x86)\World of Warcraft\_forever_\WTF\Account\<ACCOUNT>\SavedVariables\WoWForeverRespawnTimer.lua` in Notepad (or ask Claude to check it). The `NOTE T0 setup check` line must be there.
5. **Start note:** `/rst note session start zone=<zone> level=<your level>`
6. **Flush rule:** `/reload` every 30-45 minutes and after any test you care about. The game only writes the file on `/reload` or logout, so a crash loses everything since the last one.

### What gets logged

With debug on, the add-on logs these automatically:

```
23:08:00 death 1562 Bloodsail Mage @0:-12345,678     mob died, your position (continent:x,y yards)
23:08:25 add 1562 Bloodsail Mage                     mob was already in combat when first seen (ignored)
23:12:10 learned 1562 Bloodsail Mage 4m 10s area#2 (3 samples)   respawn sample saved
23:20:00 NOTE T2 respawned                            your note
23:21:00 skipped 782 Skullsplitter Scout 22m 54s (away)   you left the area too long, sample dropped
23:22:00 bound 1059 Ana'thek the Cruel <= 17m 00s     first seen in combat: respawns within at most this
23:23:00 pet 756 Skullsplitter Panther (owner Skullsplitter Hunter, via type)   flagged as a pet, ignored from now on
23:24:00 class 782 Skullsplitter Scout normal         mob classification, logged once per mob type
23:25:00 quest 1059 Ana'thek the Cruel                tooltip showed a quest line, kept out of the zone average
23:26:00 TICK ERROR <message>                         the 5 second position check failed (report this)
```

The log keeps the last 3000 lines.

### Note format

Start every note with the test ID, then a keyword, so the log can be matched up afterwards:

| Note | When |
|---|---|
| `/rst note T2 start camp=A mob=<name>` | Before a test |
| `/rst note T2 killed` | Right after a kill (optional, the log has deaths) |
| `/rst note T2 respawned` | The moment you see the mob reappear |
| `/rst note T5 tooltip <what it says>` | To record a tooltip |
| `/rst note T2 status <what it says>` | To record `/rst status` output |
| `/rst note T2 done` | After a test |
| `/rst note bug <what you saw>` | Any time something looks wrong |
| `/rst note layer` | Layer swap, party invite or zone change mid-test |

**Tip:** make a macro (`/macro`, New) with the text `/rst note T2 respawned` and drag it to your action bar for one-click marking. Edit the test ID when you move to another test.

## B. Test cases

### T1 - Load, no errors (2 min)
1. `/rst note T1 start`
2. Type `/rst`. Chat lists `clear | debug | log | note | set | status`.
3. Hover over 3 live mobs and 1 corpse.
4. `/rst note T1 done`

**Pass:** no error popups. Tooltips show a blue respawn line, or nothing for live mobs with no data yet.

### T2 - Ground-truth respawn at one camp (30-45 min)
Measures how far learned samples are from reality.
1. Pick a camp with 3-6 normal mobs of the same type. This is camp A. `/rst note T2 start camp=A mob=<name>`
2. Stand where you can see the whole camp. Stay within ~20 yards of that spot for the whole test.
3. Kill ONE mob on its own (no adds). Chat shows `death <id> <name> @...`.
4. Watch the spot where it stood. The moment a new one appears, press your `T2 respawned` macro.
5. Hover over or target the new mob. Chat should show `learned ... area#1 (N samples)`.
6. Repeat steps 3-5 five times.
7. Target the mob, `/rst status`, then `/rst note T2 status <what it said>`.
8. `/rst note T2 done`, then `/reload`.

**Pass:** each `learned` time is 0-30 seconds more than the time between its death and your `respawned` note. Never less.

### T3 - Separate spawn areas (20-30 min)
1. Find camp B: the same mob type as T2, at least 100 yards from camp A. `/rst note T3 start camp=B`
2. Do T2 steps 3-5 three times at camp B.
3. Target a camp B mob, `/rst status`. It should say `2 spawn areas`. `/rst note T3 status <what it said>`
4. Hover over a live mob at camp B. The tooltip should say `(N samples here)` with camp B's time. `/rst note T3 tooltip B <text>`
5. Walk back to camp A and hover over a live mob. The tooltip should show camp A's time, also `here`. `/rst note T3 tooltip A <text>`
6. Stand between the camps, more than 50 yards from both, and hover over a mob of that type if one is around. It should say `other spots`. `/rst note T3 tooltip middle <text>`
7. `/rst note T3 done`, then `/reload`.

**Pass:** 2 areas, and each camp's tooltip shows its own time.

### T4 - Add filter (10 min)
1. `/rst note T4 start`
2. Pull 2-3 mobs at once (run into a group). Kill them all.
3. Chat should show `add <id> <name>` (or `bound ...` if one of that type died nearby earlier) for the mobs that joined the fight, and no `learned` line during it.
4. `/rst note T4 done`

**Pass:** no `learned` sample under 45 seconds anywhere in the log.

### T5 - Corpse countdown (15-20 min, after T2)
Needs 3+ samples at a camp, so do it at camp A after T2.
1. `/rst note T5 start`. Kill one mob.
2. Hover over the corpse right away. It should say `Died Xs ago, respawn in ~Y`. `/rst note T5 tooltip <text>`
3. Hover again about every minute. Move the mouse off and back on, since the tooltip does not update by itself.
4. When the mob reappears: `/rst note T5 respawned`. If the corpse is still there, hover over it: once the timer passes 0 it should say `respawn due`.
5. `/rst note T5 done`

**Pass:** the countdown reaches 0 within ~30 seconds of the real respawn.

### T6 - Corpse you did not see die (5 min, when you find one)
1. Find a corpse another player killed (busy area). `/rst note T6 start`
2. Hover over it. It should say `Respawn ~X (...)` or `Respawn: no data yet`, never `Died ... ago`.
3. `/rst note T6 tooltip <text>`, then `/rst note T6 done`.

### T7 - Manual override (3 min)
Use a mob type you do NOT need data for: `/rst clear` wipes that type's learned samples too.
1. Target a mob of that type. `/rst note T7 start`
2. `/rst set 120`. Chat confirms `respawn set to 2m 00s`.
3. Hover over a live one. The tooltip says `Typical respawn ~2m 00s (manual)`.
4. `/rst clear` while targeting it. Chat confirms `respawn data cleared`.
5. `/rst note T7 done`

### T8 - Persistence (5 min)
1. `/rst note T8 start`. Target a T2 mob, `/rst status`, and note the result.
2. `/reload`, then `/rst status` again. Same samples and area count.
3. Log out to character select and log back in. `/rst status` again. Same.
4. If a corpse from before the logout is still around, hover over it. It should NOT say `Died ... ago`. That is expected: death records only last one session.
5. `/rst note T8 done`

### T9 - Instance (15 min, any dungeon)
1. `/rst note T9 start dungeon=<name>` before going in.
2. Inside: hover over mobs, fight, hover over corpses.
3. After leaving: `/rst note T9 done <what you saw>`

**Pass:** no error popups. The tooltip line is missing or harmless (the game hides unit data in instances).

### T10 - Busy area (5 min)
1. `/rst note T10 start` in a city or crowded zone with lots of nameplates.
2. Move around for 2-3 minutes with nameplates on. Watch for stutter.
3. `/rst note T10 done fps=<ok|bad>`

### T11 - Different zone level (20 min)
1. Go to a zone with a different level range. `/rst note T11 start zone=<zone>`
2. Do T2 steps 3-5 three times on one mob type.
3. `/rst note T11 done`

**Pass:** samples are learned. Note whether the times differ from T2.

### T12 - Layer or party change (optional)
1. If you join a party or the game moves you to another layer mid-test: `/rst note layer`
2. Keep going. Samples right after a `layer` note get checked for outliers.

### T13 - Time away is not counted (15 min)
1. At a camp, kill one mob. `/rst note T13 start`
2. Walk or ride at least 150 yards away and stay away for 2 minutes or more.
3. Come back and look at the camp (hover or target the respawned mob).
4. Chat should show `skipped <id> <name> <time> (away)`, not `learned`.
5. Kill another mob, step only ~30 yards away for 10 seconds, come back and wait for the respawn. That one should be `learned`.
6. `/rst note T13 done`

**Pass:** the long trip gives `skipped`, the short step still gives `learned`.

### T14 - NPC pets (5 min, Skullsplitter camps in Stranglethorn or any hunter-type mob with a pet)
1. `/rst note T14 start`
2. Hover over the pet (for example Skullsplitter Panther). Chat should show `pet <id> <name> (owner <owner>, via type)` or `via text`, once. `/rst note T14 via <type or text>`
3. The pet's tooltip shows no respawn line, alive or dead.
4. Target the pet, `/rst status`. It says `pet, ignored`.
5. Kill the owner and the pet. The log shows `death` for the owner but no `death` or `learned` for the pet.
6. `/rst note T14 done`

**Pass:** pet flagged once, no data recorded for it afterwards.

### T15 - Upper bounds (10 min)
1. `/rst note T15 start`. Pick a mob type with no samples yet (`/rst status` shows `all samples []`).
2. Kill one, leave, come back after its respawn and pull it from range without hovering it first.
3. Chat shows `bound <id> <name> <= <time>`. Repeat once more on the same type.
4. Hover a live one: `Typical respawn at most X (upper bound, 2 kills)`. `/rst note T15 tooltip <text>`
5. Kill one and hover the corpse: `respawns within at most ...`, never a `~` countdown.
6. `/rst note T15 done`

### T16 - Classification and quest flags (10 min)
1. `/rst note T16 start`
2. Hover 3 normal mobs, 1 elite and 1 rare if you can find one. Chat shows one `class <id> <name> <value>` line per type. `/rst note T16 classes <what you saw>`
3. With a kill quest active, hover a quest mob. Chat shows `quest <id> <name>` once.
4. Hover a totem (Healing Ward) and a critter if around, and note their class: `/rst note T16 totem <value>`
5. `/rst note T16 done`

### T17 - Zone average (after a few sessions of normal mobs in one zone)
1. `/rst note T17 start zone=<zone>`
2. Target a normal mob type you have never timed in this zone. `/rst status` shows class, zone and the zone pool size.
3. If the pool has 3+ samples, hover a live one: `Typical respawn ~X (zone avg, N samples)`. `/rst note T17 tooltip <text>`
4. Hover a rare or a quest mob you have never timed: no zone avg line.
5. Go into a cave or mine in the same zone and type `/dump C_Map.GetBestMapForUnit("player")`. `/rst note T17 cave map=<number>`. `/rst status` there should show the same zone as outside.
6. `/rst note T17 done`

**Pass:** zone avg only on normal, non-quest mobs without their own data; same zone id inside caves.

## C. End of session
1. `/rst note session end`
2. `/reload` or log out.
3. Tell Claude "session done". Optional: screenshots of odd tooltips are in `_forever_\Screenshots`.

## D. Analysis (after the session)
- Read `log` and `npcs` from SavedVariables.
- T2, T5, T11: pair each `respawned` note with its `learned` line and compute the error per sample (expected: 0-30 seconds, never negative).
- T3: area count and per-camp times against the tooltip notes.
- T4: any `learned` sample under 45 seconds or during combat.
- Every `bug` note and error popup, with a proposed fix.
- Tune `MIN_SAMPLE`, `MATCH_RADIUS` and `AREA_RADIUS` in `WoWForeverRespawnTimer/Estimator.lua` if the data calls for it.
- Write it up in `docs/testing/results/<date>.md`.
