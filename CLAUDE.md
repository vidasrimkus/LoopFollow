# CLAUDE.md — vidasrimkus/LoopFollow

## What this repo is

A fork of loopandlearn/LoopFollow used to follow a child's Trio and to send it remote commands
(including dosing-mode changes). Read `CUSTOMIZATIONS.md` before any work.

## Binding rules

1. **Merge to `main` and "4. Build LoopFollow" only after Vidas's explicit word.**
2. **Every commit of ours starts with `[vidas] `.**
3. **Never use GitHub "Sync fork" and never change `SCHEDULED_SYNC`** (it stays `false`). Upstream
   changes come in only through the procedure below.
4. **If an interface changes** (see `CUSTOMIZATIONS.md` §4), say exactly what has to change in
   `vidasrimkus/Trio` and/or `t1d-monitor`.
5. Tests and lint run on GitHub (no Swift toolchain on the Windows machine):
   `unit_tests_fork.yml` (runs on push to `feat/**`) and `gh workflow run lint.yml --ref <branch>`.

## Upstream update procedure

a. Read `CUSTOMIZATIONS.md`.
b. Fetch the loopandlearn/LoopFollow release tag.
c. Branch `upgrade/vX.Y.Z` from `main`; merge the tag.
d. Resolve conflicts keeping our behaviour. If upstream has substantially changed the TRC commands,
   `PushMessage`, `InfoType` or `DeviceStatus` handling, **STOP and explain it to Vidas** before
   resolving anything.
e. Check the interfaces with Trio listed in `CUSTOMIZATIONS.md` §4 against the merged code.
f. Tests + SwiftFormat + reviewer on the final commit.
g. Update `CUSTOMIZATIONS.md`.
h. **Stop before merging to `main`**; show results and wait for Vidas's word.
