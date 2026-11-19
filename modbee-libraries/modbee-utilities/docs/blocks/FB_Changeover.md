# FB_Changeover — Two contactors never on together

Two contactors that must never be on together, with the dead time between them and an aux check. The reversing, two-speed and star-delta motors use it; it also works on its own.

## Pins

| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `bRun` | `BOOL` |  | run: side A, or side B with bSelectSideB |
| in | `bSelectSideB` | `BOOL` |  | FALSE: side A (fwd / low / star), TRUE: side B (rev / high / delta) |
| in | `bSideAFeedback` | `BOOL` |  | A contactor aux |
| in | `bSideBFeedback` | `BOOL` |  | B contactor aux |
| in | `bContactorFeedbackFitted` | `BOOL` |  | supervise the auxes |
| in | `tAToBDeadTime` | `TIME` |  | dead time A off -> B on |
| in | `tBToADeadTime` | `TIME` |  | dead time B off -> A on |
| in | `tAuxFeedbackTimeout` | `TIME` | `T#1s` | a contactor must open / close within this |
| out | `bSideAOutput` | `BOOL` |  | contactor A |
| out | `bSideBOutput` | `BOOL` |  | contactor B (never with A) |
| out | `bPlannedGap` | `BOOL` |  | a planned gap: the owner keeps feedback supervision quiet |
| out | `bStartHeld` | `BOOL` |  | dead time, or the other contactor not open yet |
| out | `bAuxWrong` | `BOOL` |  | an aux wrong for the sequence |
| out | `bInDeadTime` | `BOOL` |  | waiting out the dead time |
| out | `bWaitingOtherOpen` | `BOOL` |  | waiting for the other contactor to open |
| out | `tTimeLeft` | `TIME` |  | gap left |

## How it works

Switch between two contactors A / B that must never be on together (reversing, two-speed, star -> delta). The motor variants' shared piece; usable on its own. `bRun` with `bSelectSideB` FALSE drives A, with `bSelectSideB` TRUE drives B. Changing over: the energised side drops first, then the dead time (`tAToBDeadTime` from A to B, `tBToADeadTime` from B to A) runs and, with `bContactorFeedbackFitted`, the other contactor's aux must have opened, before the new side closes. `bSideAOutput` and `bSideBOutput` are never TRUE together. At the first scan both sides wait one full gap (the motor may still be turning). `bAuxWrong`: with `bContactorFeedbackFitted`, an aux that does not follow its coil within `tAuxFeedbackTimeout` (welded, not pulled in): the owner's changeover protection. `bPlannedGap`: a planned gap (and `tAuxFeedbackTimeout` after a side closes), so the owner keeps its feedback supervision quiet. `bStartHeld`: the dead time, or the other contactor not open yet.

## Example

Normally used inside the motor variants. On its own: two contactors A and B with auxes.

| Pin | Wire |
| --- | --- |
| `bRun` | `bRunAny` |
| `bSelectSideB` | `bWantSideB` |
| `bSideAFeedback` | `DI_A_Aux` |
| `bSideBFeedback` | `DI_B_Aux` |
| `bContactorFeedbackFitted` | TRUE |
| `tAToBDeadTime` | `T#500ms` |
| `tBToADeadTime` | `T#500ms` |
| `bSideAOutput` | `DO_A` |
| `bSideBOutput` | `DO_B` |

**Back to** [the index](../README.md).
