# FB_Debounce — On / off delay

An on / off delay filter: ignores anything shorter than its delays.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL` |  | the raw signal |
| in | `tOnDelay` | `TIME` | `T#100ms` | bIn must be TRUE this long to switch bQ on |
| in | `tOffDelay` | `TIME` | `T#100ms` | bIn must be FALSE this long to switch bQ off |
| out | `bQ` | `BOOL` |  | the debounced output |
| out | `bRising` | `BOOL` |  | one scan when bQ comes on |
| out | `bFalling` | `BOOL` |  | one scan when bQ goes off |
| out | `tElapsedTime` | `TIME` |  | how long bIn has held its new state |
| out | `tTimeLeft` | `TIME` |  | the delay still to run |

## How it works

On / off delay filter. `bQ` switches on once `bIn` has been TRUE for `tOnDelay` without a break, and off once it has been FALSE for `tOffDelay`. Anything shorter is ignored. `bRising` / `bFalling`: one scan when `bQ` switches.

A delay of 0 (or less) passes `bIn` straight through. While `bIn` differs from `bQ`, `tElapsedTime` is how long `bIn` has held its new state and `tTimeLeft` the delay still to run; else both 0.

## Example

A float that bounces.

| Pin | Wire |
| --- | --- |
| `bIn` | `DI_Float` |
| `tOnDelay` | `T#2s` |
| `tOffDelay` | `T#2s` |
| `bQ` | the clean float |

**Back to** [the index](../README.md).
