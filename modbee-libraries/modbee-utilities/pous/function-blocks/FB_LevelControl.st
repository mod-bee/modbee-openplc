(* FB_LevelControl — keeps a level by driving a pump.

Pins: bRun (the process may run: e.g. the system not Off), bDemand (pump down / fill now, past the start
level, to set.fDemandStop), bInterlock (FALSE: nothing is requested), ipLevel (the level: a transmitter, a
vessel), ipTarget (the pump it drives), fSpeed (the speed asked of the target while it asks, e.g. for VSD pumps;
< 0 = the target's own), plus FB_Object's outputs. refData: its record.
-> bRunning (it asks and the pump runs), bCall (the level calls for pumping), bAtStop (at or past the stop
level), bHighHigh, bLowLow.
EMPTY (sump, wet well): start at or above fStart, stop at or below fStop; bDemand runs it down to fDemandStop;
at or above fHighHigh it always runs (overflow), also with bDemandOnly; at or below fLowLow it never runs.
FILL (tank): start at or below fStart, stop at or above fStop; bDemand fills to fDemandStop; at or above
fHighHigh it never runs (full); fLowLow is an alarm level only.
TIMED: no level needed (ipLevel may be unwired): on for set.tOnTime, off for set.tOffTime, over and over (on first),
while bRun.
set.fStartVariation: the start level moves at random by up to this, either way, after each cycle (fat build-up
in a sump; used only when smaller than the start-stop gap). A held bDemand that reached set.fDemandStop runs
again when the level is back at set.fDemandRestart (0 = the start level). -> bDemandActive (for FB_Stages'
demand pumps).
bDemandOnly: the start / stop levels are not used, it runs on bDemand only (the high-high still acts in
EMPTY). A bad level is ridden through for its protection delay (the request held), then set.eLevelFail:
Stop or RunOn (keeps the request as it was, for at most set.tRunOnMax, then stops).
Parts (FB_LevelCheck, FB_Protection): a trip stops the request; a signal pauses it (source low, no flow);
its parts: float backup (FB_LevelFloats), cleaning (FB_SumpClean), exercise (FB_Exercise), booster (FB_Booster),
level checks (FB_LevelCheck); beside it: stages (FB_Stages -> FB_Group.nExtra), the inflow estimate
(FB_VesselFlow). tot.nCycles counts each new call for pumping (kept over a power cut; bCmdResetTot clears it).
No pump: while it asks and its target is neither available nor running (a pump or its motor in Hand or Off,
faulted, every group member out), it is in fault: bError, eErrorId NoneAvailable (a run it serves can end on
it, e.g. bInterlock := NOT fbStation.bError). It clears by itself when the target is available again.
Detail (det): tTimeLeft (RunOn: the run-on left under set.tRunOnMax; TIMED: the on or off time left; else 0),
tPhaseTime (since its request last changed: pumping or idle). *)

FUNCTION_BLOCK FB_LevelControl EXTENDS FB_Object IMPLEMENTS I_LevelControl
  VAR_INPUT
    bRun : BOOL;
    bDemand : BOOL;
    bInterlock : BOOL := TRUE;
    ipLevel : I_Measurement; (* required *)
    ipTarget : I_Equipment; (* required *)
    fSpeed : REAL := -1.0; (* the speed asked of the target (< 0 = its own) *)
    refData : REFERENCE TO ST_LevelControlData;
  END_VAR
  VAR_OUTPUT
    bRunning : BOOL;
    bCall : BOOL;
    bAtStop : BOOL;
    bHighHigh : BOOL;
    bLowLow : BOOL;
    bDemandActive : BOOL; (* a demand is running (-> FB_Stages bDemand) *)
  END_VAR
  VAR RETAIN
    stKept : ST_LevelControlSet;
    nKeptLayout : UINT;
    stKeptTot : ST_LevelControlTot; (* kept at each cycle and reset *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    stWLevelBad : ST_ProtectionWork;
    bDemandLatch : BOOL; (* a demand runs until its level *)
    bDemandPrev : BOOL;
    bReq : BOOL;
    bCycleWas : BOOL; (* the request last scan, for the cycle count *)
    fLevel : REAL;
    nRng : UDINT; (* the start variation's random numbers *)
    fOffset : REAL;
    bReqWas : BOOL;
    bFailedWas : BOOL;
    tFailedAt : TIME;
    bDemandWait : BOOL; (* a held demand reached its level: waits for the restart level *)
    bCycOn : BOOL; (* TIMED *)
    tCycAt : TIME;
    tPhaseSince : TIME; (* the request last changed *)
  END_VAR
  VAR_TEMP
    bReset : BOOL;
    bNoneAvail : BOOL; (* asked, and the target is neither available nor running *)
    bGood : BOOL;
    bFailed : BOOL;
    bEmpty : BOOL;
    bTrip : BOOL;
    bReached : BOOL;
    bTimed : BOOL;
    bRecovered : BOOL;
    bDemandHeld : BOOL;
    fStartNow : REAL;
    fRestart : REAL;
  END_VAR


PROPERTY PUBLIC fActHighHigh : REAL
  GET
    IF __ISVALIDREF(refData) THEN fActHighHigh := refData.set.fHighHigh; ELSE fActHighHigh := 3.4E38; END_IF;
  END_GET
END_PROPERTY

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.stLevelBad.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.stLevelBad.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (refData.set.tRunOnMax >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fStartVariation >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (refData.set.fStartVariation <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (ABS(refData.set.fDemandRestart) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (refData.set.eMode <> E_LevelMode.Timed
             OR (refData.set.tOnTime > T#0s AND refData.set.tOffTime >= T#0s)) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.bDemandOnly OR refData.set.eMode = E_LevelMode.Timed
             OR (refData.set.eMode = E_LevelMode.Empty AND refData.set.fStart > refData.set.fStop)
             OR (refData.set.eMode = E_LevelMode.Fill AND refData.set.fStart < refData.set.fStop)) THEN
    SetWhy := E_UtError.LimitsBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

bTimed := FALSE;
IF __ISVALIDREF(refData) THEN
  bTimed := refData.set.eMode = E_LevelMode.Timed;
END_IF;
IF NOT __ISVALIDREF(refData) OR (ipLevel = NULL AND NOT bTimed) OR ipTarget = NULL THEN
  bRunning := FALSE;
  bDemandActive := FALSE;
  bError := TRUE;
  IF ipTarget = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  nRng := DWORD_TO_UDINT(DWORD#16#2545F491 XOR UDINT_TO_DWORD(LINT_TO_UDINT(TIME_TO_LINT(tNow))));
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.sts.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
bReset := SystemReset() OR refData.bCmdReset;
IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;
bEmpty := refData.set.eMode = E_LevelMode.Empty;

(* the level: ridden through while bad for its delay, then eLevelFail *)
bGood := bTimed;
IF ipLevel <> NULL THEN
  IF ipLevel.bIsFitted AND ipLevel.bHasValue AND ipLevel.bIsGood THEN
    bGood := TRUE;
    fLevel := ipLevel.fActValue;
  END_IF;
END_IF;
bTrip := F_Protect(tNow := tNow, bCause := NOT bGood, bResetReq := bReset, tRetryWindow := T#1h,
                   stSet := refData.set.stLevelBad, stSts := refData.sts.stLevelBad, stWork := stWLevelBad);
bFailed := stWLevelBad.bActive;
IF bFailed AND NOT bFailedWas THEN
  tFailedAt := tNow;
END_IF;
bFailedWas := bFailed;

(* the start in use: moved at random after each cycle *)
IF bReqWas AND NOT bReq THEN
  nRng := nRng * 1103515245 + 12345;
  IF refData.set.fStartVariation > 0.0 AND refData.set.fStartVariation < ABS(refData.set.fStart - refData.set.fStop) THEN
    fOffset := (UDINT_TO_REAL((nRng / 65536) MOD 32768) / 16383.5 - 1.0) * refData.set.fStartVariation;
  ELSE
    fOffset := 0.0;
  END_IF;
END_IF;
IF refData.set.fStartVariation <= 0.0 THEN
  fOffset := 0.0;
END_IF;
bReqWas := bReq;
fStartNow := refData.set.fStart + fOffset;

(* levels *)
IF bEmpty THEN
  bHighHigh := fLevel >= refData.set.fHighHigh;
  bLowLow := fLevel <= refData.set.fLowLow;
  bAtStop := fLevel <= refData.set.fStop;
  IF fLevel >= fStartNow THEN
    bCall := TRUE;
  ELSIF bAtStop THEN
    bCall := FALSE;
  END_IF;
ELSE
  bHighHigh := fLevel >= refData.set.fHighHigh;
  bLowLow := fLevel <= refData.set.fLowLow;
  bAtStop := fLevel >= refData.set.fStop;
  IF fLevel <= fStartNow THEN
    bCall := TRUE;
  ELSIF bAtStop THEN
    bCall := FALSE;
  END_IF;
END_IF;
IF refData.set.bDemandOnly THEN
  bCall := FALSE;
END_IF;
IF bTimed THEN
  bHighHigh := FALSE;
  bLowLow := FALSE;
  bAtStop := FALSE;
  IF NOT bRun OR NOT bInterlock THEN
    bCycOn := TRUE;                 (* on first, when it may run again *)
    tCycAt := tNow;
  ELSIF bCycOn AND tNow - tCycAt >= refData.set.tOnTime AND refData.set.tOffTime > T#0s THEN
    bCycOn := FALSE;
    tCycAt := tNow;
  ELSIF NOT bCycOn AND tNow - tCycAt >= refData.set.tOffTime THEN
    bCycOn := TRUE;
    tCycAt := tNow;
  END_IF;
  bCall := bCycOn;
END_IF;

(* demand: the pin's rising edge or the record's command latches it until its level *)
IF (bDemand AND NOT bDemandPrev) OR refData.bCmdDemand THEN
  bDemandLatch := TRUE;
  refData.bCmdDemand := FALSE;
END_IF;
bDemandPrev := bDemand;
IF refData.bCmdStop THEN
  bDemandLatch := FALSE;
  refData.bCmdStop := FALSE;
END_IF;
bReached := NOT bTimed AND ((bEmpty AND fLevel <= refData.set.fDemandStop) OR (NOT bEmpty AND fLevel >= refData.set.fDemandStop));
(* a held demand: runs to its level, then waits for the restart level *)
fRestart := refData.set.fDemandRestart;
IF fRestart = 0.0 THEN
  fRestart := fStartNow;
END_IF;
bRecovered := (bEmpty AND fLevel >= fRestart) OR (NOT bEmpty AND fLevel <= fRestart);
IF NOT bDemand THEN
  bDemandWait := FALSE;
ELSIF bReached THEN
  bDemandWait := TRUE;
ELSIF bDemandWait AND bRecovered THEN
  bDemandWait := FALSE;
END_IF;
bDemandHeld := bDemand AND NOT bReached AND NOT bDemandWait;
IF bDemandLatch AND NOT bFailed AND bReached THEN
  bDemandLatch := FALSE;          // the demand level is reached
END_IF;

(* parts *)
EvaluateParts(bRunning := bReq AND ipTarget.bIsRunning, bResetWanted := bReset, bMasked := FALSE);

(* the request *)
IF NOT bFailed THEN
  bReq := bCall OR bDemandLatch OR bDemandHeld;
  IF bEmpty AND bHighHigh THEN
    bReq := TRUE;                 // overflow: always runs
  END_IF;
  IF bPartRun OR bPartRequest THEN
    bReq := TRUE;                 // a part asks it to run (the float backup; an exercise, a clean)
  END_IF;
  IF bEmpty AND bLowLow THEN
    bReq := FALSE;                // cut-out
  END_IF;
  IF NOT bEmpty AND bHighHigh THEN
    bReq := FALSE;                // full
  END_IF;
ELSIF bPartRun THEN
  bReq := TRUE;                   // the float backup runs it while the level is bad
ELSIF refData.set.eLevelFail = E_LevelFail.Stop THEN
  bReq := FALSE;
ELSIF refData.set.tRunOnMax > T#0s AND tNow - tFailedAt >= refData.set.tRunOnMax THEN
  bReq := FALSE;                  // RunOn: as it was, for at most tRunOnMax
END_IF;
IF NOT bRun OR NOT bInterlock OR bPartTrip OR bPartStop THEN
  bReq := FALSE;
END_IF;
IF bPartHold AND NOT ipTarget.bIsRunning THEN
  bReq := FALSE;                  // no new start
END_IF;
ipTarget.Request(bRun := bReq, bHold := FALSE, fSpeed := fSpeed,
                 bUrgent := bReq AND ((bEmpty AND bHighHigh) OR bPartRun));

(* the cycle count: each new call for pumping *)
IF bReq <> bCycleWas THEN
  tPhaseSince := tNow;
END_IF;
IF bReq AND NOT bCycleWas THEN
  refData.tot.nCycles := refData.tot.nCycles + 1;
  stKeptTot := refData.tot;
END_IF;
bCycleWas := bReq;
IF refData.bCmdResetTot THEN
  refData.tot.nCycles := 0;
  stKeptTot := refData.tot;
  refData.bCmdResetTot := FALSE;
END_IF;
bRunning := bReq AND ipTarget.bIsRunning;

(* status *)
bNoneAvail := bReq AND NOT ipTarget.bIsAvailable AND NOT ipTarget.bIsRunning;
bError := bPartTrip OR stWLevelBad.bTrip OR bNoneAvail;
bWarning := bPartWarn OR stWLevelBad.bWarn OR refData.sts.bRefused;
IF bPartTrip THEN
  eErrorId := ePartTrip;
ELSIF stWLevelBad.bTrip THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bNoneAvail THEN
  eErrorId := E_UtError.NoneAvailable;
ELSIF stWLevelBad.bWarn THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bPartWarn THEN
  eErrorId := ePartWarn;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF NOT bRun THEN
  eState := E_State.Off;
ELSIF bError THEN
  eState := E_State.Fault;
ELSIF NOT bInterlock OR bPartStop THEN
  eState := E_State.Held;
ELSIF bRunning THEN
  eState := E_State.Running;
ELSIF bReq THEN
  eState := E_State.Starting;
ELSE
  eState := E_State.Idle;
END_IF;
refData.sts.eState := eState;
refData.sts.eErrorId := eErrorId;
refData.sts.bCall := bCall;
bDemandActive := bDemandLatch OR bDemandHeld;
refData.sts.bDemandActive := bDemandActive;
refData.sts.fStartNow := fStartNow;
refData.sts.bRunOn := bFailed AND bReq AND NOT bPartRun AND refData.set.eLevelFail = E_LevelFail.RunOn;
refData.sts.bAtStop := bAtStop;
refData.sts.bHighHigh := bHighHigh;
refData.sts.bLowLow := bLowLow;
refData.sts.bRequest := bReq;
refData.det.tPhaseTime := tNow - tPhaseSince;
refData.det.tTimeLeft := T#0s;
IF refData.sts.bRunOn AND refData.set.tRunOnMax > T#0s THEN
  refData.det.tTimeLeft := MAX(T#0s, refData.set.tRunOnMax - (tNow - tFailedAt));
ELSIF bTimed AND bRun AND bInterlock THEN
  IF bCycOn THEN
    refData.det.tTimeLeft := MAX(T#0s, refData.set.tOnTime - (tNow - tCycAt));
  ELSE
    refData.det.tTimeLeft := MAX(T#0s, refData.set.tOffTime - (tNow - tCycAt));
  END_IF;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK