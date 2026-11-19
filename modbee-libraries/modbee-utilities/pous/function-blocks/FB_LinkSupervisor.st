(* FB_LinkSupervisor — escalating recovery of a remote site's comms link.
bLinkGood comes from whatever checks the link (an FB_Watchdog on the SCADA heartbeat, the modem's connected flag).
While it is FALSE the supervisor steps up, each step optional (its time 0 = off), timed from when the link went
down (or from power-up, if it is down then):
  tModemRestartAfter     (30 s)  bRestartModem for tModemRestartPulseLength
  tModemPowerCycleAfter  (5 min) bPowerCycleModem for tModemPowerOffTime
  tControllerRebootAfter      (off)   ONE controlled reboot of the controller: bRebootRequest until it reboots
After those the modem is tried again with a back-off: the first retry tModemRestartAfter after the last step
(tModemPowerCycleAfter if the restart step is off), each wait twice the one before, up to tMaxWaitBetweenRetries (10 min). A retry
power cycles the modem (or restarts it, if the power cycle step is off). The back-off starts again once the link
has stayed up for tMaxWaitBetweenRetries.
The reboot happens only while bRebootAllowed (the program vetoes it while equipment runs; it waits and reboots
once allowed, in the same outage), and at most nMaxRebootsPerDay times a day. The count is kept over the reboot
itself (and any power cut), so a dead link can never make the controller reboot in a loop: it is counted and kept
first; bRebootRequest follows tSaveBeforeReboot later. With a set dtLocalTime (local time, 2000 or later) the count starts
again at each date change; without one it starts again tRebootCountWindow (24 h) of running time after the first counted
reboot (a rolling window, kept over reboots, saved in 24 steps; time switched off does not count). bResetReboots /
bCmdResetReboots sets the count to 0. Not in use (bEnable FALSE): nothing is done.
Outputs: wire bRestartModem to the modem block's restart, bPowerCycleModem to the relay or HAT power feeding the modem
(TRUE = off), bRebootRequest to the controller's reboot. Settings are kept (a retained last-good copy, a bad write put
back). *)

FUNCTION_BLOCK FB_LinkSupervisor EXTENDS FB_Object
  VAR_INPUT
    bLinkGood : BOOL; (* the link works (heartbeat seen, modem connected) *)
    bEnable : BOOL := TRUE; (* the link is in use *)
    bRebootAllowed : BOOL; (* "nothing running, no lock-out": a reboot may happen *)
    dtLocalTime : DT; (* local time, for the reboots-per-day count (unset: no date change) *)
    bResetReboots : BOOL R_EDGE; (* the reboot count to 0 *)
    refData : REFERENCE TO ST_LinkSupervisorData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bRestartModem : BOOL; (* TRUE for tModemRestartPulseLength: restart the modem *)
    bPowerCycleModem : BOOL; (* TRUE for tModemPowerOffTime: switch the modem's power off *)
    bRebootRequest : BOOL; (* reboot the controller (held until it does) *)
    bLinkDown : BOOL; (* the link is down *)
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


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_LinkSupervisorSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tModemRestartAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tModemPowerCycleAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tControllerRebootAfter >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tModemRestartPulseLength >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tModemPowerOffTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tMaxWaitBetweenRetries >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nMaxRebootsPerDay >= 0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tSaveBeforeReboot >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tRebootCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_LinkSupervisorSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
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
  refData.sts.nRebootCountToday := nSavedReboots;
  tUpAt := tNow;
  tWinBase := tNow;
  bDown := FALSE;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
bLinkIn := bLinkGood OR NOT bEnable;   (* not in use: nothing to recover *)
IF refData.set.tModemRestartAfter > T#0s THEN
  tFirstWait := refData.set.tModemRestartAfter;
ELSE
  tFirstWait := refData.set.tModemPowerCycleAfter;
END_IF;

(* the HMI reset of the reboot count *)
bCmd := refData.bCmdResetReboots;
refData.bCmdResetReboots := FALSE;
IF (bCmd AND NOT bCmdPrev) OR bResetReboots THEN
  refData.sts.nRebootCountToday := 0;
  nSavedReboots := 0;
  tSavedWin := T#0s;
  tWinBase := tNow;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bCmdPrev := bCmd;

(* the reboot count: per day of dtLocalTime, or without a set clock a rolling tRebootCountWindow of running time *)
tWin := refData.set.tRebootCountWindow;
IF tWin <= T#0s THEN
  tWin := T#24h;                  (* not a usable window: the default *)
END_IF;
tWinStep := tWin / 24;
IF tWinStep <= T#0s THEN
  tWinStep := T#1ms;
END_IF;
nSecs := DT_TO_LINT(dtLocalTime);
bClockOk := nSecs >= 946684800;   (* 2000-01-01 *)
nDayNo := nSecs / 86400;
refData.sts.tRebootCountResetTimeLeft := T#0s;
IF bClockOk THEN
  IF nDayNo <> nSavedDay THEN
    nSavedDay := nDayNo;
    refData.sts.nRebootCountToday := 0;
    nSavedReboots := 0;
  END_IF;
ELSIF refData.sts.nRebootCountToday > 0 THEN
  IF tNow - tWinBase >= tWinStep THEN
    tSavedWin := tSavedWin + tWinStep;   (* saved a step at a time: rare writes *)
    tWinBase := tWinBase + tWinStep;
  END_IF;
  IF tSavedWin + (tNow - tWinBase) >= tWin THEN
    refData.sts.nRebootCountToday := 0;      (* the window is over: the count starts again *)
    nSavedReboots := 0;
    tSavedWin := T#0s;
  ELSE
    refData.sts.tRebootCountResetTimeLeft := tWin - (tSavedWin + (tNow - tWinBase));
  END_IF;
END_IF;
IF refData.sts.nRebootCountToday = 0 OR bClockOk THEN
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
  IF tNow - tUpAt >= refData.set.tMaxWaitBetweenRetries OR tBackoff <= T#0s THEN
    tBackoff := tFirstWait;       (* up long enough: the back-off starts again *)
  END_IF;
ELSIF bLinkIn AND bDown THEN
  bDown := FALSE;
  tUpAt := tNow;
  refData.sts.tLastOutageTime := tNow - tDownAt;
  refData.sts.nOutageCount := refData.sts.nOutageCount + 1;
  bRebooting := FALSE;
  refData.sts.bRebootPending := FALSE;
END_IF;

(* the steps *)
bStepsDone := FALSE;
IF bDown THEN
  refData.sts.tCurrentOutageTime := tNow - tDownAt;
  IF NOT bDone1 AND refData.set.tModemRestartAfter > T#0s AND refData.sts.tCurrentOutageTime >= refData.set.tModemRestartAfter THEN
    bDone1 := TRUE;
    bPulseOn := TRUE;
    tPulseAt := tNow;
    tLastAt := tNow;
    refData.sts.nModemRestartCount := refData.sts.nModemRestartCount + 1;
  END_IF;
  IF NOT bDone2 AND refData.set.tModemPowerCycleAfter > T#0s AND refData.sts.tCurrentOutageTime >= refData.set.tModemPowerCycleAfter THEN
    bDone2 := TRUE;
    bCycleOn := TRUE;
    tCycleAt := tNow;
    tLastAt := tNow;
    refData.sts.nModemPowerCycleCount := refData.sts.nModemPowerCycleCount + 1;
  END_IF;
  IF NOT bDone3 AND refData.set.tControllerRebootAfter > T#0s AND refData.sts.tCurrentOutageTime >= refData.set.tControllerRebootAfter THEN
    IF refData.sts.nRebootCountToday >= refData.set.nMaxRebootsPerDay THEN
      bDone3 := TRUE;             (* the day's limit: no reboot *)
      refData.sts.bRebootPending := FALSE;
    ELSIF bRebootAllowed THEN
      bDone3 := TRUE;
      refData.sts.bRebootPending := FALSE;
      refData.sts.nRebootCountToday := refData.sts.nRebootCountToday + 1;
      nSavedReboots := refData.sts.nRebootCountToday;   (* kept before the reboot is asked for *)
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
  bStepsDone := (bDone1 OR refData.set.tModemRestartAfter <= T#0s) AND (bDone2 OR refData.set.tModemPowerCycleAfter <= T#0s)
                AND (bDone1 OR bDone2);
  IF bStepsDone AND tBackoff > T#0s AND tNow - tLastAt >= tBackoff THEN
    tLastAt := tNow;
    IF refData.set.tModemPowerCycleAfter > T#0s THEN
      bCycleOn := TRUE;
      tCycleAt := tNow;
      refData.sts.nModemPowerCycleCount := refData.sts.nModemPowerCycleCount + 1;
    ELSE
      bPulseOn := TRUE;
      tPulseAt := tNow;
      refData.sts.nModemRestartCount := refData.sts.nModemRestartCount + 1;
    END_IF;
    IF tBackoff >= refData.set.tMaxWaitBetweenRetries / 2 THEN
      tBackoff := refData.set.tMaxWaitBetweenRetries;
    ELSE
      tBackoff := tBackoff + tBackoff;
    END_IF;
  END_IF;
ELSE
  refData.sts.tCurrentOutageTime := T#0s;
END_IF;

(* the outputs: pulses run their full length *)
IF bPulseOn AND tNow - tPulseAt >= refData.set.tModemRestartPulseLength THEN
  bPulseOn := FALSE;
END_IF;
IF bCycleOn AND tNow - tCycleAt >= refData.set.tModemPowerOffTime THEN
  bCycleOn := FALSE;
END_IF;
bRestartModem := bPulseOn;
bPowerCycleModem := bCycleOn;
bRebootRequest := bRebooting AND tNow - tRebootAt >= refData.set.tSaveBeforeReboot;
bLinkDown := bDown;
refData.sts.bLinkGood := NOT bDown;

(* the next step and the time to it *)
refData.sts.nNextRecoveryStep := 0;
tNext := T#0s;
IF bDown AND NOT bRebooting THEN
  IF NOT bDone1 AND refData.set.tModemRestartAfter > T#0s THEN
    refData.sts.nNextRecoveryStep := 1;
    tNext := refData.set.tModemRestartAfter - refData.sts.tCurrentOutageTime;
  ELSIF NOT bDone2 AND refData.set.tModemPowerCycleAfter > T#0s THEN
    refData.sts.nNextRecoveryStep := 2;
    tNext := refData.set.tModemPowerCycleAfter - refData.sts.tCurrentOutageTime;
  ELSIF NOT bDone3 AND refData.set.tControllerRebootAfter > T#0s AND refData.sts.nRebootCountToday < refData.set.nMaxRebootsPerDay
        AND NOT refData.sts.bRebootPending THEN
    refData.sts.nNextRecoveryStep := 3;
    tNext := refData.set.tControllerRebootAfter - refData.sts.tCurrentOutageTime;
  ELSIF bStepsDone AND tBackoff > T#0s THEN
    IF refData.set.tModemPowerCycleAfter > T#0s THEN
      refData.sts.nNextRecoveryStep := 2;
    ELSE
      refData.sts.nNextRecoveryStep := 1;
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
bWarning := NOT bError AND (bDown OR refData.sts.bRebootPending OR refData.sts.bSettingRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bDown THEN
  eErrorId := E_UtError.LinkLost;
ELSIF refData.sts.bSettingRefused THEN
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