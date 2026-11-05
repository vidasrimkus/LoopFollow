# CR/ISF profiles — known gaps (deferred, fail-safe)

- Stale Nightscout `store.units` after Trio's glucose unit changes: every `set_isf` is refused until Trio re-uploads its profile (the expected hash is computed in the wrong form), and the message does not say why — fail-safe (nothing is written), deferred.
- In that stale case (Nightscout says mg/dL, Trio is in mmol/L) Trio's "use <m>" error cannot be fixed from LoopFollow, because LoopFollow snaps only when Nightscout says mmol/L — fail-safe (Trio refuses), clears once Trio re-uploads its profile; deferred.
- `Int(timeAsSeconds)` traps on huge values in `ActiveTherapySnapshot.init(kind:store:)`, the same as the existing upstream `ProfileManager.loadProfile` — only a corrupt Nightscout profile can trigger it, and the app already traps there; deferred with upstream.
- Opening an ISF profile and saving it unchanged while Trio is in mmol/L rewrites its stored mg/dL to the snapped values (47 → 46) — intended (Trio would refuse the original), a note is shown in the editor.
- A malformed segment makes Trio fail to decode the whole payload, so no return notification arrives (see Trio `docs/cr-isf-todo.md`; the same holds for basal) — fail-safe (nothing is written), LoopFollow validates before sending; deferred.
