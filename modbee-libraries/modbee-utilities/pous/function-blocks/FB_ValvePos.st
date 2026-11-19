(* FB_ValvePos — ABSTRACT base of the positioning valves (FB_ValveMod, FB_ValveFloat). On FB_Equipment: "running" is
open (not closed). An owner (a PID loop such as FB_SpeedLoop, a zone, a route) drives it through
I_Equipment.Request: bRun = open, fSpeed = the position % (none: 100 %).

Pins: ipPositionFeedback (I_Measurement, the position feedback in %; NULL = the variant's travel estimate), bOpenLimitSwitch /
bClosedLimitSwitch (end switches, with set.bOpenLimitSwitchFitted / bClosedLimitSwitchFitted), refData -> fPositionPct (the position in use: the
feedback when good, else the estimate; never the demand alone), bIsOpen, bIsClosed, plus FB_Equipment's
bInterlock, bPermissive, ipSystem and FB_Object's outputs.
Where it goes (fPositionSetpointPct, for the variant):
  open (bRun)                Hand: set.fHandPositionPct (kept; on entering Hand it takes the position now: bumpless);
                             Auto: the owner's fSpeed (none: 100 %)
  not open                   set.fRestPositionPct
  Off / interlock / a trip   set.fSafePositionPct (< 0: stays; set.bHoldWhenTripped: a trip holds)
Protections: position feedback (outside -5..105 % or not good; set.stPositionFeedbackFault, default Trip after 500 ms: the
estimate takes over) and deviation (|demand - feedback| above set.fDeviationAbovePct while settled; set.stDeviationFault,
default Warn after 10 s). bIsOpen / bIsClosed: an end switch, or the position past set.fOpenAtOrAbovePct /
fClosedAtOrBelowPct. Exercise: an FB_Exercise part on the valve (ipOwner := the valve) opens an idle valve in Auto
fully (100 %) for its run time. The variant moves the valve (fDemandPct, fEstimatedPct, bSettled) after SUPER^().
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK ABSTRACT FB_ValvePos EXTENDS FB_Equipment
  VAR_INPUT
    ipPositionFeedback : I_Measurement; (* position feedback, %; NULL = the travel estimate *)
    bOpenLimitSwitch : BOOL; (* open end switch (TRUE = made) *)
    bClosedLimitSwitch : BOOL; (* closed end switch (TRUE = made) *)
    refData : REFERENCE TO ST_ValvePosData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    fPositionPct : REAL; (* the position in use, % (-1: not known yet) *)
    bIsOpen : BOOL; (* open: its end switch, or the travel time passed *)
    bIsClosed : BOOL; (* closed: its end switch, or the travel time passed *)
  END_VAR
  VAR RETAIN
    stKept : ST_ValvePosSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    fAim : REAL; (* for the variant: where to go, % *)
    bAimHold : BOOL; (* for the variant: stay where it is *)
    bAimShaped : BOOL; (* for the variant: clamp / ramp the aim (not a safe position) *)
    fDemand : REAL; (* from the variant: the demand now, % *)
    fEstimate : REAL; (* from the variant: the travel estimate, % *)
    bSettled : BOOL; (* from the variant: not moving *)
    bFbOk : BOOL;
    eModeWas : E_Mode;
    stWDev : ST_ProtectionWork;
    stWPosFb : ST_ProtectionWork;
    bExercising : BOOL; (* the run is a part's (FB_Exercise), not the owner's *)
  END_VAR
  VAR_TEMP
    bReset : BOOL;
    bTrip : BOOL;
    bWarn : BOOL;
    eOwn : E_UtError;
    bFbFit : BOOL;
    bFbBad : BOOL;
    fFbV : REAL;
    bLsO : BOOL;
    bLsC : BOOL;
  END_VAR


(* bRun: open. The aim, for the variant. *)
METHOD PROTECTED Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
  bAimHold := FALSE;
  bAimShaped := TRUE;
  IF NOT bRun AND (eStop = E_StopReason.Off OR eStop = E_StopReason.Interlock OR eStop = E_StopReason.Fault) THEN
    bAimShaped := FALSE;
    IF (eStop = E_StopReason.Fault AND refData.set.bHoldWhenTripped) OR refData.set.fSafePositionPct < 0.0 THEN
      bAimHold := TRUE;
      fAim := fDemand;
    ELSE
      fAim := LIMIT(0.0, refData.set.fSafePositionPct, 100.0);
    END_IF;
  ELSIF NOT bRun THEN
    fAim := LIMIT(0.0, refData.set.fRestPositionPct, 100.0);
  ELSIF refData.set.eMode = E_Mode.Hand THEN
    fAim := LIMIT(0.0, refData.set.fHandPositionPct, 100.0);
  ELSIF bExercising THEN
    fAim := 100.0;                (* an exercise: the full stroke *)
  ELSIF fSpeedReq >= 0.0 AND fSpeedReq = fSpeedReq THEN
    fAim := LIMIT(0.0, fSpeedReq, 100.0);
  ELSE
    fAim := 100.0;
  END_IF;
END_METHOD

(* the Auto decision: the owner's request, or a part's (FB_Exercise) *)
METHOD PROTECTED OVERRIDE ShapeRun : BOOL
  VAR_INPUT
    bWant : BOOL;
  END_VAR
  bExercising := NOT bWant AND bPartRequest;
  ShapeRun := bWant OR bPartRequest;
END_METHOD

(* "running" is open: not closed *)
METHOD PROTECTED FeedbackOk : BOOL
  FeedbackOk := NOT bIsClosed;
END_METHOD

METHOD PRIVATE ProtOk : BOOL
  VAR_INPUT
    stP : REFERENCE TO ST_ProtectionSet;
  END_VAR
  ProtOk := stP.tTripDelay >= T#0s AND stP.tAutoRecoverAfter >= T#0s AND stP.nMaxRetriesBeforeLockout >= 0;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_ValvePosSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (ABS(stS.fSafePositionPct) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (stS.fRestPositionPct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fRestPositionPct <= 100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fHandPositionPct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fHandPositionPct <= 100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fPositionDeadbandPct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fPositionDeadbandPct <= 50.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fDeviationAbovePct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fClosedAtOrBelowPct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fOpenAtOrAbovePct <= 100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fClosedAtOrBelowPct < stS.fOpenAtOrAbovePct) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (ProtOk(stP := stS.stDeviationFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (ProtOk(stP := stS.stPositionFeedbackFault)) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ValvePosSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
ELSIF SetOk(stS := refData.set) THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;

bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);

(* Hand: bumpless on entry *)
IF refData.set.eMode = E_Mode.Hand AND eModeWas <> E_Mode.Hand AND NOT bFirstScan AND fPositionPct >= 0.0 THEN
  refData.set.fHandPositionPct := LIMIT(0.0, fPositionPct, 100.0);
END_IF;
eModeWas := refData.set.eMode;

(* the feedback and the position in use *)
bFbFit := FALSE;
fFbV := 0.0;
bFbBad := FALSE;
IF ipPositionFeedback <> NULL THEN
  IF ipPositionFeedback.bIsFitted THEN
    bFbFit := TRUE;
    fFbV := ipPositionFeedback.fActValue;
    bFbBad := NOT ipPositionFeedback.bIsGood OR NOT (fFbV = fFbV) OR fFbV < -5.0 OR fFbV > 105.0;
  END_IF;
END_IF;
bFbOk := bFbFit AND NOT bFbBad;
F_Protect(tNow := tNow, bConditionPresent := bFbFit AND bFbBad, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
          stSettings := refData.set.stPositionFeedbackFault, stStatus := refData.sts.stPositionFeedbackFault, stWorking := stWPosFb);
F_Protect(tNow := tNow, bConditionPresent := bFbOk AND bSettled AND ABS(fDemand - fFbV) > refData.set.fDeviationAbovePct,
          bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
          stSettings := refData.set.stDeviationFault, stStatus := refData.sts.stDeviationFault, stWorking := stWDev);
IF bFbOk THEN
  fPositionPct := LIMIT(0.0, fFbV, 100.0);
ELSE
  fPositionPct := fEstimate;
END_IF;
bLsO := refData.set.bOpenLimitSwitchFitted AND bOpenLimitSwitch;
bLsC := refData.set.bClosedLimitSwitchFitted AND bClosedLimitSwitch;
bIsOpen := bLsO OR (fPositionPct >= 0.0 AND fPositionPct >= refData.set.fOpenAtOrAbovePct);
bIsClosed := bLsC OR (fPositionPct >= 0.0 AND fPositionPct <= refData.set.fClosedAtOrBelowPct);
IF bLsO AND bLsC THEN
  bIsOpen := FALSE;               (* both made: neither *)
  bIsClosed := FALSE;
END_IF;

bTrip := stWPosFb.bTripping OR stWDev.bTripping;
bWarn := stWPosFb.bWarning OR stWDev.bWarning;
eOwn := E_UtError.None;
IF stWPosFb.bTripping OR stWPosFb.bWarning THEN
  eOwn := E_UtError.SensorBad;
ELSIF stWDev.bTripping OR stWDev.bWarning THEN
  eOwn := E_UtError.PositionDeviation;
END_IF;
Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset, tRestartDelay := T#0s);

refData.sts.fPositionSetpointPct := fAim;
refData.sts.fPositionPct := fPositionPct;
refData.sts.bFeedbackGood := bFbOk;
IF bFbFit THEN
  refData.sts.fFeedbackPct := fFbV;
ELSE
  refData.sts.fFeedbackPct := -1.0;
END_IF;
refData.sts.bIsOpen := bIsOpen;
refData.sts.bIsClosed := bIsClosed;

END_FUNCTION_BLOCK