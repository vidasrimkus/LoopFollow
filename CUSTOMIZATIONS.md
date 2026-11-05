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
Time-zone wording (`feat/cr-isf-profiles`, text only, no behaviour change): "Laikas (Trio telefono laikas)" headers,
"Laikai — Trio telefono laikas, ne šio telefono." footers, and "dabar (nuskaityta HH:MM)" (this phone's read time).
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

## 2b. CR and ISF profiles → `set_carb_ratios` / `set_isf` (branch `feat/cr-isf-profiles`)

**Purpose.** Keep named carb-ratio and ISF schedules on this phone (two separate lists, two screens) and activate one
on Trio remotely. Contract agreed with vidasrimkus/Trio ("cr-isf"): 30-minute grid, ISF sent always as integer
mg/dL, nothing written to the pump (no pump restriction). Basal code is untouched; everything is parallel.

**Files.**

| File | Change |
|---|---|
| `LoopFollow/Remote/TRC/TherapyProfiles/TherapyProfile.swift` | New. `TherapyKind` (carbRatio / isf), `TherapyEntry` (start minute, value: CR in tenths of g/U, ISF in mg/dL), `TherapyProfile`, `TherapyProfileList` (upsert keeps ids), `TherapyActiveMarker` (same rules as `BasalActiveMarker`, hash in the Nightscout form for the profile's units), `TherapyProfileMath`: 48 half-hour slots (latest start ≤ minute, else last entry), hashes `cr;…` / `isf-mgdl;…` / `isf-mmol;…` (first 8 bytes of SHA-256), Trio `asMmolL` in integer arithmetic (`(mg×555+500)/1000` tenths), mmol→mg/dL (contract revised: the SMALLEST of 9…540 with the same asMmolL — what Trio's mmol/L ISF editor stores), `trioMmolEditorValue` / `snappedForTrio`, Nightscout values rounded half-up from their decimal text, Nightscout → stored entries (refuses off-grid / out-of-range), merge, payload entries, validation mirror, display helpers, comparison rows, direction ("daugiau/mažiau insulino"), > 20 % check, editor input parsing. |
| `LoopFollow/Remote/TRC/TherapyProfiles/TherapyProfilesView.swift` | New. `TherapyProfilesView(kind:)` (list, "Dabar Trio'je", save current, copy/delete/edit, JSON export/import `cr-profiles` / `isf-profiles`), `ActiveTherapySnapshot` (from `ProfileManager.carbRatioSchedule` / `isfSchedule` + `units`; 15-min Unknown), `TherapyProfilesUIState.carbRatio` / `.isf` (activation request, editor draft, current view — id-keyed, outside the views, as `BasalProfilesUIState`), segment editor (00:00 first row fixed, other starts picked in 30-min steps, add/remove), activation view (time \| now \| new \| Δ rows merged where nothing changes, red = more insulin, blue = less; ISF in mmol/L also lists the mg/dL that will be stored). |
| `TRCCommandType.swift`, `PushMessage.swift`, `PushNotificationManager.swift` | `setCarbRatios = "set_carb_ratios"` ("Carb Ratios"), `setISF = "set_isf"` ("ISF"); `carb_ratio_schedule`, `isf_schedule`, `schedule_name` (nil not encoded; `expected_active_hash` shared with basal); `therapySchedulePayload` / `sendTherapySchedulePushNotification` through `sendEncryptedCommand`. |
| `TrioRemoteControlView.swift` | "CR Profiles" and "ISF Profiles" tiles; screens `.carbRatioProfiles` / `.isfProfiles` opened by the hidden links outside the `LazyVGrid`. |
| `Storage.swift` | `carbRatioProfiles`, `activeCarbRatioProfileID`, `isfProfiles`, `activeISFProfileID`. |

**Rules.**
- Lower CR or lower ISF = MORE insulin. Every changed row says "daugiau insulino" / "mažiau insulino"; the summary
  lists the times per direction; any row changing by more than 20 % (exactly 20 % is not) adds a red warning, also
  in the confirmation.
- Expected hash: CR hash of Nightscout `store.default.carbratio`; ISF Nightscout-form hash of `store.default.sens` with
  the profile's `units` ("mg/dl" → `isf-mgdl`, otherwise `isf-mmol` of value × 10). ✓ / "sutampa su aktyviu" compare
  the saved profile's Nightscout-form hash for the same units — in mmol/L two profiles 1 mg/dL apart (46/47) both
  match, which is all Nightscout can tell.
- ISF editor in the app unit (Settings → units). mmol/L input step 0.1 → mg/dL = the smallest of its 0.1 mmol/L group
  (2.6 → 46, 8.3 → 149, 5.0 → 90); an unchanged row keeps its stored mg/dL; a row added by "Pridėti laiką" copies the
  source row's stored value. The editor shows the mg/dL next to each value.
- **Trio in mmol/L refuses** (`set_isf`) any sensitivity that is not the smallest mg/dL of its 0.1 mmol/L group. When
  Trio's Nightscout profile is in mmol/L, the editor snaps such values on save and the activation snaps what it sends
  (also a profile made in mg/dL app mode with 47), each with "HH:MM: 47 → bus siunčiama 46 mg/dL — Trio mmol/L
  redaktoriaus reikšmė."; the Nightscout form (hash, ✓) is unchanged. A refused value is never sent.
- "Išsaugoti dabartinį kaip…" and "Ankstesnis" from an mmol/L Nightscout profile rebuild mg/dL with the same rule;
  Nightscout then shows it exactly as now, Trio's stored mg/dL may differ by 1. Nightscout values that are not exact
  in their unit (CR not a whole 0.1 g/U, ISF not a whole mg/dL / 0.1 mmol/L) are rounded and also marked
  reconstructed. The screen, the save message and the confirmation say so.
- Rows, directions and the > 20 % warning are computed on Nightscout-form integers (Trio's slots vs the profile's
  slots in the same units) and decided without rounding: |new − now| × 100 > 20 × now (CR 4.9 → 3.9, −20.4 %, warns;
  exactly 20 % does not); the unit shown is applied only to the text. A change smaller than one step of the shown
  unit reads "≈". With Trio in mmol/L and equal mmol/L rows whose mg/dL may differ: "≈ (±1 mg/dL)".
- Confirmation text, expected hash and the "Ankstesnis" source come from a re-read at "Aktyvuoti" (warns when the
  schedule changed since the screen opened); "Kartoti" re-sends the identical command, no new backup.
- Units of the screen are taken when a sheet opens (an open editor or activation does not switch units).
- Time zone: every start is minutes from midnight in the **Trio phone's** local time (Nightscout `timeAsSeconds` / 60,
  formatted with plain `%02d:%02d`; nothing passes through a `TimeZone`), so a parent phone in another zone sends
  "07:30" as "07:30". Headers say "Laikas (Trio telefono laikas)", footers "Laikai — Trio telefono laikas, ne šio
  telefono."; the "dabar (nuskaityta HH:MM)" column and "Gauta iš NS" are this phone's clock (when it was read).

**Tests.** `Tests/TherapyProfileTests.swift`: all contract hash vectors (CR1–CR4 incl. split and wrap, ISF1/ISF2 in
both forms, from entries and from Nightscout doubles), asMmolL and the revised mmol→mg/dL vectors (smallest: 0.5→9 … 2.6→46, 8.3→149 … 30.0→540,
296 groups) plus the round trip for 0.5–30.0, snapping for Trio in mmol/L (47 → 46 with a note, hash unchanged),
the > 20 % rule in integers (CR 4.9 → 3.9 warns, 20 % does not, ISF 98 → 77 with the app in mmol/L), "≈ (±1 mg/dL)",
inexact Nightscout values, `ActiveTherapySnapshot.current` after `ProfileManager.loadProfile` (mmol/L and mg/dL
stores, `TherapyProfileManagerTests`), half-up rounding, validation mirror, editor parsing and draft (unchanged mmol text keeps mg/dL), Nightscout
profile decoding (mmol and mg/dL), off-grid refusal and 15-min Unknown, direction words and the > 20 % warning,
encoding of both commands (other commands omit the new keys, alert texts), whole APNS body < 4 KB with 48 entries
and a 30-character name (CR and ISF), storage round trip and upsert, active marker (incl. ISF units). ISF 90 mg/dL end
to end (sent as `"sensitivity":90` in both app units; 5.0 mmol/L → 90; confirmation "5.0 mmol/L (90 mg/dL)").
`TherapyTimeZoneTests` (serialized, restores `NSTimeZone.default`): UTC, Europe/Vilnius, Asia/Tokyo, America/New_York
give the same entries, slots, hashes and `carb_ratio_schedule` / `isf_schedule` / `basal_schedule` start strings.

Manual check (no UI tests): see the report for the on-phone checklist; as for basal, editor and activation sheets
must stay open ≥ 6 min while Nightscout updates arrive.

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
| LoopFollow → Trio (branch `feat/cr-isf-profiles`, not on main yet) | `command_type: "set_carb_ratios"` with `carb_ratio_schedule` = `[{"start":"HH:MM","ratio":<g/U>}]` (1.0–50.0, step 0.1; 1–48 entries, first 00:00, 30-min starts, strictly increasing; adjacent equal values merged), `schedule_name` (1–30 chars, no quotes/control chars), `expected_active_hash` = CR hash (`"cr;"` + 48 × ratio×10) of Nightscout `store.default.carbratio`. Result only as Trio's push ("Carb ratios activated: X" / "Already active: X" / error), not parsed. |
| LoopFollow → Trio (branch `feat/cr-isf-profiles`, not on main yet) | `command_type: "set_isf"` with `isf_schedule` = `[{"start":"HH:MM","sensitivity":<integer mg/dL 9–540>}]` (with Trio in mmol/L only the smallest mg/dL of each 0.1 mmol/L group — Trio refuses others; LoopFollow snaps before sending; mmol/L → mg/dL = that smallest value), `schedule_name`, `expected_active_hash` = ISF Nightscout-form hash of `store.default.sens` (`"isf-mgdl;"` + 48 mg/dL, or `"isf-mmol;"` + 48 × value×10 when Trio uploads in mmol/L). Vectors in both repos' tests. |
| Nightscout → LoopFollow (CR/ISF) | Profile `store.default.carbratio`, `store.default.sens` and `units` ("mg/dl" / "mmol", as Trio `uploadProfiles` writes them; sens = `asMmolL` in mmol/L) = Trio's active schedules; used for ✓, comparison, "Ankstesnis" and the expected hashes. |

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
