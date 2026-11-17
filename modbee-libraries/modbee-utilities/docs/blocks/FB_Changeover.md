# FB_Changeover — Two contactors never on together

Two contactors that must never be on together, with the dead time between them and an aux check. The reversing, two-speed and star-delta motors use it; it also works on its own.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | Run: side A, or side B with `bWantB` |
| in | `bWantB` | `BOOL` |  | FALSE: side A (fwd / low / star), TRUE: side B (rev / high / delta) |
| in | `bFbA` | `BOOL` |  | A contactor aux |
| in | `bFbB` | `BOOL` |  | B contactor aux |
| in | `bUseFb` | `BOOL` |  | supervise the auxes |
| in | `tGapAB` | `TIME` |  | dead time A off -> B on |
| in | `tGapBA` | `TIME` |  | dead time B off -> A on |
| in | `tOpenTime` | `TIME` | `T#1s` | a contactor must open / close within this |
| out | `bQA` | `BOOL` |  | Contactor A |
| out | `bQB` | `BOOL` |  | Contactor B (never with A) |
| out | `bInGap` | `BOOL` |  | a planned gap: the owner keeps feedback supervision quiet |
| out | `bStartBlock` | `BOOL` |  | dead time, or the other contactor not open yet |
| out | `bCause` | `BOOL` |  | an aux wrong for the sequence |
| out | `bDeadTime` | `BOOL` |  | waiting out the dead time |
| out | `bWaitOpen` | `BOOL` |  | waiting for the other contactor to open |
| out | `tTimeLeft` | `TIME` |  | gap left |

## How it works

Switch between two contactors A / B that must never be on together (reversing, two-speed, star -> delta). The motor variants' shared piece; usable on its own. `bRun` with `bWantB` FALSE drives A, with `bWantB` TRUE drives B. Changing over: the energised side drops first, then the dead time (`tGapAB` from A to B, `tGapBA` from B to A) runs and, with `bUseFb`, the other contactor's aux must have opened, before the new side closes. `bQA` and `bQB` are never TRUE together. At the first scan both sides wait one full gap (the motor may still be turning). `bCause`: with `bUseFb`, an aux that does not follow its coil within `tOpenTime` (welded, not pulled in): the owner's changeover protection. `bInGap`: a planned gap (and `tOpenTime` after a side closes), so the owner keeps its feedback supervision quiet. `bStartBlock`: the dead time, or the other contactor not open yet.

## Example

Normally used inside the motor variants. On its own: two contactors A and B with auxes.

| Pin | Wire |
| --- | --- |
| `bRun` | `bRunAny` |
| `bWantB` | `bWantSideB` |
| `bFbA` | `DI_A_Aux` |
| `bFbB` | `DI_B_Aux` |
| `bUseFb` | TRUE |
| `tGapAB` | `T#500ms` |
| `tGapBA` | `T#500ms` |
| `bQA` | `DO_A` |
| `bQB` | `DO_B` |

**Back to** [the index](../README.md).
