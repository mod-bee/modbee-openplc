# UT_IRR_DEFER — Wet weather: defer irrigation

Says when **not** to irrigate, and why: rain, saturated soil, a lost rain or soil
sensor, or a manual or remote defer. While irrigation is deferred, `ToStorage` sends
the effluent to storage instead. A short shower or a noisy reading does not stop a
run, and once deferred, irrigation waits for the soil to drain before it is allowed
again.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Rain` | BOOL | FALSE | Raining: a rain switch, or your own rain-rate check |
| in | `SoilWet` | BOOL | FALSE | Soil saturated: a moisture switch, or your own % check |
| in | `RainOk` | BOOL | TRUE | The rain sensor's signal is good. FALSE = lost: defers (e.g. `Dig[n].ok` from [UT_IO_MAP_IN](UT_IO_MAP_IN.md), or UT_ANALOG_IN's `Good`) |
| in | `SoilOk` | BOOL | TRUE | The soil sensor's signal is good. FALSE = lost: defers |
| in | `Manual` | BOOL | FALSE | Manual defer: a panel switch or an HMI button |
| in | `Remote` | BOOL | FALSE | Remote defer from SCADA |
| out | `Defer` | BOOL | | Do not irrigate: block the runs |
| out | `Reason` | UT_DEFER | | Why (below). `UT_DEF_NONE` when irrigation is allowed |
| out | `ToStorage` | BOOL | | Send the effluent to storage: `Defer`, when a storage is fitted (`storage`) |
| inout | `Data` | UT_IRR_DEFER_DATA | | Settings and status |

## Using it
```iecst
Wet(Rain := RainSwitch, SoilWet := SoilProbe.Value > SoilWetPct, SoilOk := SoilProbe.Good,
    Manual := HmiDefer, Remote := ScadaDefer, Data := WetData);

RunLimit(Start := RunStart, Permit := NOT Wet.Defer, Running := M1.Running, Data := RunData);
StorageValve(AutoOpen := Wet.ToStorage, Data := StorageValveData);
```

For an irrigation zone program, wire `Defer` to [UT_ZONE_SEQ](UT_ZONE_SEQ.md)'s
`RainHold` (its `rainAction` decides pause, skip or cancel). With
[UT_RUN_LIMIT](UT_RUN_LIMIT.md), `Permit := NOT Defer` ends a run and refuses a
new one.

## Record `UT_IRR_DEFER_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `useRain` | BOOL | TRUE | A rain sensor is fitted. FALSE: `Rain` and `RainOk` are ignored |
| `useSoil` | BOOL | TRUE | A soil sensor is fitted. FALSE: `SoilWet` and `SoilOk` are ignored |
| `onDelay` | TIME | T#1m | A weather cause must last this long to defer |
| `clearDelay` | TIME | T#1h | Every weather cause must be gone this long before irrigation is allowed again |
| `storage` | BOOL | TRUE | A storage is fitted: `ToStorage` follows `Defer` |
| `statusCode` | UT_STATUS | | Status: why it defers, or OK (below) |
| `faultId` | UT_FAULT | | Status: `UT_F_DEFER_DELAY` with a bad delay, else `UT_F_NONE` |
| `statusText` | STRING(30) | | Status: the two in words |
| `timeLeft` | TIME | | Status: the on delay still to go before deferring, or the clear delay still to go before allowing (0 = none) |

There are no HMI commands: a manual defer from the HMI goes to the `Manual` pin.

## Reasons `UT_DEFER`
When more than one applies, `Reason` is the first in this order: SETTING, MANUAL,
REMOTE, RAIN, SOIL, RAIN_LOST, SOIL_LOST.

| No. | `Reason` | Why |
| --- | --- | --- |
| 0 | `UT_DEF_NONE` | Irrigation is allowed |
| 1 | `UT_DEF_MANUAL` | `Manual` |
| 2 | `UT_DEF_REMOTE` | `Remote` |
| 3 | `UT_DEF_RAIN` | Rain (with a good rain sensor) |
| 4 | `UT_DEF_SOIL` | Soil wet (with a good soil sensor) |
| 5 | `UT_DEF_RAIN_LOST` | The rain sensor is lost (`RainOk` FALSE) |
| 6 | `UT_DEF_SOIL_LOST` | The soil sensor is lost (`SoilOk` FALSE) |
| 7 | `UT_DEF_SETTING` | A delay is negative: deferred until it is fixed |

## Status
The numbers are in [conventions](../conventions.md#the-numbers).

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_CONFIG` | `UT_F_DEFER_DELAY` | `Config: defer delay` | `onDelay` or `clearDelay` is negative: deferred until fixed |
| `UT_ST_DEFER_MANUAL` | | `Deferred: manual` | `Manual` |
| `UT_ST_DEFER_REMOTE` | | `Deferred: remote` | `Remote` |
| `UT_ST_DEFER_RAIN` | | `Deferred: rain` | Deferred by the weather; it is raining now |
| `UT_ST_DEFER_SOIL` | | `Deferred: soil wet` | Deferred by the weather; the soil is wet now |
| `UT_ST_DEFER_SENSOR` | | `Deferred: sensor lost` | Deferred by the weather; a rain or soil sensor is lost now |
| `UT_ST_DEFER_CLEARING` | | `Deferred: clearing` | Every weather cause has gone; the clear delay counts (`timeLeft`). `Reason` keeps the last weather cause |
| `UT_ST_OK` | | `OK` | Irrigation is allowed. Also while a weather cause waits out its on delay (`timeLeft`) |

## How it works
1. **Manual and Remote** defer at once and release at once.
2. **The weather causes** are rain, wet soil, a lost rain sensor and a lost soil
   sensor. Any one of them must last `onDelay` (default 1 min) to defer, so one tip
   of a rain gauge or a noisy reading does not stop a run. A cause that changes into
   another (rain, then wet soil) counts as one.
3. **Clearing.** Once deferred by the weather, every weather cause must be gone for
   `clearDelay` (default 1 h, while the soil drains) before irrigation is allowed
   again. A cause that comes back in that time defers again at once, and the clear
   delay starts again from the beginning when it goes.
4. **A lost sensor defers**, as a fail-safe: wet weather is assumed. A rain reading
   from a lost sensor is ignored; the loss itself is the cause.
5. **Not fitted:** `useRain` or `useSoil` FALSE ignores that sensor and its signal
   quality.
6. While the weather defers, `Reason` follows the cause present now; while clearing,
   it keeps the last one.
7. `ToStorage` is `Defer` when `storage` is TRUE, for every reason, the setting
   error too.

### Invalid settings
A negative `onDelay` or `clearDelay` is a setting error: it defers (the safe way),
`Reason` `UT_DEF_SETTING` and `Config: defer delay`, until it is fixed. `T#0s` is
valid: no on delay, or no clear delay.

### Power cut
Nothing is kept. The weather defer starts clear: a weather cause still present
defers again after `onDelay`. A clear delay that was counting at the cut is not finished:
irrigation is allowed at once if the weather has gone.
