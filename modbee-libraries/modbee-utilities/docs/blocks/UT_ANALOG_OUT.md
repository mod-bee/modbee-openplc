# UT_ANALOG_OUT — Analog output (eng → raw, clamp, ramp, hand, fail value)

Turns an engineering value (e.g. % speed, % valve) into the raw value for an analog
output card. It adds limits, a rate limit, a hand value, and a defined value on
interlock.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `In` | REAL | 0.0 | Engineering demand (Auto), e.g. the PID output |
| in | `Interlock` | BOOL | TRUE | FALSE → `failValue` (or hold), in Hand too |
| in | `Hand` | BOOL | FALSE | Use `handValue` (or set `cmdMode`) |
| out | `Out` | REAL | | Engineering value actually output |
| out | `OutRaw` | UINT | | For `%QW` |
| out | `Limited` | BOOL | | Clamped or ramping |
| inout | `Data` | UT_ANALOG_OUT_DATA | | |

## Record `UT_ANALOG_OUT_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `engMin` / `engMax` | REAL | 0.0 / 100.0 | Engineering range |
| `rawMin` / `rawMax` | REAL | 0.0 / 65535.0 | Raw values at `engMin` / `engMax` (e.g. 0 / 27648) |
| `outMin` / `outMax` | REAL | 0.0 / 100.0 | Output clamp (either order works) |
| `rampUp` / `rampDown` | REAL | 0.0 / 0.0 | Rate limit rising / falling, engineering units per `rateUnit` (0 = off) |
| `failValue` | REAL | 0.0 | Output while `Interlock` is FALSE (at once, no ramp) |
| `holdOnInterlock` | BOOL | FALSE | TRUE: hold the output instead of `failValue` |
| `handValue` | REAL | 0.0 | Output in Hand. Tracks `In` while in Auto, so switching to Hand is bumpless |
| `cmdMode` | INT | -1 | HMI: `1` Hand, `2` Auto. Acts when a new value arrives; set back to −1; other codes are ignored |
| `out`, `raw`, `hand` | | | Status: `Out`, `OutRaw`, in Hand now |
| `wrnBadInput` | BOOL | | The demand is NaN or infinite: the output holds |
| `wrnConfig` | BOOL | | `engMin = engMax`, or a NaN / infinite range or limit, or an unknown `rateUnit` |
| `rateUnit` | UT_RATE_UNIT | UT_PER_SEC | `rampUp` / `rampDown` are per second, minute (`UT_PER_MIN`), hour or day |

## How it works
- **Auto / Hand**: Hand if the `Hand` pin is TRUE or the HMI chose Hand
  (`cmdMode` 1). The HMI choice starts in **Auto**.
- **Clamp, then ramp**: the demand is clamped to `outMin..outMax`, then `Out` moves
  towards it at no more than `rampUp` / `rampDown` per `rateUnit` (timed from real
  elapsed time): a slow valve opening of 10 % per minute is `rampUp` 10 with
  `UT_PER_MIN`. An unknown `rateUnit` sets `wrnConfig` and the output does not ramp.
  At power-up the output starts from 0 and ramps.
- **cmdMode** acts once when a new valid value arrives: one held or rewritten acts
  once. A master that rewrites it every poll goes through [UT_CMD](UT_CMD.md).
- **Interlock** FALSE: `failValue` at once (also in Hand), or the last output with
  `holdOnInterlock`. When it returns, the output ramps back from there.
- **OutRaw** is clamped to 0..65535, so it never wraps; a clamp shows on `Limited`.
- **Power cut**: nothing is kept. The HMI choice starts in Auto again. (`handValue`
  lives in your record: declare the record `RETAIN` to keep it.)

## Using it
```iecst
SpeedOut(In := SpeedPid.Q, Interlock := PumpRunning, Data := SpeedOutCfg);
%QW0 := SpeedOut.OutRaw;
```
