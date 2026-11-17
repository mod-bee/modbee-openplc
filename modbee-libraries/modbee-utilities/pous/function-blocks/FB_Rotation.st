(* FB_Rotation — shaft / belt speed monitor from a proximity sensor on the driven shaft, pulley or target wheel: the
speed, a stall (no pulse for set.tStallTime while running: the sensor stuck on or stuck off, a broken coupling or
belt), underspeed (belt slip, overload), overspeed, and pulses while the machine is stopped (a faulty sensor, or
something else turning it).
A part of its motor (ipOwner, optional): a trip stops the motor through its part list. Without an owner it is a
plain monitor: wire bHealthy where it is needed.
Running: the bMachineRun pin, or with an owner its run command (either).

Speed, in set.eSpeedUnit, from the pulse rate f (pulses per second):
  Rpm          rpm   = 60 x f / nPulsesPerRev  (the default)
  RevPerSec    rev/s = f / nPulsesPerRev       (Hz of the shaft)
  MetrePerMin  m/min = 60 x f x fDistPerPulse  (belt / chain line speed)
  MetrePerSec  m/s   = f x fDistPerPulse
fMinSpeed, fMaxSpeed and the speed are all in eSpeedUnit. f is measured from the first to the last pulse of a
window at least set.tFilterTime long (one pulse period when the shaft is slower). Between pulses f falls as
1 / (time since the last pulse) once that is longer than the last period, so a stopping shaft is seen slowing
down; after tStallTime with no pulse it is 0. A pulse is seen once per scan: the fastest measurable rate is
1 / (2 x scan time) pulses per second; sts.bTooFast (a warning, PulsesTooFast) for 5 s whenever pulses arrive at
that limit.
An unknown eSpeedUnit, or a line speed with fDistPerPulse not above 0 (or not a number): sts.bUnitBad, a warning
(BadSetting); the speed reads 0 and the under / over speed checks are off until it is fixed. The stall and
sensor checks do not need the unit and still act.

Protections (ST_ProtectionSet, F_Protect):
  stStall       Trip, Manual  running, past tStartDelay and tStallTime, no pulse for tStallTime   -> Stall
  stUnderspeed  Warn, Auto    running, past tStartDelay, below fMinSpeed (> 0) for tSpeedDelay   -> Underspeed
  stOverspeed   Off           above fMaxSpeed (> 0) for tSpeedDelay                               -> Overspeed
  stSensor      Warn, Auto    pulses while stopped, tCoastDown after the stop                     -> PulsesWhileStopped
A trip or a signal acts on the owner (Trip / Stop); a warning shows on it. Reset: bReset (rising edge), the
record's bCmdReset (once per write), the owner's reset, the system reset.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back; a set
never good is BadSetting (bError) and the checks go on with it (nPulsesPerRev below 1 counts as 1).
Its rung stopping while a protection acts is PartLost on its owner. *)

FUNCTION_BLOCK FB_Rotation EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    bSensor : BOOL := FALSE; (* the proximity sensor *)
    bMachineRun : BOOL; (* the machine runs (with an owner, its run command counts too) *)
    bReset : BOOL R_EDGE; (* reset a latched fault *)
    ipOwner : I_PartOwner; (* optional: the motor it protects *)
    refData : REFERENCE TO ST_RotationData;
  END_VAR
  VAR_OUTPUT
    bHealthy : BOOL; (* no protection tripped *)
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
METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_RotationSet;
  END_VAR
  SetOk := stS.nPulsesPerRev >= 1 AND stS.tStartDelay >= T#0s AND stS.tStallTime > T#0s
           AND stS.fMinSpeed >= 0.0 AND stS.fMaxSpeed >= 0.0 AND stS.tSpeedDelay >= T#0s
           AND stS.tFilterTime >= T#0s AND stS.tCoastDown >= T#0s AND stS.tRetryWindow >= T#0s
           AND stS.stStall.tDelay >= T#0s AND stS.stStall.tRecover >= T#0s AND stS.stStall.nMaxRetries >= 0
           AND stS.stUnderspeed.tDelay >= T#0s AND stS.stUnderspeed.tRecover >= T#0s
           AND stS.stUnderspeed.nMaxRetries >= 0
           AND stS.stOverspeed.tDelay >= T#0s AND stS.stOverspeed.tRecover >= T#0s
           AND stS.stOverspeed.nMaxRetries >= 0
           AND stS.stSensor.tDelay >= T#0s AND stS.stSensor.tRecover >= T#0s AND stS.stSensor.nMaxRetries >= 0;
END_METHOD

(* the first acting protection: its error, stall > overspeed > underspeed > sensor *)
METHOD PRIVATE ActingId : E_UtError
  VAR_INPUT
    bTrips : BOOL;                // TRUE: among the trips / signals, FALSE: among the warnings
  END_VAR
  IF (bTrips AND (stWStall.bTrip OR stWStall.bSignal)) OR (NOT bTrips AND stWStall.bWarn) THEN
    ActingId := E_UtError.Stall;
  ELSIF (bTrips AND (stWOver.bTrip OR stWOver.bSignal)) OR (NOT bTrips AND stWOver.bWarn) THEN
    ActingId := E_UtError.Overspeed;
  ELSIF (bTrips AND (stWUnder.bTrip OR stWUnder.bSignal)) OR (NOT bTrips AND stWUnder.bWarn) THEN
    ActingId := E_UtError.Underspeed;
  ELSE
    ActingId := E_UtError.PulsesWhileStopped;
  END_IF;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  bOwnerRun := bRunning;
  IF bResetWanted THEN
    bOwnerReset := TRUE;
  END_IF;
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND (refData.sts.stStall.eState <> E_ProtState.Clear
                      OR refData.sts.stUnderspeed.eState <> E_ProtState.Clear
                      OR refData.sts.stOverspeed.eState <> E_ProtState.Clear
                      OR refData.sts.stSensor.eState <> E_ProtState.Clear) THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  IF stWStall.bTrip OR stWOver.bTrip OR stWUnder.bTrip OR stWSensor.bTrip THEN
    eErrorId := ActingId(bTrips := TRUE);
    Evaluate := E_PartAction.Trip;
  ELSIF stWStall.bSignal OR stWOver.bSignal OR stWUnder.bSignal OR stWSensor.bSignal THEN
    eErrorId := ActingId(bTrips := TRUE);
    Evaluate := E_PartAction.Stop;
  ELSIF stWStall.bWarn OR stWOver.bWarn OR stWUnder.bWarn OR stWSensor.bWarn THEN
    eErrorId := ActingId(bTrips := FALSE);
    Evaluate := E_PartAction.Warn;
  ELSE
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNext : I_Part;
  END_VAR
  THIS^.ipNext := ipNext;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bHealthy := FALSE;
  bRotating := FALSE;
  fSpeed := 0.0;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
bRun := bMachineRun OR (ipOwner <> NULL AND bOwnerRun);
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
  bSensorPrev := bSensor;
  bRunPrev := bRun;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
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
nPpr := MAX(refData.set.nPulsesPerRev, 1);
CASE refData.set.eSpeedUnit OF
  E_SpeedUnit.Rpm: fK := 60.0 / INT_TO_REAL(nPpr);
  E_SpeedUnit.RevPerSec: fK := 1.0 / INT_TO_REAL(nPpr);
  E_SpeedUnit.MetrePerMin: fK := 60.0 * refData.set.fDistPerPulse;
  E_SpeedUnit.MetrePerSec: fK := refData.set.fDistPerPulse;
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
IF bSensor AND NOT bSensorPrev THEN
  IF bEdgeSeen AND tNow - tLastEdge <= tStep + tStep + tStep / 2 AND tStep > T#0s THEN
    tFastUntil := tNow + T#5s;    (* at the limit: one pulse every two scans *)
  END_IF;
  IF NOT bEdgeSeen OR tNow - tLastEdge >= refData.set.tStallTime THEN
    tWinStart := tNow;            (* the first pulse after a stop: start measuring *)
    nWinEdges := 0;
    fMeasured := 0.0;
  ELSE
    refData.det.tPeriod := tNow - tLastEdge;
    nWinEdges := nWinEdges + 1;
    IF tNow - tWinStart >= refData.set.tFilterTime THEN
      fMeasured := 1000.0 * DINT_TO_REAL(nWinEdges) / LINT_TO_REAL(TIME_TO_LINT(tNow - tWinStart));
      tWinStart := tNow;
      nWinEdges := 0;
    END_IF;
  END_IF;
  bEdgeSeen := TRUE;
  tLastEdge := tNow;
END_IF;
bSensorPrev := bSensor;
refData.sts.bTooFast := tNow < tFastUntil;

(* the speed shown: falls while no pulse comes, 0 after tStallTime *)
fShown := fMeasured;
IF bEdgeSeen THEN
  tSince := tNow - tLastEdge;
  IF tSince >= refData.set.tStallTime THEN
    fShown := 0.0;
    fMeasured := 0.0;
  ELSIF tSince > refData.det.tPeriod AND tSince > T#0s THEN
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
bRotating := bEdgeSeen AND tNow - tLastEdge < refData.set.tStallTime;

(* the conditions *)
bPastStart := bRun AND tNow - tRunStart >= refData.set.tStartDelay;
bBelow := bPastStart AND NOT bUnitBad AND refData.set.fMinSpeed > 0.0 AND fShown < refData.set.fMinSpeed;
IF NOT bBelow THEN
  tBelowSince := tNow;
END_IF;
bAbove := NOT bUnitBad AND refData.set.fMaxSpeed > 0.0 AND fShown > refData.set.fMaxSpeed;
IF NOT bAbove THEN
  tAboveSince := tNow;
END_IF;

(* the resets: the pin, the record (once per write), the owner, the system *)
bResetReq := bReset OR (refData.bCmdReset AND NOT bCmdSeen) OR bOwnerReset OR SystemReset();
bCmdSeen := refData.bCmdReset;
refData.bCmdReset := FALSE;
bOwnerReset := FALSE;
IF bResetReq THEN
  refData.sts.bRefused := FALSE;
END_IF;

F_Protect(tNow := tNow, bCause := bPastStart AND (NOT bEdgeSeen OR tNow - tLastEdge >= refData.set.tStallTime)
                                  AND tNow - tRunStart >= refData.set.tStallTime,
          bResetReq := bResetReq, tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stStall,
          stSts := refData.sts.stStall, stWork := stWStall);
F_Protect(tNow := tNow, bCause := bBelow AND tNow - tBelowSince >= refData.set.tSpeedDelay,
          bResetReq := bResetReq, tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stUnderspeed,
          stSts := refData.sts.stUnderspeed, stWork := stWUnder);
F_Protect(tNow := tNow, bCause := bAbove AND tNow - tAboveSince >= refData.set.tSpeedDelay,
          bResetReq := bResetReq, tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stOverspeed,
          stSts := refData.sts.stOverspeed, stWork := stWOver);
F_Protect(tNow := tNow, bCause := NOT bRun AND bRotating AND tNow - tStopAt >= refData.set.tCoastDown
                                  AND tLastEdge - tStopAt >= refData.set.tCoastDown,
          bResetReq := bResetReq, tRetryWindow := refData.set.tRetryWindow, stSet := refData.set.stSensor,
          stSts := refData.sts.stSensor, stWork := stWSensor);

bAnyTrip := stWStall.bTrip OR stWUnder.bTrip OR stWOver.bTrip OR stWSensor.bTrip;
bAnyWarn := stWStall.bWarn OR stWUnder.bWarn OR stWOver.bWarn OR stWSensor.bWarn;
bHealthy := NOT bAnyTrip;
fSpeed := fShown;
refData.sts.fSpeed := fShown;
refData.sts.bRotating := bRotating;
refData.sts.bUnitBad := bUnitBad;

(* the time left: the acting protection's, else the start delay's *)
tLeft := T#0s;
IF bAnyTrip OR bAnyWarn THEN
  CASE ActingId(bTrips := bAnyTrip) OF
    E_UtError.Stall: tLeft := refData.sts.stStall.tTimeLeft;
    E_UtError.Overspeed: tLeft := refData.sts.stOverspeed.tTimeLeft;
    E_UtError.Underspeed: tLeft := refData.sts.stUnderspeed.tTimeLeft;
  ELSE
    tLeft := refData.sts.stSensor.tTimeLeft;
  END_CASE;
ELSIF bRun AND NOT bPastStart THEN
  tLeft := refData.set.tStartDelay - (tNow - tRunStart);
END_IF;
IF tLeft < T#0s THEN
  tLeft := T#0s;
END_IF;
refData.det.tTimeLeft := tLeft;

bError := bAnyTrip OR NOT bOk;
bWarning := NOT bError AND (bAnyWarn OR bUnitBad OR refData.sts.bTooFast OR refData.sts.bRefused
                            OR stWStall.bBadSetting OR stWUnder.bBadSetting OR stWOver.bBadSetting
                            OR stWSensor.bBadSetting);
IF bAnyTrip THEN
  eErrorId := ActingId(bTrips := TRUE);
ELSIF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bAnyWarn THEN
  eErrorId := ActingId(bTrips := FALSE);
ELSIF bUnitBad OR stWStall.bBadSetting OR stWUnder.bBadSetting OR stWOver.bBadSetting OR stWSensor.bBadSetting THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bTooFast THEN
  eErrorId := E_UtError.PulsesTooFast;
ELSIF refData.sts.bRefused THEN
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