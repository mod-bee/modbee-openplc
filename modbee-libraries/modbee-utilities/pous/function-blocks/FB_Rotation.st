(* FB_Rotation — shaft / belt speed monitor from a proximity sensor on the driven shaft, pulley or target wheel: the
speed, a stall (no pulse for set.tStalledAfterNoPulse while running: the sensor stuck on or stuck off, a broken coupling or
belt), underspeed (belt slip, overload), overspeed, and pulses while the machine is stopped (a faulty sensor, or
something else turning it).
A part of its motor (ipOwner, optional): a trip stops the motor through its part list. Without an owner it is a
plain monitor: wire bNoFaultTripped where it is needed.
Running: the bMachineRunning pin, or with an owner its run command (either).

Speed, in set.eSpeedUnit, from the pulse rate f (pulses per second):
  Rpm          rpm   = 60 x f / nPulsesPerRevolution  (the default)
  RevPerSec    rev/s = f / nPulsesPerRevolution       (Hz of the shaft)
  MetrePerMin  m/min = 60 x f x fDistancePerPulse  (belt / chain line speed)
  MetrePerSec  m/s   = f x fDistancePerPulse
fUnderspeedBelow, fOverspeedAbove and the speed are all in eSpeedUnit. f is measured from the first to the last pulse of a
window at least set.tMeasureSpeedOver long (one pulse period when the shaft is slower). Between pulses f falls as
1 / (time since the last pulse) once that is longer than the last period, so a stopping shaft is seen slowing
down; after tStalledAfterNoPulse with no pulse it is 0. A pulse is seen once per scan: the fastest measurable rate is
1 / (2 x scan time) pulses per second; sts.bPulsesTooFast (a warning, PulsesTooFast) for 5 s whenever pulses arrive at
that limit.
An unknown eSpeedUnit, or a line speed with fDistancePerPulse not above 0 (or not a number): sts.bSpeedUnitBad, a warning
(BadSetting); the speed reads 0 and the under / over speed checks are off until it is fixed. The stall and
sensor checks do not need the unit and still act.

Protections (ST_ProtectionSet, F_Protect):
  stStallFault       Trip, Manual  running, past tMaskAfterStart and tStalledAfterNoPulse, no pulse for tStalledAfterNoPulse   -> Stall
  stUnderspeedFault  Warn, Auto    running, past tMaskAfterStart, below fUnderspeedBelow (> 0) for tSpeedFaultDelay   -> Underspeed
  stOverspeedFault   Off           above fOverspeedAbove (> 0) for tSpeedFaultDelay                               -> Overspeed
  stPulsesWhileStoppedFault      Warn, Auto    pulses while stopped, tCoastDownTime after the stop                     -> PulsesWhileStopped
A trip or a signal acts on the owner (Trip / Stop); a warning shows on it. Reset: bResetFaults (rising edge), the
record's bCmdResetFaults (once per write), the owner's reset, the system reset.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back; a set
never good is BadSetting (bError) and the checks go on with it (nPulsesPerRevolution below 1 counts as 1).
Its rung stopping while a protection acts is PartLost on its owner. *)

FUNCTION_BLOCK FB_Rotation EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    bProximitySensor : BOOL := FALSE; (* the proximity sensor *)
    bMachineRunning : BOOL; (* the machine runs (with an owner, its run command counts too) *)
    bResetFaults : BOOL R_EDGE; (* reset a latched fault *)
    ipOwner : I_PartOwner; (* optional: the motor it protects *)
    refData : REFERENCE TO ST_RotationData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bNoFaultTripped : BOOL; (* no protection tripped *)
    bRotating : BOOL; (* pulses being seen *)
    fSpeed : REAL; (* in set.eSpeedUnit (default rpm) *)
  END_VAR
  VAR RETAIN
    stKept : ST_RotationSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL; (* the rung ran since the owner's last Evaluate *)
    bOwnerRun : BOOL; (* the owner's run command (Evaluate) *)
    bOwnerReset : BOOL; (* the owner's reset, taken on the next call *)
    tPrev : TIME;
    bSensorPrev : BOOL;
    bRunPrev : BOOL;
    bCmdSeen : BOOL;
    bEdgeSeen : BOOL;
    tLastEdge : TIME;
    tWinStart : TIME;
    nWinEdges : DINT;
    tRunStart : TIME;
    tStopAt : TIME;
    tFastUntil : TIME;
    tBelowSince : TIME;
    tAboveSince : TIME;
    fMeasured : REAL; (* the pulse rate of the last window, pulses / s *)
    stWStall : ST_ProtectionWork;
    stWUnder : ST_ProtectionWork;
    stWOver : ST_ProtectionWork;
    stWSensor : ST_ProtectionWork;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bRun : BOOL;
    tStep : TIME;
    nPpr : INT;
    fK : REAL; (* speed units per (pulse / s) *)
    bUnitBad : BOOL;
    tSince : TIME;
    fShown : REAL;
    fDecay : REAL;
    bPastStart : BOOL;
    bBelow : BOOL;
    bAbove : BOOL;
    bResetReq : BOOL;
    bAnyTrip : BOOL;
    bAnyWarn : BOOL;
    tLeft : TIME;
  END_VAR


(* the settings are usable *)
METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_RotationSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.nPulsesPerRevolution >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tMaskAfterStart >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tStalledAfterNoPulse > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.fUnderspeedBelow >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fOverspeedAbove >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.tSpeedFaultDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tMeasureSpeedOver >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tCoastDownTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stStallFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stStallFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stStallFault.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stUnderspeedFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stUnderspeedFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stUnderspeedFault.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stOverspeedFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stOverspeedFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stOverspeedFault.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stPulsesWhileStoppedFault.tTripDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stPulsesWhileStoppedFault.tAutoRecoverAfter >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stPulsesWhileStoppedFault.nMaxRetriesBeforeLockout >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_RotationSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

(* the first acting protection: its error, stall > overspeed > underspeed > sensor *)
METHOD PRIVATE ActingId : E_UtError
  VAR_INPUT
    bTrips : BOOL;                // TRUE: among the trips / signals, FALSE: among the warnings
  END_VAR
  IF (bTrips AND (stWStall.bTripping OR stWStall.bSignalling)) OR (NOT bTrips AND stWStall.bWarning) THEN
    ActingId := E_UtError.Stall;
  ELSIF (bTrips AND (stWOver.bTripping OR stWOver.bSignalling)) OR (NOT bTrips AND stWOver.bWarning) THEN
    ActingId := E_UtError.Overspeed;
  ELSIF (bTrips AND (stWUnder.bTripping OR stWUnder.bSignalling)) OR (NOT bTrips AND stWUnder.bWarning) THEN
    ActingId := E_UtError.Underspeed;
  ELSE
    ActingId := E_UtError.PulsesWhileStopped;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bOwnerRunCommand : BOOL;    // the owner is running (its run command)
    bResetRequest : BOOL;    // the owner's reset request this scan
    bStartMaskOn : BOOL;    // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;    // the error this part stands for (when it warns or trips)
  END_VAR
  bOwnerRun := bOwnerRunCommand;
  IF bResetRequest THEN
    bOwnerReset := TRUE;
  END_IF;
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND (refData.sts.stStallFault.eFaultState <> E_ProtState.Clear
                      OR refData.sts.stUnderspeedFault.eFaultState <> E_ProtState.Clear
                      OR refData.sts.stOverspeedFault.eFaultState <> E_ProtState.Clear
                      OR refData.sts.stPulsesWhileStoppedFault.eFaultState <> E_ProtState.Clear) THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  IF stWStall.bTripping OR stWOver.bTripping OR stWUnder.bTripping OR stWSensor.bTripping THEN
    eErrorId := ActingId(bTrips := TRUE);
    Evaluate := E_PartAction.Trip;
  ELSIF stWStall.bSignalling OR stWOver.bSignalling OR stWUnder.bSignalling OR stWSensor.bSignalling THEN
    eErrorId := ActingId(bTrips := TRUE);
    Evaluate := E_PartAction.Stop;
  ELSIF stWStall.bWarning OR stWOver.bWarning OR stWUnder.bWarning OR stWSensor.bWarning THEN
    eErrorId := ActingId(bTrips := FALSE);
    Evaluate := E_PartAction.Warn;
  ELSE
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNextPart : I_Part;    // the next part in the owner's chain
  END_VAR
  THIS^.ipNext := ipNextPart;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bNoFaultTripped := FALSE;
  bRotating := FALSE;
  fSpeed := 0.0;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
bRun := bMachineRunning OR (ipOwner <> NULL AND bOwnerRun);
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  tPrev := tNow;
  tRunStart := tNow;
  tStopAt := tNow;
  tFastUntil := tNow;
  bSensorPrev := bProximitySensor;
  bRunPrev := bRun;
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
IF NOT bAdded AND ipOwner <> NULL THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
tStep := tNow - tPrev;
tPrev := tNow;
IF tStep < T#0s THEN
  tStep := T#0s;
END_IF;

(* the unit *)
nPpr := MAX(refData.set.nPulsesPerRevolution, 1);
CASE refData.set.eSpeedUnit OF
  E_SpeedUnit.Rpm: fK := 60.0 / INT_TO_REAL(nPpr);
  E_SpeedUnit.RevPerSec: fK := 1.0 / INT_TO_REAL(nPpr);
  E_SpeedUnit.MetrePerMin: fK := 60.0 * refData.set.fDistancePerPulse;
  E_SpeedUnit.MetrePerSec: fK := refData.set.fDistancePerPulse;
ELSE
  fK := 0.0;
END_CASE;
bUnitBad := NOT (fK > 0.0 AND fK <= REAL#3.4E38);   (* NaN fails too *)

IF bRun AND NOT bRunPrev THEN
  tRunStart := tNow;
ELSIF bRunPrev AND NOT bRun THEN
  tStopAt := tNow;
END_IF;
bRunPrev := bRun;

(* a pulse *)
IF bProximitySensor AND NOT bSensorPrev THEN
  IF bEdgeSeen AND tNow - tLastEdge <= tStep + tStep + tStep / 2 AND tStep > T#0s THEN
    tFastUntil := tNow + T#5s;    (* at the limit: one pulse every two scans *)
  END_IF;
  IF NOT bEdgeSeen OR tNow - tLastEdge >= refData.set.tStalledAfterNoPulse THEN
    tWinStart := tNow;            (* the first pulse after a stop: start measuring *)
    nWinEdges := 0;
    fMeasured := 0.0;
  ELSE
    refData.det.tTimeBetweenPulses := tNow - tLastEdge;
    nWinEdges := nWinEdges + 1;
    IF tNow - tWinStart >= refData.set.tMeasureSpeedOver THEN
      fMeasured := 1000.0 * DINT_TO_REAL(nWinEdges) / LINT_TO_REAL(TIME_TO_LINT(tNow - tWinStart));
      tWinStart := tNow;
      nWinEdges := 0;
    END_IF;
  END_IF;
  bEdgeSeen := TRUE;
  tLastEdge := tNow;
END_IF;
bSensorPrev := bProximitySensor;
refData.sts.bPulsesTooFast := tNow < tFastUntil;

(* the speed shown: falls while no pulse comes, 0 after tStalledAfterNoPulse *)
fShown := fMeasured;
IF bEdgeSeen THEN
  tSince := tNow - tLastEdge;
  IF tSince >= refData.set.tStalledAfterNoPulse THEN
    fShown := 0.0;
    fMeasured := 0.0;
  ELSIF tSince > refData.det.tTimeBetweenPulses AND tSince > T#0s THEN
    fDecay := 1000.0 / LINT_TO_REAL(TIME_TO_LINT(tSince));
    IF fDecay < fShown THEN
      fShown := fDecay;
    END_IF;
  END_IF;
END_IF;
IF bUnitBad THEN
  fShown := 0.0;
ELSE
  fShown := fShown * fK;          (* pulses / s -> the speed unit *)
END_IF;
bRotating := bEdgeSeen AND tNow - tLastEdge < refData.set.tStalledAfterNoPulse;

(* the conditions *)
bPastStart := bRun AND tNow - tRunStart >= refData.set.tMaskAfterStart;
bBelow := bPastStart AND NOT bUnitBad AND refData.set.fUnderspeedBelow > 0.0 AND fShown < refData.set.fUnderspeedBelow;
IF NOT bBelow THEN
  tBelowSince := tNow;
END_IF;
bAbove := NOT bUnitBad AND refData.set.fOverspeedAbove > 0.0 AND fShown > refData.set.fOverspeedAbove;
IF NOT bAbove THEN
  tAboveSince := tNow;
END_IF;

(* the resets: the pin, the record (once per write), the owner, the system *)
bResetReq := bResetFaults OR (refData.bCmdResetFaults AND NOT bCmdSeen) OR bOwnerReset OR SystemReset();
bCmdSeen := refData.bCmdResetFaults;
refData.bCmdResetFaults := FALSE;
bOwnerReset := FALSE;
IF bResetReq THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

F_Protect(tNow := tNow, bConditionPresent := bPastStart AND (NOT bEdgeSeen OR tNow - tLastEdge >= refData.set.tStalledAfterNoPulse)
                                  AND tNow - tRunStart >= refData.set.tStalledAfterNoPulse,
          bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stStallFault,
          stStatus := refData.sts.stStallFault, stWorking := stWStall);
F_Protect(tNow := tNow, bConditionPresent := bBelow AND tNow - tBelowSince >= refData.set.tSpeedFaultDelay,
          bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stUnderspeedFault,
          stStatus := refData.sts.stUnderspeedFault, stWorking := stWUnder);
F_Protect(tNow := tNow, bConditionPresent := bAbove AND tNow - tAboveSince >= refData.set.tSpeedFaultDelay,
          bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stOverspeedFault,
          stStatus := refData.sts.stOverspeedFault, stWorking := stWOver);
F_Protect(tNow := tNow, bConditionPresent := NOT bRun AND bRotating AND tNow - tStopAt >= refData.set.tCoastDownTime
                                  AND tLastEdge - tStopAt >= refData.set.tCoastDownTime,
          bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow, stSettings := refData.set.stPulsesWhileStoppedFault,
          stStatus := refData.sts.stPulsesWhileStoppedFault, stWorking := stWSensor);

bAnyTrip := stWStall.bTripping OR stWUnder.bTripping OR stWOver.bTripping OR stWSensor.bTripping;
bAnyWarn := stWStall.bWarning OR stWUnder.bWarning OR stWOver.bWarning OR stWSensor.bWarning;
bNoFaultTripped := NOT bAnyTrip;
fSpeed := fShown;
refData.sts.fSpeed := fShown;
refData.sts.bRotating := bRotating;
refData.sts.bSpeedUnitBad := bUnitBad;

(* the time left: the acting protection's, else the start delay's *)
tLeft := T#0s;
IF bAnyTrip OR bAnyWarn THEN
  CASE ActingId(bTrips := bAnyTrip) OF
    E_UtError.Stall: tLeft := refData.sts.stStallFault.tTimeLeft;
    E_UtError.Overspeed: tLeft := refData.sts.stOverspeedFault.tTimeLeft;
    E_UtError.Underspeed: tLeft := refData.sts.stUnderspeedFault.tTimeLeft;
  ELSE
    tLeft := refData.sts.stPulsesWhileStoppedFault.tTimeLeft;
  END_CASE;
ELSIF bRun AND NOT bPastStart THEN
  tLeft := refData.set.tMaskAfterStart - (tNow - tRunStart);
END_IF;
IF tLeft < T#0s THEN
  tLeft := T#0s;
END_IF;
refData.det.tTimeLeft := tLeft;

bError := bAnyTrip OR NOT bOk;
bWarning := NOT bError AND (bAnyWarn OR bUnitBad OR refData.sts.bPulsesTooFast OR refData.sts.bSettingRefused
                            OR stWStall.bSettingBad OR stWUnder.bSettingBad OR stWOver.bSettingBad
                            OR stWSensor.bSettingBad);
IF bAnyTrip THEN
  eErrorId := ActingId(bTrips := TRUE);
ELSIF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bAnyWarn THEN
  eErrorId := ActingId(bTrips := FALSE);
ELSIF bUnitBad OR stWStall.bSettingBad OR stWUnder.bSettingBad OR stWOver.bSettingBad OR stWSensor.bSettingBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bPulsesTooFast THEN
  eErrorId := E_UtError.PulsesTooFast;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bRun AND NOT bPastStart THEN
  eState := E_State.Starting;
ELSIF bRun THEN
  eState := E_State.Running;
ELSIF bRotating THEN
  eState := E_State.Stopping;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK