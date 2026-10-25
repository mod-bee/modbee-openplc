# UT_HOA — Hand / Off / Auto for anything

Mode selection for outputs that don't have their own block: lights, heaters,
solenoids, a whole system. (Motors and valves have this built in.) Same mode
sources and `cmdMode` codes as the devices ([UT_MODE_SELECT](UT_MODE_SELECT.md)),
without out of service.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `AutoCmd` | BOOL | FALSE | Output wanted in Auto |
| in | `HandCmd` | BOOL | TRUE | Output wanted in Hand (unwired = on) |
| in | `SwHand` / `SwAuto` | BOOL | FALSE | Selector switch (when `modeSource` uses it) |
| in | `Interlock` | BOOL | TRUE | FALSE forces the output off in every mode |
| out | `Out` | BOOL | | The output |
| out | `Mode` | UT_MODE | | The mode now |
| out | `IsOff`, `IsHand`, `IsAuto` | BOOL | | |
| inout | `Data` | UT_HOA_DATA | | |

## Record `UT_HOA_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `modeSource` | UT_MODE_SOURCE | UT_SRC_HMI | `UT_SRC_HMI` · `UT_SRC_SWITCH` · `UT_SRC_REMOTE`. The mode starts at **Off** and is retained (see `powerUp`, `handPowerUp`) |
| `handTimeout` | TIME | T#0s | Hand goes back to Off after this (0 = never) |
| `cmdMode` | INT | −1 | HMI: 0 Off · 1 Hand · 2 Auto. Acts once, when a new value arrives. Anything else is ignored. Set back to −1 |
| `mode` | UT_MODE | | *status* |
| `out` | BOOL | | *status* |
| `powerUp` | UT_POWERUP | UT_PU_LAST | After a power cut or a PLC stop / start: `UT_PU_LAST` the mode comes back as it was (but see `handPowerUp`); `UT_PU_OFF` every mode comes back Off |
| `handPowerUp` | UT_HAND_POWERUP | UT_HPU_OFF | After a power cut, a Hand: `UT_HPU_OFF` comes back **Off**, the output never comes on by itself; `UT_HPU_KEEP` Hand and its output come back |
| `handLeft` | TIME | | *status*: time until the hand timeout ends Hand (0 when no timeout is running) |
| `statusCode` | UT_STATUS | | *status*: what it is doing, see Status codes |
| `statusText` | STRING(30) | | *status*: `statusCode` in words, e.g. `Running: Hand`. The time to the hand timeout is in `handLeft` |

## How it works
| Mode | `Out` |
| --- | --- |
| Off | FALSE |
| Hand | `HandCmd` (TRUE when not wired, so Hand = on) |
| Auto | `AutoCmd` |

`Interlock` FALSE turns `Out` off in every mode; it comes back on when the interlock returns.

- **Hand.** With `HandCmd` not wired, Hand means on, like a hard-wired HOA switch.
  Wire `HandCmd` to make Hand follow your own logic or a pushbutton latch.
- **Power cut** (or a PLC stop / start). With the defaults, Auto comes back
  following `AutoCmd` and Off stays off, from the first scan. A **Hand** comes back
  **Off** (`handPowerUp` = `UT_HPU_OFF`): a Hand chosen on the HMI is set to Off, and
  a selector left in Hand holds the output off until it is turned out of Hand and
  back. A heater or motor left in Hand never starts by itself after a power cut
  (EN 60204-1). `UT_HPU_KEEP` brings Hand back on, for a light that should stay on.
  `powerUp` = `UT_PU_OFF` brings every mode back Off.
- **Hand timeout.** Starts on entering Hand and restarts when the HMI asks for Hand
  again (`cmdMode` 1). When it runs out, a Hand chosen on the HMI goes back to Off.
  A selector left in Hand gives Mode Off and `Out` off until it is turned out of
  Hand and back. `handLeft` shows the time still to go.
- **HMI command.** `cmdMode` acts once when a new value arrives; a value held or
  rewritten there acts once (so a held 1 does not keep restarting the hand
  timeout). With two masters, put [UT_CMD](UT_CMD.md) in front.

## Status codes
`statusCode` is a `UT_STATUS` (an HMI reads its number); `statusText` is the same in words.

| `statusCode` | `statusText` | When |
| --- | --- | --- |
| `UT_ST_OFF` | `Off` | Mode Off |
| `UT_ST_IDLE_HAND` | `Idle: Hand, command off` | Hand, `HandCmd` off |
| `UT_ST_IDLE_NO_DEMAND` | `Idle: no demand` | Auto, `AutoCmd` off |
| `UT_ST_RUN_HAND` | `Running: Hand` | Hand, output on (`handLeft` shows the time to the hand timeout) |
| `UT_ST_RUN_AUTO` | `Running: Auto` | Auto, output on |
| `UT_ST_INTERLOCK` | `Blocked: interlock` | The output is wanted but `Interlock` is FALSE |
| `UT_ST_SELECTOR_HAND` | `Waiting: selector out of Hand` | A selector in Hand after the hand timeout, or after a power cut |

## Using it
```iecst
YardLights(AutoCmd := Dusk, SwHand := LightsHand, SwAuto := LightsAuto, Data := YardLightsHOA);
YardLightsContactor := YardLights.Out;
```
