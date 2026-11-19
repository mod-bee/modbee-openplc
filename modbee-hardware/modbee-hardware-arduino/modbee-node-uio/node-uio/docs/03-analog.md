# 03 - Analog

## The units

A channel reads and writes in the unit it is wired for.

| Mode | Unit | Range |
| --- | --- | --- |
| `UIO_VOLTAGE` | volts (REAL) | 0.0 to 10.0 |
| `UIO_CURRENT` | milliamps (REAL) | 0.0 to 20.0 |

So 5 V is `5.0` and 12 mA is `12.0`. A reading below the range reads 0.

## Over range: a saturated input reads 22 mA / 11 V

The converter tops out just above the range's full scale. An input driven beyond
what it can measure — a shorted 4-20 mA transmitter, a sensor failed high —
**saturates** the converter, and the reading is then a clear over-range value
rather than a plausible full scale:

| Mode | A saturated input reads |
| --- | --- |
| `UIO_CURRENT` | 22.0 mA |
| `UIO_VOLTAGE` | 11.0 V |

So transmitter-failed-high detection works: NAMUR NE43 counts anything from
21 mA up as a failed transmitter, and 22.0 is there. Saturation is judged on the
converter count (`nAI01RawCount` at 32765 or more) before calibration, so no offset
can hide it. Short of saturation, a channel calibrated so that full scale sits
below the converter's limit can read a little above it (20.5 mA, an NE43
over-range), up to the same 22 mA / 11 V.

## The mode pin is not the wiring

This is the thing to get right, because nothing will tell you when it is wrong.

Whether a terminal accepts 0-10 V or 0-20 mA is a **solder bridge on the
board**, decided when the board is built. The mode pin only tells the software
which arithmetic to use.

The board leaves the factory with the **inputs bridged for 0-20 mA** and the
**outputs for 0-10 V** — cut the bridge to swap either. The mode pins default to
`UIO_VOLTAGE`, so an input on a factory board needs `UIO_CURRENT` set
explicitly.

Set `UIO_CURRENT` on a channel bridged for voltage and you get a number that
looks entirely reasonable and is wrong. There is no error and no way for the
software to detect it. Check the bridges against what your program says.

## Raw counts

`nAI01RawCount` and friends are the converter's own count, 0 to 32767, before
scaling and before calibration. `nAO01RawCount` and `nAO02RawCount` are the same on the way
out, after scaling.

You need them for two things: calibrating a channel, and working out whether a
reading that looks wrong is the sensor or the scaling.

## How often a reading changes

The four inputs share one converter and are read in turn, so any one channel
refreshes roughly every 20 ms no matter how fast your task runs. Reading
`fAI01` twice in one scan gives the same number twice, and reading it every
millisecond does not make it change every millisecond.

The output converter is only written when the value changes, so holding a
setpoint costs nothing on the I2C bus.

## Calibrating

Two points and an offset per channel:

- `nZeroCount` is the raw count you see with 0 V (or 0 mA) applied.
- `nFullScaleCount` is the raw count with full scale, 10 V (or 20 mA), applied.
- `fOffset` is added to the scaled result afterwards.

Leaving `nZeroCount` and `nFullScaleCount` equal falls back to a straight ratio,
which is what an uncalibrated channel does.

To calibrate AI01:

1. Apply a known 0 V (or 0 mA) and read `nAI01RawCount`. That is `nZeroCount`.
2. Apply a known 10 V (or 20 mA) and read `nAI01RawCount`. That is `nFullScaleCount`.
3. Set `eChannel := UIO_AI01`, the two counts and `fOffset := 0`, then pulse `bApplyCalibration`.
4. Check `fAI01` now reads what you applied.
5. Pulse `bSaveToFlash`.

`bApplyCalibration` takes effect at once but only in RAM. Nothing reaches flash until
`bSaveToFlash`, so you can try values freely.

`eChannel` names the channel — `UIO_AI01` to `UIO_AI04` for the inputs,
`UIO_AO01` and `UIO_AO02` for the outputs.

`bResetAllToDefaults` puts every channel back to its default and saves that — worth knowing
about when a calibration has gone wrong and you want a known starting point.
