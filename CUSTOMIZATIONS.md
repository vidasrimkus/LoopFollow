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
