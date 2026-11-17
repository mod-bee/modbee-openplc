# FB_Toggle — Push-on / push-off

Push-on / push-off: each press flips the output.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bIn` | `BOOL R_EDGE` |  | Acts on its rising edge. |
| in | `bReset` | `BOOL` |  | Held: bQ off (wins) |
| in | `bForceOn` | `BOOL` |  | Held: bQ on |
| in | `bEdgeAtStart` | `BOOL` |  | A button held at the first scan counts as a press |
| out | `bQ` | `BOOL` |  | The output |

## How it works

Push-on / push-off. Each press (rising edge of `bIn`) flips `bQ`. `bReset` forces `bQ` off and wins; `bForceOn` forces it on; both act while held. `bQ` starts off (not kept). A button held at the first scan counts as a press only with `bEdgeAtStart`.

## Example

A push-on / push-off light.

| Pin | Wire |
| --- | --- |
| `bIn` | `DI_LightPB` |
| `bQ` | `DO_Light` |

**Back to** [the index](../README.md).
