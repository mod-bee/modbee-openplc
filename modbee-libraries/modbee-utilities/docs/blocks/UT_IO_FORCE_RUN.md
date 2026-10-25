# UT_IO_FORCE_RUN — One IO force slot (function)

The engine of one commissioning force slot, shared by
[UT_IO_MAP_IN](UT_IO_MAP_IN.md) and [UT_IO_MAP_OUT](UT_IO_MAP_OUT.md). **Not for your
programs: the IO maps call it**, once per slot per scan. This page explains how a
force starts, runs and ends, for the HMI's force page.

It is a function, not a function block. The slot (`UT_IO_FORCE`, described on
[UT_IO_MAP_IN](UT_IO_MAP_IN.md#force-slot-ut_io_force)) keeps all its state.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| inout | `S` | UT_IO_FORCE | | The slot. Its `cmdForce` and `cmdRelease` are read and cleared |
| in | `Where` | UT_IO_Q | UT_IOQ_UNUSED | `UT_IOQ_OK` when the slot's address was found, else why not (`UT_IOQ_NO_MODULE`, `UT_IOQ_NO_CHANNEL`). Anything but OK refuses or ends a force |
| in | `Permit` | BOOL | FALSE | Forcing is allowed now. The input map passes TRUE, the output map its `ForcePermit` |
| in | `Release` | BOOL | FALSE | TRUE: release now and refuse new forces (the map's `ReleaseAll`) |
| in | `Elapsed` | TIME | T#0s | Time since the last scan |
| in | `ForceTime` | TIME | T#0s | How long a force lasts, already limited by the map (5 s … 10 min) |
| returns | | BOOL | | TRUE while the slot forces its channel (the same as `S.active`) |

```iecst
IF UT_IO_FORCE_RUN(S := Force[j], Where := where, Permit := ForcePermit, Release := ReleaseAll,
                   Elapsed := tStep, ForceTime := ft) THEN
  (* put the forced value on the slot's channel *)
END_IF;
```

## The slot's status
| Field | After |
| --- | --- |
| `active` | TRUE while forcing |
| `timeLeft` | The time until the force ends by itself; `T#0s` when not forcing |
| `state` | `UT_IOQ_FORCED` while forcing. `UT_IOQ_NO_MODULE` / `UT_IOQ_NO_CHANNEL` when a force was refused or ended for its address. `UT_IOQ_NOT_PERMITTED` when it was refused or ended for want of `Permit`. `UT_IOQ_UNUSED` after a release, a `Release`, or the time running out. Otherwise it keeps its last value |

There are no status codes: the maps report forcing in their own status (`Warning:
IO forced`, `forcedCount`, `forceLeft`).

## How it works
1. **Commands act once.** `cmdForce` and `cmdRelease` act on their rising edge and
   are cleared every scan. The slot remembers the last value it read
   (`forceSeen`, `releaseSeen`), so a command held on (a Modbus coil, a debugger
   force) acts once, and acts again only after it has been FALSE for a scan.
2. **Release first.** `cmdRelease` or `Release` ends a force at once (`state`
   UNUSED). While `Release` is TRUE, a `cmdForce` is refused and is not kept for
   later.
3. **Start.** `cmdForce` starts a force with `timeLeft` = `ForceTime`, if `Where` is OK
   and `Permit` is TRUE. Otherwise it is refused, and `state` says why. `cmdForce`
   on a slot that is already forcing starts its time again.
4. **Running.** Each scan `timeLeft` goes down by `Elapsed`. If `ForceTime` has been
   made shorter, `timeLeft` is cut to it at once. At 0 the force ends (`state`
   UNUSED).
5. **Lost on the way.** A force ends at once if `Where` stops being OK (the address
   was changed to one that does not exist) or `Permit` drops (`state` says which).
   The slot's address itself is not checked here: the map looks up the channel from
   the slot's address every scan, so a new address that exists moves the force.
6. The function does not look at the slot's `kind`: the input map handles DI and AI
   slots (and clears NONE ones), the output map DO and AO slots.

Nothing is kept over a power cut. Never declare the force slots `RETAIN`.
