# CUSTOMIZATIONS — vidasrimkus/LoopFollow

Every difference between this fork and upstream **loopandlearn/LoopFollow v7.1.0** (`4a74b78`).
Read this first before any upstream update (procedure in `CLAUDE.md`).

## 1. Trio Dosing Mode display

**Purpose.** Show which dosing mode Trio is in (Closed Loop / Open Loop / Low Glucose Suspend /
Basal Testing), read from Nightscout devicestatus `openaps.dosingMode` (Trio v1.0.1+).

**Commits.** `83635d4` (display + command), `02b1815` (keep the last Trio reading, 15-min staleness),
`f33ea39` (string-literal fix), `5b7e02a` (future timestamps, unrecognized modes, 30 s refresh).

**Files.**

| File | Change |
|---|---|
| `LoopFollow/Remote/TRC/TrioDosingMode.swift` | New. Enum with Trio's rawValues and names; `Reading` (raw + time); `merge` (only a record with a non-empty `openaps.dosingMode` replaces the reading); `status` (`none` / `current` / `unrecognized` / `stale` / `future`); `infoText`, `confirmationNote`, `sameModeNote`, `isRowEnabled`; devicestatus time from `mills` or `created_at`. |
| `LoopFollow/Storage/Observable.swift` | `dosingMode: ObservableValue<TrioDosingMode.Reading?>`. |
| `LoopFollow/Controllers/Nightscout/DeviceStatusOpenAPS.swift` | Merges the reading before the suggested/enacted early return. |
| `LoopFollow/Controllers/Nightscout/DeviceStatus.swift` | Info row set from the remembered reading after both branches; `.dosingMode` in the per-cycle clear list. |
| `LoopFollow/InfoTable/InfoType.swift` | `case dosingMode` appended **last** (rawValue = storage index; existing rows keep theirs), name "Mode", visible by default. |

**Rules.**
- Only Trio records change the mode: devicestatus without `openaps.dosingMode` (Loop, a second uploader, blank) neither changes nor clears it.
- Older than 15 min (exactly 15:00 is still fresh) or undated → "Unknown (N min)" / "Unknown".
- More than 2 min in the future → "Unknown (laikas ateityje)"; up to 2 min ahead is ordinary clock skew and stays fresh. A negative age is never shown as "0 min".
- A fresh but unrecognized value is shown as is.
- Info row "Mode": Closed Loop / Open Loop / LGS / Basal Test, "—" when no Trio record has been seen.

## 2. Remote command `set_dosing_mode`

**Purpose.** Change Trio's dosing mode from LoopFollow through Trio Remote Control.

**Commits.** `83635d4`, `5b7e02a`, `57b4608` (every row enabled, same-mode confirmation).

**Files.**

| File | Change |
|---|---|
| `LoopFollow/Remote/TRC/TRCCommandType.swift` | `case setDosingMode = "set_dosing_mode"`, display name "Dosing Mode". |
| `LoopFollow/Remote/TRC/PushMessage.swift` | `CommandPayload.dosingMode: String?` with CodingKey `"dosing_mode"` (nil is not encoded, so no other command carries it); `EncryptedPushMessage.alertText`: "Remote Command: Dosing Mode → <mode>" for this command, every other command keeps its text. |
| `LoopFollow/Remote/TRC/PushNotificationManager.swift` | `sendDosingModePushNotification(mode:)` through the existing `sendEncryptedCommand` (same encryption, JWT, APNS request, return notification); one extra `dosingMode:` argument where `EncryptedPushMessage` is built. |
| `LoopFollow/Remote/TRC/DosingModeView.swift` | New. Current mode + time/age of the last Trio devicestatus; four rows, ✓ on the current one, all enabled (only an in-flight send disables them); confirmation before every send ("Perjungti X → Y?"), plus the unknown/unrecognized note, the same-mode line "Pagal duomenis (prieš N min) Trio jau šiame režime. Siųsti vis tiek?", and for Closed Loop "Trio vėl pats duos insulino (korekcijos, SMB)"; re-rendered every 30 s (`TimelineView`, paused off screen). |
| `LoopFollow/Remote/TRC/TrioRemoteControlView.swift` | "Dosing Mode" button; glows while Trio is known (fresh data) to be in a non-closed mode. |

**Tests.** `Tests/TrioDosingModeTests.swift` (Swift Testing): rawValues match Trio; encoding for all four
modes; other commands omit `dosing_mode`; alert text; devicestatus parsing (each value, no field,
unknown value, records without the mode keep the reading); 15-min staleness; ±2-min future rule;
confirmation notes; current-mode row enabled with the same-mode line; Info row index.

**Known open review note (accepted, not fixed).** The confirmation text is recomputed on each 30 s
re-render; if the alert stays open across a boundary its extra line could change while shown. Sending
still happens only on Confirm, and Trio decides the real current mode itself.

## 2a. Basal profiles → `set_basal_schedule` (branch `feat/basal-profiles`)

**Purpose.** Keep named basal schedules on this phone and activate one on Trio remotely (Trio side:
vidasrimkus/Trio CUSTOMIZATIONS.md §7, Dana only).

**Files.**

| File | Change |
|---|---|
| `LoopFollow/Remote/TRC/BasalProfiles/BasalProfile.swift` | New. `BasalProfile` (id, name, 24 hourly rates, created/updated); `BasalProfileMath`: merge into segments, Nightscout → 24 hours (refuses off-hour schedules), hash identical to Trio's (48 half-hour values, independent of how the schedule is split — Trio CUSTOMIZATIONS.md §7), daily total, % change, the same validation as Trio (name, > 0, whole hundredths, Dana `Decimal → Double(truncating:) → UInt16(*100)` check with the nearest exact rates). |
| `LoopFollow/Remote/TRC/BasalProfiles/BasalProfilesView.swift` | New. List (U/d, ✓ when the profile's hash equals the hash of Nightscout's active schedule), Edit / Copy / Delete (not the active one), "Išsaugoti dabartinį kaip…", JSON export/import (file exporter/importer); editor (24 rows, 0.01 U/h); activation (hour \| now \| new \| Δ table, total A → B (±N %), confirmation text and expected hash fixed when the dialog opens, extra warning above 20 %, stale-data warning (> 15 min or none), "Ankstesnis (YYYY-MM-DD HH:MM)" saved before every new activation (the confirmed "Aktyvuoti") unless a saved profile already has the active schedule's hash — not on "Kartoti", which re-sends the identical, already-confirmed command: the schedule it replaces was saved by the activation it repeats, and if Trio's active schedule changed meanwhile Trio refuses it on the expected hash). |
| `LoopFollow/Remote/TRC/TRCCommandType.swift`, `PushMessage.swift`, `PushNotificationManager.swift` | `setBasalSchedule`; `basal_schedule`, `basal_schedule_name`, `expected_active_hash` (nil not encoded); send through the existing `sendEncryptedCommand`. |
| `LoopFollow/Remote/TRC/TrioRemoteControlView.swift` | "Basal Profiles" button (Trio Remote Control only). All six TRC buttons open their screen through `@State selection` and hidden links outside the `LazyVGrid` (`fix/basal-editor-dismiss`): links inside the lazy grid lost their pushed screen when a devicestatus redrew the grid (dosingMode / device publish on every record), closing an open editor or confirmation. `CommandButtonView` is kept for Loop APNS; its look is `CommandTile`. |
| `LoopFollow/Remote/TRC/DosingModeView.swift` | (`fix/basal-editor-dismiss`) confirmation text fixed at the tap, not recomputed by the 30 s timeline or devicestatus. |
| `LoopFollow/Storage/Storage.swift`, `Observable.swift`, `Controllers/Nightscout/Profile.swift` | `basalProfiles` and `activeBasalProfileID` storage; `nsProfileLoadedAt` set when the Nightscout profile loads. |

**Notes.** Max Basal is not shown: Trio does not publish it in the Nightscout profile — Trio enforces it.
LoopFollow does not parse Trio's reply, so "Kartoti" is always offered after a send (re-sending the same
schedule with the same expected hash is safe on the Trio side). Omnipod DASH is not blocked here; Trio refuses
it. The existing QR settings export is not extended (several profiles would exceed a QR code); profiles are
exported/imported as a JSON file from the Basal Profiles screen.
The list does not observe Nightscout live: the active schedule is a snapshot taken on appear and on
"Atnaujinti". Activation and the editor open as sheets driven by `BasalProfilesUIState.shared` (activation request by
profile id + schedule snapshot and time taken at the tap; editor draft), not by the list's own `@State`
(`fix/basal-editor-dismiss-2`: a second-level push held in the pushed list's `@State` closed 2–3 s after opening, on
the devicestatus-driven redraw). The editor writes nothing until "Išsaugoti"; swipe-to-dismiss is off. The
"dabar (HH:MM)" column and on-screen warning use the snapshot.
Active marker (`fix/basal-active-marker`, `BasalActiveMarker`): `Storage.activeBasalProfileID` is set on a successful
activation send and by "Išsaugoti dabartinį kaip…", never by "Kopijuoti". ✓ only on that profile and only while its
hash equals Nightscout's; other profiles with the same hash show a grey "sutampa su aktyviu" and can be deleted; only
the active id cannot. When no saved profile matches Nightscout, "Dabar Trio'je" says so (orange). Without a stored (existing) id — e.g. right after the update — the oldest profile matching Nightscout is taken.
The activation screen shows the hashes (Nightscout, this profile, expected on send) for diagnostics.
"Dabar Trio'je" (`feat/current-basal-view`, top of the screen): Trio's active schedule from Nightscout
store.default.basal as merged segments (time → U/h) and U/d, drawn from `BasalProfileMath.nightscoutSlots` — the same
48 half-hour values `hash(ofNightscout:)` is computed from, not a separate parse; "Gauta iš NS" time, "Unknown" when
> 15 min or never loaded; the matching saved profile's name (active one first) or "Neatitinka nė vieno išsaugoto
profilio"; "Atnaujinti", "Išsaugoti kaip profilį…". Tap opens a read-only sheet (24 hourly rows, 48 when the schedule
has half-hour changes); nothing is sent from it. The section also refreshes when a Nightscout profile load finishes.
Row: tap on the name opens the editor; "Aktyvuoti" button and a "…" menu (Kopijuoti, Trinti — disabled for the
active id) in the row; swipe actions (Redaguoti, Kopijuoti, Trinti) stay. "Aktyvuoti" reads the
active schedule once more: the confirmation text (warns if it changed since HH:MM), the expected hash and the
"Ankstesnis" backup come from that read.
Manual check (no UI tests): open the editor and, separately, an activation screen, leave each open ≥ 6 min while
Nightscout updates arrive — both stay open, entered values stay.

**Tests.** `Tests/BasalProfileTests.swift`: Trio hash vectors V1–V5 (Nightscout form, sent segments, hourly;
split-independence incl. [02:00 0.55, 03:00 0.55] == [02:00 0.55] and 30-minute segments), merge,
Nightscout → 24 h, the Trio validation examples (0.29, 1.15, 2.05, 2.30 refused; 0.57 and everyday rates pass),
totals, JSON, whole APNS body < 4 KB with 24 segments and a 30-character name, storage round trip; ids kept by the
Storage encoding and by `BasalProfileList.upsert` (other profiles unchanged); active marker (copy gets no ✓, copy
deletable, active id switches after activation, hash mismatch removes ✓, initial choice = oldest match); "Dabar
Trio'je" shows the hash input (hash of displayed slots == Trio vectors V1–V6, rows/segments/total, 48 rows for V4,
Unknown after 15 min, matching profile).

## 3. Fork CI

**Commits.** `d625e17`, `5038282`, `b3b4adf`.

`.github/workflows/unit_tests_fork.yml` (new; upstream has no unit-test workflow): runs the `Tests`
target of the shared `LoopFollow` scheme on an iPhone 17 / iOS 26.2 simulator, unsigned, on
`workflow_dispatch` or a push to `feat/**`. SwiftFormat: the existing `lint.yml` via
`gh workflow run lint.yml -R vidasrimkus/LoopFollow --ref <branch>`.

## 4. Interfaces (other systems depend on these)

| Direction | Contract |
|---|---|
| LoopFollow → Trio | `vidasrimkus/Trio` accepts `command_type: "set_dosing_mode"` with `dosing_mode` = `closed`, `open`, `lowGlucoseSuspend`, `basalTesting` — must match Trio's `DosingMode` rawValue exactly. |
| Trio → LoopFollow | The result arrives only as Trio's return push notification ("Dosing mode: X → Y" / "Already in Y"). LoopFollow shows it as a notification and **deliberately does not parse it**. |
| Nightscout → LoopFollow | devicestatus `openaps.dosingMode` (same field t1d-monitor reads). |
| LoopFollow → Trio (branch `feat/basal-profiles`, not on main yet) | `command_type: "set_basal_schedule"` with `basal_schedule` = `[{"start":"HH:00","rate":<U/h>}]` (adjacent equal hours merged), `basal_schedule_name`, `expected_active_hash` = hash of Nightscout `store.default.basal` (48 half-hour values, independent of how the schedule is split; Trio CUSTOMIZATIONS.md §7 algorithm and vectors V1–V5, tested on both sides). Sending the schedule that is already active gets "Already active" from Trio, however either side splits it. Trio accepts it only with a Dana; its result arrives only as the push notification. |
| Nightscout → LoopFollow (basal) | Profile `store.default.basal` (`ProfileManager.basalSchedule`) = Trio's active schedule; used for ✓, comparison, "Ankstesnis" and the expected hash. |

If any of these contracts changes, `vidasrimkus/Trio` and `t1d-monitor` must change too.

## 5. Browser Build (GitHub Actions → TestFlight)

- Repository variables: `SCHEDULED_SYNC=false`, `ENABLE_NUKE_CERTS=true`.
- Secrets: `TEAMID`, `FASTLANE_ISSUER_ID`, `FASTLANE_KEY_ID`, `FASTLANE_KEY`, `GH_PAT`, `MATCH_PASSWORD`
  (values in 1Password only; `MATCH_PASSWORD` is shared with Trio and encrypts `vidasrimkus/Match-Secrets`).
- Builds only from `main`. "4. Build LoopFollow" also runs on its schedule.
- Bundle `com.B9R54LY699.LoopFollow` (`app_suffix` empty), App Store Connect app "LoopFollow-Vidas",
  TestFlight internal group "LoopFollow-test" with automatic distribution.
- Builds so far: 7.1.0 (2) from `5b7e02a`, 7.1.0 (3) from `57b4608`.

## 6. Considered and REJECTED

**Parsing Trio's confirmation push.** Idea: read "Dosing mode: X → Y" from Trio's return notification
and show the mode immediately. Rejected: the mode exists only in human-readable, localized text (no
machine field), the push is alert-only (no `content-available`), so a backgrounded or closed LoopFollow
never receives it in code — fragile. The Trio push notification itself is the confirmation; the displayed
mode comes from devicestatus.
