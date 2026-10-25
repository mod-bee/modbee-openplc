# UT_SEQUENCER — Start/stop chain (conveyors, crushing, process trains)

Starts a chain of machines in order, each waiting for the previous one to prove
it's running, and stops them in reverse order. If a running machine drops out,
everything **after it** in the start order stops at once (cascade stop), so
material doesn't pile up. There's any number of steps: you declare the array.

## Pins
| | Pin | Type | Default | What to wire |
| --- | --- | --- | --- | --- |
| in | `Start` | BOOL | FALSE | Rising edge: start. Held TRUE = a maintained run request (needed for auto restart) |
| in | `Stop` | BOOL | FALSE | Rising edge: stop |
| in | `Abort` | BOOL | FALSE | Level: everything off at once (e.g. NOT e-stop healthy) |
| in | `Hold` | BOOL | FALSE | Pause a start where it is (a stop is never held) |
| in | `Reset` | BOOL | FALSE | Rising edge: clear the fault (a Start or Stop edge also clears it) |
| out | `Running` | BOOL | | Every step up |
| out | `Busy` | BOOL | | Starting, held or stopping |
| out | `Fault` | BOOL | | |
| out | `CurrentStep` | INT | | Position of the step being started or stopped (0 = none) |
| out | `Restarting` | BOOL | | Auto restart countdown running. Wire to a pre-start siren / beacon |
| inout | `Steps` | ARRAY[*] OF UT_SEQ_STEP | | One element per machine, in **start order** |
| inout | `Data` | UT_SEQ_DATA | | Sequence record |

Positions (`CurrentStep`, `faultStep`, `configStep`) count from 1 = the first
element, whatever the array's lower bound.

## Step slot `UT_SEQ_STEP`
| Field | Type | Default | Who writes it | Meaning |
| --- | --- | --- | --- | --- |
| `feedback` | BOOL | FALSE | **you** | Machine running / proven (e.g. `Conveyor2.Running`) |
| `ready` | BOOL | TRUE | you | Machine healthy (e.g. `Conveyor2.Ready`). Auto restart waits for every step to be ready |
| `cmd` | BOOL | | block | Run this machine (→ its `AutoCmd`) |
| `startDelay` | TIME | T#2s | you | After the feedback proves, wait this before the next step |
| `stopDelay` | TIME | T#2s | you | After this step stops, wait this before the next stop |
| `timeout` | TIME | T#10s | you | The feedback must come (start) or go (stop) within this. T#0s = no limit |
| `bypass` | BOOL | FALSE | you / HMI | Don't start this step (maintenance). A step already running keeps running until it is stopped. Clearing it while the chain runs does not start the step: the chain stays RUNNING without it until the next start |
| `noFeedback` | BOOL | FALSE | you | No feedback: proved by `startDelay` alone, never supervised |
| `state` | UT_STATE | | block | OFF, STARTING, ON, STOPPING, FAULT, OOS (bypassed) |
| `elapsed` | TIME | | block | Time in the current start or stop |
| `timeLeft` | TIME | | block | Starting or stopping: its `timeout` left; while the chain waits its `startDelay` or `stopDelay`: the delay left; otherwise 0 |

Ladder, one rung each:
```
|--[ Conveyor2.Running ]-------------( Steps[2].feedback )--|
|--[ Conveyor2.Ready ]---------------( Steps[2].ready )-----|
|--[ Steps[2].cmd ]-----------------( Conveyor2_AutoCmd )--|
```

## Record `UT_SEQ_DATA`
| Field | Type | Default | Meaning |
| --- | --- | --- | --- |
| `stopMode` | UT_SEQ_STOP | UT_SEQ_REVERSE | `UT_SEQ_REVERSE` (last started, first stopped) · `UT_SEQ_ALL_AT_ONCE` · `UT_SEQ_FORWARD` (first started, first stopped: the machines started later keep running, and feeding, until their turn to stop; use it only where that run-on is wanted, e.g. to empty a line) |
| `onLoss` | UT_SEQ_LOSS | UT_SEQ_CASCADE | A step lost or failed to prove: `UT_SEQ_CASCADE` (it and every step after it at once, then the rest in reverse — original behaviour) · `UT_SEQ_STOP_ALL` · `UT_SEQ_DOWNSTREAM_ONLY` (it and every step after it; the steps before it keep running) |
| `autoRestart` | BOOL | FALSE | Restart by itself after a fault stop, once every step is `ready` and `Start` is still held TRUE |
| `restartDelay` | TIME | T#30s | Countdown before an auto restart, with `Restarting` on |
| `cmdStart`, `cmdStop`, `cmdReset` | BOOL | | HMI commands, act once, cleared by the block |
| `mode` | UT_SEQ_MODE | | Status: `UT_SEQ_IDLE`, `_STARTING`, `_RUNNING`, `_STOPPING`, `_ABORTED`, `_HELD`, `_PARTIAL` (some steps running after a DOWNSTREAM_ONLY stop) |
| `statusCode` | UT_STATUS | | Status: what it is doing, or what holds it back (see [Status codes](#status-codes)) |
| `faultId` | UT_FAULT | | Status: the fault or setting the status is about (`UT_F_NONE` when none) |
| `statusText` | STRING(30) | | Status: `statusCode` and `faultId` in words, e.g. `Latched: step fb lost`. The step is in `CurrentStep` / `faultStep` / `configStep`, the time in `timeLeft` |
| `fault` | BOOL | | Status: any fault |
| `faultStep` | INT | | Status: position of the first faulted step (0 = none) |
| `faultCode` | DWORD | | Status: bit 0 timeout, bit 1 feedback lost, bit 2 config |
| `fltTimeout` | BOOL | | Status: a step didn't prove at start, or didn't stop |
| `fltLoss` | BOOL | | Status: a running step lost its feedback |
| `fltConfig` | BOOL | | Status: nothing to run (every step bypassed), or a bad setting |
| `restartIn` | TIME | | Status: auto restart countdown left |
| `timeLeft` | TIME | | Status: the countdown the status shows (a step's delay, the auto restart); 0 when it shows none |
| `configStep` | INT | | Status: the first step with a negative time (0 = none, or a chain setting) |

## How it works
- **Start**: step 1's `cmd` goes on; once its feedback proves, `startDelay` passes, then
  step 2, and so on. Bypassed steps are passed over. A start while stopping (or
  from part running) starts again from step 1: machines still running stay on and
  pass straight through.
- **Stop**: the steps stop one at a time in `stopMode` order, each waiting for its
  feedback to go, then its `stopDelay`. A step whose feedback won't go (welded
  contactor) holds the stop there and raises `did not stop` after its timeout, since
  its machine is still running and the ones it feeds must keep going. **Abort** is the
  way out.
- **Loss / start timeout**: per `onLoss`, see the table above. The fault stays until a
  Start edge, a Stop edge, `Reset` or `cmdReset` (a `did not stop` comes back while
  the machine still runs).
- **Hold** pauses a start: no further step is started and the current step's timers
  stop. Losses and stops still act.
- **Abort** (level) drops every `cmd` at once; the mode shows ABORTED until the next
  Start, Stop or Reset. It never restarts by itself.
- **Auto restart**: after a fault stop, with `Start` held TRUE and every non-bypassed step `ready`, `Restarting`
  comes on for `restartDelay` and the chain starts from step 1. A step going not ready,
  `Start` dropping or `Hold` cancels the countdown. A Stop edge or Abort cancels the
  run request, so a stopped or aborted chain never restarts by itself.
- **Power cut**: nothing is kept. The chain comes back idle with every `cmd` off (even
  if you declared the steps RETAIN) and needs a new Start edge — also with auto restart
  on and `Start` held.
- Start and Stop in the same scan: the stop wins. Commands held on act once.

## Using it
```iecst
VAR  Chain : ARRAY[1..4] OF UT_SEQ_STEP;  ChainData : UT_SEQ_DATA;  END_VAR

Chain[1].feedback := Conveyor3.Running;  Chain[1].ready := Conveyor3.Ready;
Chain[2].feedback := Conveyor2.Running;  Chain[2].ready := Conveyor2.Ready;
Chain[3].feedback := Jaw.Running;        Chain[3].ready := Jaw.Ready;
Chain[4].feedback := Feeder.Running;     Chain[4].ready := Feeder.Ready;
Plant(Start := RunSwitch, Stop := NOT RunSwitch, Abort := NOT EStopOk,
      Steps := Chain, Data := ChainData);
Conveyor3(AutoCmd := Chain[1].cmd, ...);   (* and so on *)
Siren := Plant.Restarting;
```

## Status codes
`statusCode` is a `UT_STATUS` and `faultId` a `UT_FAULT` (an HMI reads their numbers);
`statusText` is the two in words, changed only when one of them changes. The one main
thing, in the order config, fault, held, normal, off. The step is in `CurrentStep`
(starting, stopping, held), `faultStep` (a fault) or `configStep` (a bad setting), the
countdown in `timeLeft`, and each step's state in `Steps[n].state`. Name the steps on
the HMI, by position.

| `statusCode` | `faultId` | `statusText` | When |
| --- | --- | --- | --- |
| `UT_ST_OFF` | | `Off` | Idle |
| `UT_ST_OFF_ABORTED` | | `Off: aborted` | After an Abort (until a Start, Stop or Reset) |
| `UT_ST_RUN_ALL` | | `Running: all steps` | Every step up |
| `UT_ST_STARTING` | | `Starting` | Waiting for the step's proof; then its `startDelay` (`timeLeft`) |
| `UT_ST_STOPPING` | | `Stopping` | Waiting for the step to stop; then its `stopDelay` (`timeLeft`); or all at once (`CurrentStep` 0) |
| `UT_ST_RUN_PART` | | `Running: part` | Part running after a DOWNSTREAM_ONLY stop, the fault reset |
| `UT_ST_AUTO_RESTART` | | `Waiting: auto restart` | Auto restart counting down (`Restarting`, `timeLeft`), no fault left |
| `UT_ST_ABORT` | | `Blocked: abort` | `Abort` TRUE: everything off |
| `UT_ST_HELD` | | `Held` | `Hold` during a start |
| `UT_ST_FAULT_RESET` | `UT_F_STEP_NO_FB` | `Latched: step no feedback` | A step did not prove at start (`fltTimeout`) |
| `UT_ST_FAULT_RESET` | `UT_F_STEP_FB_LOST` | `Latched: step fb lost` | A running step lost its feedback (`fltLoss`) |
| `UT_ST_FAULT_RESET` | `UT_F_STEP_NO_STOP` | `Latched: step not stopped` | A step's feedback did not go when stopped |
| `UT_ST_FAULT_RETRY` | the same | `Retrying: step fb lost` | The same, with an auto restart counting down (`timeLeft`) |
| `UT_ST_CONFIG` | `UT_F_STEP_SETTING` | `Config: step setting` | A step's negative time (`fltConfig`, `configStep`) |
| `UT_ST_CONFIG` | `UT_F_CHAIN` | `Config: chain setting` | `stopMode`, `onLoss` or `restartDelay` |
| `UT_ST_CONFIG` | `UT_F_NO_STEPS` | `Config: no steps to run` | A start with nothing to run (all bypassed) |

## Bad settings
A negative `startDelay`, `stopDelay`, `timeout` or `restartDelay`, or an unknown
`stopMode` / `onLoss`, is a config fault (`fltConfig`, `Config: step setting` with the
step in `configStep`, or `Config: chain setting`) while it lasts: no start and no auto restart. A chain already running
carries on (a negative time acts as 0, an unknown stopMode as REVERSE, onLoss as
CASCADE) and stops normally.
