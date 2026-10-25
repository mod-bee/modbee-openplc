(* UT_LINK_SUPERVISOR — escalating recovery of a remote site's comms link.

LinkOk comes from whatever checks the link (a UT_WATCHDOG on the SCADA
heartbeat, the modem's connected flag). While it is FALSE the supervisor
steps up, each step optional (its time T#0s = off), timed from when the
link went down (or from power-up, if it is down then):

  restartAfter      (30 s)  RestartModem is TRUE for pulseTime
  powerCycleAfter   (5 min) PowerCycle is TRUE for powerOffTime
  rebootAfter       (10 min) ONE controlled reboot of the controller:
                            RebootReq is TRUE until it reboots

After those steps the modem is tried again with a back-off: the first
retry comes restartAfter after the last step (powerCycleAfter if the
restart step is off), each wait twice the one before, up to maxBackoff
(10 min). A retry power cycles the modem (or restarts it, if the power
cycle step is off). The back-off starts again once the link has stayed up
for maxBackoff.

The reboot happens only while RebootAllowed is TRUE (the program vetoes it
while equipment runs; it waits and reboots once allowed, in the same
outage), and at most maxRebootsPerDay times a day. The count is kept over
the reboot itself (and any power cut), so a dead link can never make the
controller reboot in a loop. It is counted and saved first; RebootReq
follows rebootSaveWait later. With a set Clock (local time, 2000 or
later) the count starts again at each date change. Without one (unwired,
or not set yet) it starts again countWindow (24 h) of running time after
the first counted reboot: a rolling window, kept over reboots too (its
progress is saved in 24 steps, so a reboot or power cut loses at most one
step and the window only gets longer; time switched off does not count).
cmdResetReboots sets the count to 0 at any time.

The outputs are pins: wire RestartModem to the modem block's restart,
PowerCycle to the relay or HAT power that feeds the modem (TRUE = off),
RebootReq to the controller's reboot. *)

FUNCTION_BLOCK UT_LINK_SUPERVISOR
  VAR_INPUT
    LinkOk : BOOL; (* the link works (heartbeat seen, modem connected) *)
    Enable : BOOL := TRUE; (* the link is in use (FALSE: nothing is done) *)
    RebootAllowed : BOOL; (* wire "nothing running, no lock-out" to allow a reboot (66) *)
    Clock : DT; (* local time, for the reboots-per-day count (unwired: no day change) *)
    ResetReboots : BOOL R_EDGE; (* the reboot count to 0 *)
  END_VAR
  VAR_OUTPUT
    RestartModem : BOOL; (* TRUE for pulseTime: restart the modem *)
    PowerCycle : BOOL; (* TRUE for powerOffTime: switch the modem's power off *)
    RebootReq : BOOL; (* reboot the controller (held until it does) *)
    LinkDown : BOOL; (* the link is down *)
    Warning : BOOL;
  END_VAR
  VAR_IN_OUT
    Data : UT_LINK_SUPERVISOR_DATA;
  END_VAR
  VAR RETAIN
    keptSet : UT_LINK_SUPERVISOR_SET;
    keptGood : BOOL;
    savedReboots : INT; (* the reboot count and the day it belongs to *)
    savedDay : LINT;
    savedWin : TIME; (* no clock: running time since the first counted reboot (saved in steps) *)
  END_VAR
  VAR
    keep : UT_KEEP;
    setOk : BOOL;
    linkIn : BOOL;
    started : BOOL;
    tCur : TIME;
    down : BOOL;
    downAt : TIME;
    upAt : TIME;
    done1 : BOOL; (* this outage: modem restarted *)
    done2 : BOOL; (* power cycled *)
    done3 : BOOL; (* reboot step done (or skipped: limit) *)
    rebooting : BOOL;
    rebootAt : TIME;
    lastAt : TIME; (* the last restart / power cycle (back-off from here) *)
    backoff : TIME;
    firstWait : TIME;
    pulseAt : TIME;
    cycleAt : TIME;
    pulseOn : BOOL;
    cycleOn : BOOL;
    cmdPrev : BOOL;
    cmd : BOOL;
    secs : LINT;
    dayNo : LINT;
    stepsDone : BOOL; (* the restart and power cycle steps are done (or off) *)
    retryDue : BOOL;
    tNext : TIME;
    sc : UT_STATUS;
    shown : BOOL; (* statusText has been set *)
    clockOk : BOOL; (* Clock is set (2000 or later) *)
    winBase : TIME; (* no clock: TIME() the unsaved part of the window counts from *)
    win : TIME; (* countWindow in use *)
    winStep : TIME; (* the window is saved in these steps *)
  END_VAR


tCur := TIME();
keep();
IF keep.RestoreSet THEN
  Data.set := keptSet;
END_IF;
setOk := Data.set.restartAfter >= T#0s AND Data.set.powerCycleAfter >= T#0s AND Data.set.rebootAfter >= T#0s
         AND Data.set.pulseTime >= T#0s AND Data.set.powerOffTime >= T#0s AND Data.set.maxBackoff >= T#0s
         AND Data.set.maxRebootsPerDay >= 0 AND Data.set.rebootSaveWait >= T#0s AND Data.set.countWindow >= T#0s;
IF NOT setOk AND keptGood AND NOT keep.FirstBoot THEN
  Data.sts.refused := UT_F_SETTING;
  Data.sts.refusedWhy := UT_F_SETTING;
  Data.set := keptSet;
  setOk := TRUE;
END_IF;
IF keep.SaveSet AND (setOk OR NOT keptGood) THEN
  keptSet := Data.set;
  keptGood := setOk;
END_IF;
linkIn := LinkOk OR NOT Enable;  (* not in use: nothing to recover *)
IF NOT started THEN
  started := TRUE;
  Data.sts.rebootsToday := savedReboots;
  upAt := tCur;
  winBase := tCur;
  down := FALSE;
END_IF;
IF Data.set.restartAfter > T#0s THEN
  firstWait := Data.set.restartAfter;
ELSE
  firstWait := Data.set.powerCycleAfter;
END_IF;

(* the HMI reset of the reboot count *)
cmd := Data.cmdResetReboots;
Data.cmdResetReboots := FALSE;
IF (cmd AND NOT cmdPrev) OR ResetReboots THEN
  Data.sts.rebootsToday := 0;
  savedReboots := 0;
  savedWin := T#0s;
  winBase := tCur;
END_IF;
cmdPrev := cmd;

(* the reboot count: per day of Clock, or without a set clock a rolling
   countWindow of running time from the first counted reboot *)
win := Data.set.countWindow;
IF win <= T#0s THEN
  win := T#24h;                      (* not a usable window: the default *)
END_IF;
winStep := win / 24;
IF winStep <= T#0s THEN
  winStep := T#1ms;
END_IF;
secs := DT_TO_LINT(Clock);
clockOk := secs >= 946684800;        (* 2000-01-01 *)
Data.det.countResetIn := T#0s;
IF clockOk THEN
  dayNo := secs / 86400;
  IF dayNo <> savedDay THEN
    savedDay := dayNo;
    Data.sts.rebootsToday := 0;
    savedReboots := 0;
  END_IF;
ELSIF Data.sts.rebootsToday > 0 THEN
  IF tCur - winBase >= winStep THEN
    savedWin := savedWin + winStep;  (* saved a step at a time: rare writes *)
    winBase := winBase + winStep;
  END_IF;
  IF savedWin + (tCur - winBase) >= win THEN
    Data.sts.rebootsToday := 0;          (* the window is over: the count starts again *)
    savedReboots := 0;
    savedWin := T#0s;
  ELSE
    Data.det.countResetIn := win - (savedWin + (tCur - winBase));
  END_IF;
END_IF;
IF Data.sts.rebootsToday = 0 OR clockOk THEN
  winBase := tCur;                   (* the window starts at the first counted reboot *)
  IF savedWin <> T#0s THEN
    savedWin := T#0s;
  END_IF;
END_IF;

(* outage start and end *)
IF NOT linkIn AND NOT down THEN
  down := TRUE;
  downAt := tCur;
  done1 := FALSE;
  done2 := FALSE;
  done3 := FALSE;
  IF tCur - upAt >= Data.set.maxBackoff OR backoff <= T#0s THEN
    backoff := firstWait;            (* up long enough: the back-off starts again *)
  END_IF;
ELSIF linkIn AND down THEN
  down := FALSE;
  upAt := tCur;
  Data.sts.lastDownFor := tCur - downAt;
  Data.sts.outages := Data.sts.outages + 1;
  rebooting := FALSE;
  Data.sts.rebootPending := FALSE;
END_IF;

(* the steps *)
stepsDone := FALSE;
retryDue := FALSE;
IF down THEN
  Data.det.downFor := tCur - downAt;
  IF NOT done1 AND Data.set.restartAfter > T#0s AND Data.det.downFor >= Data.set.restartAfter THEN
    done1 := TRUE;
    pulseOn := TRUE;
    pulseAt := tCur;
    lastAt := tCur;
    Data.sts.restarts := Data.sts.restarts + 1;
  END_IF;
  IF NOT done2 AND Data.set.powerCycleAfter > T#0s AND Data.det.downFor >= Data.set.powerCycleAfter THEN
    done2 := TRUE;
    cycleOn := TRUE;
    cycleAt := tCur;
    lastAt := tCur;
    Data.sts.powerCycles := Data.sts.powerCycles + 1;
  END_IF;
  IF NOT done3 AND Data.set.rebootAfter > T#0s AND Data.det.downFor >= Data.set.rebootAfter THEN
    IF Data.sts.rebootsToday >= Data.set.maxRebootsPerDay THEN
      done3 := TRUE;                 (* the day's limit: no reboot *)
      Data.sts.rebootPending := FALSE;
    ELSIF RebootAllowed THEN
      done3 := TRUE;
      Data.sts.rebootPending := FALSE;
      Data.sts.rebootsToday := Data.sts.rebootsToday + 1;
      savedReboots := Data.sts.rebootsToday;   (* saved before the reboot is asked for *)
      IF secs >= 946684800 THEN
        savedDay := dayNo;
      END_IF;
      rebooting := TRUE;
      rebootAt := tCur;
    ELSE
      Data.sts.rebootPending := TRUE;
    END_IF;
  END_IF;
  (* retries with a back-off once the restart and power cycle steps are past *)
  stepsDone := (done1 OR Data.set.restartAfter <= T#0s) AND (done2 OR Data.set.powerCycleAfter <= T#0s)
               AND (done1 OR done2);
  IF stepsDone AND backoff > T#0s AND tCur - lastAt >= backoff THEN
    retryDue := TRUE;
    lastAt := tCur;
    IF Data.set.powerCycleAfter > T#0s THEN
      cycleOn := TRUE;
      cycleAt := tCur;
      Data.sts.powerCycles := Data.sts.powerCycles + 1;
    ELSE
      pulseOn := TRUE;
      pulseAt := tCur;
      Data.sts.restarts := Data.sts.restarts + 1;
    END_IF;
    IF backoff >= Data.set.maxBackoff / 2 THEN
      backoff := Data.set.maxBackoff;
    ELSE
      backoff := backoff + backoff;
    END_IF;
  END_IF;
ELSE
  Data.det.downFor := T#0s;
END_IF;

(* the outputs: pulses run their full length *)
IF pulseOn AND tCur - pulseAt >= Data.set.pulseTime THEN
  pulseOn := FALSE;
END_IF;
IF cycleOn AND tCur - cycleAt >= Data.set.powerOffTime THEN
  cycleOn := FALSE;
END_IF;
RestartModem := pulseOn;
PowerCycle := cycleOn;
RebootReq := rebooting AND tCur - rebootAt >= Data.set.rebootSaveWait;
LinkDown := down;
Data.sts.linkOk := NOT down;

(* the next step and the time to it *)
Data.sts.nextStep := 0;
tNext := T#0s;
IF down AND NOT rebooting THEN
  IF NOT done1 AND Data.set.restartAfter > T#0s THEN
    Data.sts.nextStep := 1;
    tNext := Data.set.restartAfter - Data.det.downFor;
  ELSIF NOT done2 AND Data.set.powerCycleAfter > T#0s THEN
    Data.sts.nextStep := 2;
    tNext := Data.set.powerCycleAfter - Data.det.downFor;
  ELSIF NOT done3 AND Data.set.rebootAfter > T#0s AND Data.sts.rebootsToday < Data.set.maxRebootsPerDay
        AND NOT Data.sts.rebootPending THEN
    Data.sts.nextStep := 3;
    tNext := Data.set.rebootAfter - Data.det.downFor;
  ELSIF stepsDone AND backoff > T#0s THEN
    IF Data.set.powerCycleAfter > T#0s THEN
      Data.sts.nextStep := 2;
    ELSE
      Data.sts.nextStep := 1;
    END_IF;
    tNext := backoff - (tCur - lastAt);
  END_IF;
END_IF;
IF tNext < T#0s THEN
  tNext := T#0s;
END_IF;
Data.det.timeLeft := tNext;

(* status *)
IF NOT Enable THEN
  sc := UT_ST_LINK_NOT_USED;
ELSIF NOT down THEN
  sc := UT_ST_LINK_OK;
ELSIF rebooting THEN
  sc := UT_ST_LINK_REBOOTING;
ELSIF Data.sts.rebootPending THEN
  sc := UT_ST_LINK_REBOOT_WAITS;
ELSIF Data.sts.nextStep = 3 THEN
  sc := UT_ST_LINK_REBOOT;
ELSIF Data.sts.nextStep = 1 AND NOT stepsDone THEN
  sc := UT_ST_LINK_RESTART;
ELSIF Data.sts.nextStep = 2 AND NOT stepsDone THEN
  sc := UT_ST_LINK_POWER_CYCLE;
ELSIF Data.sts.nextStep > 0 THEN
  sc := UT_ST_LINK_RETRY;
ELSE
  sc := UT_ST_LINK_NO_STEPS;
END_IF;
IF NOT shown OR sc <> Data.sts.statusCode THEN
  shown := TRUE;
  Data.sts.statusText := UT_STATUS_TEXT(sc, UT_F_NONE);
END_IF;
Data.sts.statusCode := sc;
Warning := LinkDown OR NOT setOk;
Data.sts.ne107 := UT_NE107_RUN(Fault := FALSE, Check := FALSE, OutOfSpec := Warning, Maint := FALSE);

END_FUNCTION_BLOCK