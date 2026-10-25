# UT_SYSTEM_MODE — The plant's mode: Off / Manual / Auto

Most sites have one mode for the whole plant on top of the device modes: **Off**
(nothing runs), **Manual** (run while someone holds a run request) and **Auto**
(the program runs the plant), often with a choice of auto programs. UT_SYSTEM_MODE
is that, with local / remote and a safe manual run.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `LocalRun` | BOOL | FALSE | Local manual run request, **held**: a run button held, a run switch, the local HMI's run button |
| in | `RemoteRun` | BOOL | FALSE | Remote manual run request, held (SCADA) |
| in | `RemoteEnabled` | BOOL | TRUE | FALSE: local control, `RemoteRun` is refused |
| in | `CommsOk` | BOOL | TRUE | FALSE: the remote link is down, `RemoteRun` is dropped (wire [UT_WATCHDOG](UT_WATCHDOG.md)'s `NOT CommsFail`) |
| in | `SwManual` / `SwAuto` | BOOL | FALSE | Plant selector switch (when `modeSource` uses it) |
| in | `ForceOff` | BOOL | FALSE | TRUE holds the plant Off (an e-stop healthy relay dropped, a tariff block). The chosen mode comes back after |
| out | `Mode` | UT_SYS_MODE | | `UT_SYS_OFF` · `UT_SYS_MANUAL` · `UT_SYS_AUTO` |
| out | `IsOff` / `IsManual` / `IsAuto` | BOOL | | |
| out | `AutoType` | INT | | The auto type chosen (1 … `autoTypes`). Your program reads it while `IsAuto` |
| out | `ManualRun` | BOOL | | Run now: Manual, with a run request held |
| out | `Changed` | BOOL | | One scan: the mode or the auto type has just changed |
| inout | `Data` | UT_SYSTEM_MODE_DATA | | Settings, commands and status |

## Record `UT_SYSTEM_MODE_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `modeSource` | UT_MODE_SOURCE | UT_SRC_HMI | `UT_SRC_HMI` (cmdMode) · `UT_SRC_SWITCH` (SwManual / SwAuto) · `UT_SRC_REMOTE` (selector Off and Manual local, Auto hands over to cmdMode) |
| `powerUp` | UT_POWERUP | UT_PU_LAST | After a power cut or PLC stop / start: `UT_PU_LAST` the mode comes back; `UT_PU_OFF` back to Off |
| `autoTypes` | INT | 1 | Auto types offered: 1 … `autoTypes` (below 1 acts as 1) |
| `manualMaxRun` | TIME | T#0s | A manual run stops after this (0 = no limit) |
| `cmdMode` | INT | −1 | HMI: 0 Off · 1 Manual · 2 Auto. Acts once when a new value arrives; anything else ignored. Set back to −1 |
| `cmdAutoType` | INT | −1 | HMI: 1 … `autoTypes`. Acts once when a new value arrives; anything else ignored. Set back to −1 |
| `mode` | UT_SYS_MODE | | *status* |
| `autoType` | INT | | *status*: the auto type chosen (kept over a power cut) |
| `manualRun` | BOOL | | *status*: a manual run is on |
| `runFrom` | UT_CMD_FROM | | *status*: who holds it: `UT_FROM_LOCAL` · `UT_FROM_REMOTE` (local first when both) · `UT_FROM_NONE` |
| `runTime` | TIME | | *status*: how long the manual run has lasted (0 when not running) |
| `timeLeft` | TIME | | *status*: manual run time left (0 without `manualMaxRun`) |
| `remote` | BOOL | | *status*: `RemoteEnabled` |
| `statusCode` | UT_STATUS | | *status*: see Status codes |
| `faultId` | UT_FAULT | | *status*: the setting that keeps it off (`UT_F_MANUAL_MAX_RUN`), else `UT_F_NONE` |
| `statusText` | STRING(30) | | *status*: `statusCode` and `faultId` in words, e.g. `Manual: running (remote)`. The auto type is in `autoType`, the time left in `timeLeft` |

## How it works
**The mode** works as a device mode ([UT_MODE_SELECT](UT_MODE_SELECT.md)): from the
HMI, a selector, or both, starting at Off, with `powerUp` deciding what comes back
after a power cut. The **auto type** is kept over a power cut in every case.
Commands act once, when a new value arrives; with two masters put
[UT_CMD](UT_CMD.md) in front of `cmdMode`.

**Manual run**: `ManualRun` is on in Manual while a run request is **held**:
`LocalRun`, or `RemoteRun` while `RemoteEnabled` and `CommsOk`. Drop it and the
run stops. A request must be **released and given again** before it runs:
- after a power cut or PLC start (a run switch left on doesn't start the plant);
- after the mode changes (entering Manual with the button held);
- after the remote side was refused (local control) or cut off (comms lost),
  so a stale SCADA request never restarts it;
- after `manualMaxRun` has run out.

**Auto**: the block only says Auto and which type. Your program runs the plant from
`IsAuto` and `AutoType`. A manual request does nothing in Auto.

**Retained**: only the mode (as UT_MODE_SELECT) and the auto type, each saved only
when it changes.

## Status codes
`statusCode` is a `UT_STATUS` (an HMI reads its number); `statusText` is the same in words.

| `statusCode` | `statusText` | When |
| --- | --- | --- |
| `UT_ST_OFF` | `Off` | Mode Off |
| `UT_ST_IDLE_MANUAL` | `Idle: Manual, no run request` | Manual, no run request held |
| `UT_ST_AUTO` | `Auto` | Auto (the type chosen is in `autoType`) |
| `UT_ST_MANUAL_LOCAL` | `Manual: running (local)` | A manual run held by `LocalRun` (`timeLeft` with `manualMaxRun`) |
| `UT_ST_MANUAL_REMOTE` | `Manual: running (remote)` | A manual run held by `RemoteRun` |
| `UT_ST_FORCED_OFF` | `Blocked: forced off` | `ForceOff` |
| `UT_ST_SELECT_MODE` | `Waiting: select a mode` | `UT_PU_OFF`, selector found in Manual or Auto at power-up: move it |
| `UT_ST_MUST_CYCLE` | `Waiting: command must cycle` | A run request must be released and given again |
| `UT_ST_MANUAL_MAX_RUN` | `Manual: max run, release run` | `manualMaxRun` ran out |
| `UT_ST_REMOTE_REFUSED` | `Blocked: remote run refused` | `RemoteRun` under local control |
| `UT_ST_COMMS_LOST` | `Blocked: comms lost` | `RemoteRun` dropped: `CommsOk` FALSE |
| `UT_ST_CONFIG` + `UT_F_MANUAL_MAX_RUN` | `Config: manual max run` | `manualMaxRun` negative: no manual run until fixed |

## Using it
```iecst
Plant(LocalRun := PanelRunPB, RemoteRun := SCADA_Run, RemoteEnabled := NOT LocalSw,
      CommsOk := NOT ScadaLink.CommsFail, Data := PlantMode);   (* autoTypes := 2 *)
IrrigationEnable := Plant.IsAuto AND Plant.AutoType = 1;
PumpDownEnable := Plant.IsAuto AND Plant.AutoType = 2;
Pump1Demand := Plant.ManualRun OR (Plant.IsAuto AND LevelHigh);
```
