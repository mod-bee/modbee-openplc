(* FB_LinkSupervisor — escalating recovery of a remote site's comms link (src-v2 UT_LINK_SUPERVISOR, the same rules).
bLinkOk comes from whatever checks the link (an FB_Watchdog on the SCADA heartbeat, the modem's connected flag).
While it is FALSE the supervisor steps up, each step optional (its time 0 = off), timed from when the link went
down (or from power-up, if it is down then):
  tRestartAfter     (30 s)  bRestartModem for tPulse
  tPowerCycleAfter  (5 min) bPowerCycle for tPowerOff
  tRebootAfter      (off)   ONE controlled reboot of the controller: bRebootReq until it reboots
After those the modem is tried again with a back-off: the first retry tRestartAfter after the last step
(tPowerCycleAfter if the restart step is off), each wait twice the one before, up to tMaxBackoff (10 min). A retry
power cycles the modem (or restarts it, if the power cycle step is off). The back-off starts again once the link
has stayed up for tMaxBackoff.
The reboot happens only while bRebootAllowed (the program vetoes it while equipment runs; it waits and reboots
once allowed, in the same outage), and at most nMaxRebootsPerDay times a day. The count is kept over the reboot
itself (and any power cut), so a dead link can never make the controller reboot in a loop: it is counted and kept
first; bRebootReq follows tRebootSaveWait later. With a set dtClock (local time, 2000 or later) the count starts
again at each date change; without one it starts again tCountWindow (24 h) of running time after the first counted
reboot (a rolling window, kept over reboots, saved in 24 steps; time switched off does not count). bResetReboots /
bCmdResetReboots sets the count to 0. Not in use (bEnable FALSE): nothing is done.
Outputs: wire bRestartModem to the modem block's restart, bPowerCycle to the relay or HAT power feeding the modem
(TRUE = off), bRebootReq to the controller's reboot. Settings are kept (a retained last-good copy, a bad write put
back). *)

FUNCTION_BLOCK FB_LinkSupervisor EXTENDS FB_Object
  VAR_INPUT
    bLinkOk : BOOL; (* the link works (heartbeat seen, modem connected) *)
    bEnable : BOOL := TRUE; (* the link is in use *)
    bRebootAllowed : BOOL; (* "nothing running, no lock-out": a reboot may happen *)
    dtClock : DT; (* local time, for the reboots-per-day count (unset: no date change) *)
    bResetReboots : BOOL R_EDGE; (* the reboot count to 0 *)
    refData : REFERENCE TO ST_LinkSupervisorData;
  END_VAR
  VAR_OUTPUT
    bRestartModem : BOOL; (* TRUE for tPulse: restart the modem *)
    bPowerCycle : BOOL; (* TRUE for tPowerOff: switch the modem's power off *)
    bRebootReq : BOOL; (* reboot the controller (held until it does) *)
    bLinkDown : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_LinkSupervisorSet;
    nKeptLayout : UINT;
    nSavedReboots : INT; (* the reboot count and the day it belongs to (a safety count, not a live value) *)
    nSavedDay : LINT;
    tSavedWin : TIME; (* no clock: running time since the first counted reboot (saved in steps) *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bDown : BOOL;
    tDownAt : TIME;
    tUpAt : TIME;
    bDone1 : BOOL; (* this outage: modem restarted *)
    bDone2 : BOOL; (* power cycled *)
    bDone3 : BOOL; (* the reboot step done (or skipped: the limit) *)
    bRebooting : BOOL;
    tRebootAt : TIME;
    tLastAt : TIME; (* the last restart / power cycle (the back-off from here) *)
    tBackoff : TIME;
    tPulseAt : TIME;
    tCycleAt : TIME;
    bPulseOn : BOOL;
    bCycleOn : BOOL;
    bCmdPrev : BOOL;
    tWinBase : TIME; (* no clock: TIME() the unsaved part of the window counts from *)
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bLinkIn : BOOL;
    tFirstWait : TIME;
    bCmd : BOOL;
    nSecs : LINT;
    nDayNo : LINT;
    bClockOk : BOOL;
    tWin : TIME;
    tWinStep : TIME;
    bStepsDone : BOOL;
    tNext : TIME;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_LinkSupervisorSet;
  END_VAR
  SetOk := stS.tRestartAfter >= T#0s AND stS.tPowerCycleAfter >= T#0s AND stS.tRebootAfter >= T#0s
           AND stS.tPulse >= T#0s AND stS.tPowerOff >= T#0s AND stS.tMaxBackoff >= T#0s
           AND stS.nMaxRebootsPerDay >= 0 AND stS.tRebootSaveWait >= T#0s AND stS.tCountWindow >= T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  refData.sts.nRebootsToday := nSavedReboots;
  tUpAt := tNow;
  tWinBase := tNow;
  bDown := FALSE;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;
bLinkIn := bLinkOk OR NOT bEnable;   (* not in use: nothing to recover *)
IF refData.set.tRestartAfter > T#0s THEN
  tFirstWait := refData.set.tRestartAfter;
ELSE
  tFirstWait := refData.set.tPowerCycleAfter;
END_IF;

(* the HMI reset of the reboot count *)
bCmd := refData.bCmdResetReboots;
refData.bCmdResetReboots := FALSE;
IF (bCmd AND NOT bCmdPrev) OR bResetReboots THEN
  refData.sts.nRebootsToday := 0;
  nSavedReboots := 0;
  tSavedWin := T#0s;
  tWinBase := tNow;
  refData.sts.bRefused := FALSE;
END_IF;
bCmdPrev := bCmd;

(* the reboot count: per day of dtClock, or without a set clock a rolling tCountWindow of running time *)
tWin := refData.set.tCountWindow;
IF tWin <= T#0s THEN
  tWin := T#24h;                  (* not a usable window: the default *)
END_IF;
tWinStep := tWin / 24;
IF tWinStep <= T#0s THEN
  tWinStep := T#1ms;
END_IF;
nSecs := DT_TO_LINT(dtClock);
bClockOk := nSecs >= 946684800;   (* 2000-01-01 *)
nDayNo := nSecs / 86400;
refData.sts.tCountResetIn := T#0s;
IF bClockOk THEN
  IF nDayNo <> nSavedDay THEN
    nSavedDay := nDayNo;
    refData.sts.nRebootsToday := 0;
    nSavedReboots := 0;
  END_IF;
ELSIF refData.sts.nRebootsToday > 0 THEN
  IF tNow - tWinBase >= tWinStep THEN
    tSavedWin := tSavedWin + tWinStep;   (* saved a step at a time: rare writes *)
    tWinBase := tWinBase + tWinStep;
  END_IF;
  IF tSavedWin + (tNow - tWinBase) >= tWin THEN
    refData.sts.nRebootsToday := 0;      (* the window is over: the count starts again *)
    nSavedReboots := 0;
    tSavedWin := T#0s;
  ELSE
    refData.sts.tCountResetIn := tWin - (tSavedWin + (tNow - tWinBase));
  END_IF;
END_IF;
IF refData.sts.nRebootsToday = 0 OR bClockOk THEN
  tWinBase := tNow;               (* the window starts at the first counted reboot *)
  IF tSavedWin <> T#0s THEN
    tSavedWin := T#0s;
  END_IF;
END_IF;

(* an outage starts and ends *)
IF NOT bLinkIn AND NOT bDown THEN
  bDown := TRUE;
  tDownAt := tNow;
  bDone1 := FALSE;
  bDone2 := FALSE;
  bDone3 := FALSE;
  IF tNow - tUpAt >= refData.set.tMaxBackoff OR tBackoff <= T#0s THEN
    tBackoff := tFirstWait;       (* up long enough: the back-off starts again *)
  END_IF;
ELSIF bLinkIn AND bDown THEN
  bDown := FALSE;
  tUpAt := tNow;
  refData.sts.tLastDownFor := tNow - tDownAt;
  refData.sts.nOutages := refData.sts.nOutages + 1;
  bRebooting := FALSE;
  refData.sts.bRebootPending := FALSE;
END_IF;

(* the steps *)
bStepsDone := FALSE;
IF bDown THEN
  refData.sts.tDownFor := tNow - tDownAt;
  IF NOT bDone1 AND refData.set.tRestartAfter > T#0s AND refData.sts.tDownFor >= refData.set.tRestartAfter THEN
    bDone1 := TRUE;
    bPulseOn := TRUE;
    tPulseAt := tNow;
    tLastAt := tNow;
    refData.sts.nRestarts := refData.sts.nRestarts + 1;
  END_IF;
  IF NOT bDone2 AND refData.set.tPowerCycleAfter > T#0s AND refData.sts.tDownFor >= refData.set.tPowerCycleAfter THEN
    bDone2 := TRUE;
    bCycleOn := TRUE;
    tCycleAt := tNow;
    tLastAt := tNow;
    refData.sts.nPowerCycles := refData.sts.nPowerCycles + 1;
  END_IF;
  IF NOT bDone3 AND refData.set.tRebootAfter > T#0s AND refData.sts.tDownFor >= refData.set.tRebootAfter THEN
    IF refData.sts.nRebootsToday >= refData.set.nMaxRebootsPerDay THEN
      bDone3 := TRUE;             (* the day's limit: no reboot *)
      refData.sts.bRebootPending := FALSE;
    ELSIF bRebootAllowed THEN
      bDone3 := TRUE;
      refData.sts.bRebootPending := FALSE;
      refData.sts.nRebootsToday := refData.sts.nRebootsToday + 1;
      nSavedReboots := refData.sts.nRebootsToday;   (* kept before the reboot is asked for *)
      IF bClockOk THEN
        nSavedDay := nDayNo;
      END_IF;
      bRebooting := TRUE;
      tRebootAt := tNow;
    ELSE
      refData.sts.bRebootPending := TRUE;
    END_IF;
  END_IF;
  (* retries with a back-off once the restart and power cycle steps are past *)
  bStepsDone := (bDone1 OR refData.set.tRestartAfter <= T#0s) AND (bDone2 OR refData.set.tPowerCycleAfter <= T#0s)
                AND (bDone1 OR bDone2);
  IF bStepsDone AND tBackoff > T#0s AND tNow - tLastAt >= tBackoff THEN
    tLastAt := tNow;
    IF refData.set.tPowerCycleAfter > T#0s THEN
      bCycleOn := TRUE;
      tCycleAt := tNow;
      refData.sts.nPowerCycles := refData.sts.nPowerCycles + 1;
    ELSE
      bPulseOn := TRUE;
      tPulseAt := tNow;
      refData.sts.nRestarts := refData.sts.nRestarts + 1;
    END_IF;
    IF tBackoff >= refData.set.tMaxBackoff / 2 THEN
      tBackoff := refData.set.tMaxBackoff;
    ELSE
      tBackoff := tBackoff + tBackoff;
    END_IF;
  END_IF;
ELSE
  refData.sts.tDownFor := T#0s;
END_IF;

(* the outputs: pulses run their full length *)
IF bPulseOn AND tNow - tPulseAt >= refData.set.tPulse THEN
  bPulseOn := FALSE;
END_IF;
IF bCycleOn AND tNow - tCycleAt >= refData.set.tPowerOff THEN
  bCycleOn := FALSE;
END_IF;
bRestartModem := bPulseOn;
bPowerCycle := bCycleOn;
bRebootReq := bRebooting AND tNow - tRebootAt >= refData.set.tRebootSaveWait;
bLinkDown := bDown;
refData.sts.bLinkOk := NOT bDown;

(* the next step and the time to it *)
refData.sts.nNextStep := 0;
tNext := T#0s;
IF bDown AND NOT bRebooting THEN
  IF NOT bDone1 AND refData.set.tRestartAfter > T#0s THEN
    refData.sts.nNextStep := 1;
    tNext := refData.set.tRestartAfter - refData.sts.tDownFor;
  ELSIF NOT bDone2 AND refData.set.tPowerCycleAfter > T#0s THEN
    refData.sts.nNextStep := 2;
    tNext := refData.set.tPowerCycleAfter - refData.sts.tDownFor;
  ELSIF NOT bDone3 AND refData.set.tRebootAfter > T#0s AND refData.sts.nRebootsToday < refData.set.nMaxRebootsPerDay
        AND NOT refData.sts.bRebootPending THEN
    refData.sts.nNextStep := 3;
    tNext := refData.set.tRebootAfter - refData.sts.tDownFor;
  ELSIF bStepsDone AND tBackoff > T#0s THEN
    IF refData.set.tPowerCycleAfter > T#0s THEN
      refData.sts.nNextStep := 2;
    ELSE
      refData.sts.nNextStep := 1;
    END_IF;
    tNext := tBackoff - (tNow - tLastAt);
  END_IF;
END_IF;
IF tNext < T#0s THEN
  tNext := T#0s;
END_IF;
refData.sts.tTimeLeft := tNext;

(* errors: the link down is the block's job, a warning *)
bError := NOT bOk;
bWarning := NOT bError AND (bDown OR refData.sts.bRebootPending OR refData.sts.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bDown THEN
  eErrorId := E_UtError.LinkLost;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bEnable THEN
  eState := E_State.Off;
ELSIF bDown THEN
  eState := E_State.Waiting;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK