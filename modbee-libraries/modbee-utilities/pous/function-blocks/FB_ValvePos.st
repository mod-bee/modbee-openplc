(* FB_ValvePos — ABSTRACT base of the positioning valves (FB_ValveMod, FB_ValveFloat; src-v2 UT_VALVE core +
UT_POS_FB_RUN). On FB_Equipment: "running" is open (not closed). An owner (a PID loop such as FB_SpeedLoop, a
zone, a route) drives it through I_Equipment.Request: bRun = open, fSpeed = the position % (none: 100 %).

Pins: ipPosFb (I_Measurement, the position feedback in %; NULL = the variant's travel estimate), bOpenLs /
bClosedLs (end switches, with set.bUseOpenLs / bUseClosedLs), refData -> fPosition (the position in use: the
feedback when good, else the estimate; never the demand alone), bIsOpen, bIsClosed, plus FB_Equipment's
bInterlock, bPermissive, ipSystem and FB_Object's outputs.
Where it goes (fAim, for the variant):
  open (bRun)                Hand: set.fHandPos (kept; on entering Hand it takes the position now: bumpless);
                             Auto: the owner's fSpeed (none: 100 %)
  not open                   set.fRestPos
  Off / interlock / a trip   set.fSafePos (< 0: stays; set.bHoldOnFault: a trip holds)
Protections: position feedback (outside -5..105 % or not good; set.stPosFb, default Trip after 500 ms: the
estimate takes over) and deviation (|demand - feedback| above set.fDevLimit while settled; set.stDeviation,
default Warn after 10 s). bIsOpen / bIsClosed: an end switch, or the position past set.fOpenThreshold /
fClosedThreshold. Exercise: an FB_Exercise part on the valve (ipOwner := the valve) opens an idle valve in Auto
fully (100 %) for its run time. The variant moves the valve (fDemand, fEstimate, bSettled) after SUPER^().
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK ABSTRACT FB_ValvePos EXTENDS FB_Equipment
  VAR_INPUT
    ipPosFb : I_Measurement; (* position feedback, %; NULL = the travel estimate *)
    bOpenLs : BOOL;
    bClosedLs : BOOL;
    refData : REFERENCE TO ST_ValvePosData;
  END_VAR
  VAR_OUTPUT
    fPosition : REAL; (* the position in use, % (-1: not known yet) *)
    bIsOpen : BOOL;
    bIsClosed : BOOL;
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
    IF (eStop = E_StopReason.Fault AND refData.set.bHoldOnFault) OR refData.set.fSafePos < 0.0 THEN
      bAimHold := TRUE;
      fAim := fDemand;
    ELSE
      fAim := LIMIT(0.0, refData.set.fSafePos, 100.0);
    END_IF;
  ELSIF NOT bRun THEN
    fAim := LIMIT(0.0, refData.set.fRestPos, 100.0);
  ELSIF refData.set.eMode = E_Mode.Hand THEN
    fAim := LIMIT(0.0, refData.set.fHandPos, 100.0);
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
  ProtOk := stP.tDelay >= T#0s AND stP.tRecover >= T#0s AND stP.nMaxRetries >= 0;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_ValvePosSet;
  END_VAR
  SetOk := stS.tRetryWindow >= T#0s AND ABS(stS.fSafePos) <= REAL#3.4E38
           AND stS.fRestPos >= 0.0 AND stS.fRestPos <= 100.0 AND stS.fHandPos >= 0.0 AND stS.fHandPos <= 100.0
           AND stS.fDeadband >= 0.0 AND stS.fDeadband <= 50.0 AND stS.fDevLimit >= 0.0
           AND stS.fClosedThreshold >= 0.0 AND stS.fOpenThreshold <= 100.0
           AND stS.fClosedThreshold < stS.fOpenThreshold
           AND ProtOk(stP := stS.stDeviation) AND ProtOk(stP := stS.stPosFb);
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);

(* Hand: bumpless on entry *)
IF refData.set.eMode = E_Mode.Hand AND eModeWas <> E_Mode.Hand AND NOT bFirstScan AND fPosition >= 0.0 THEN
  refData.set.fHandPos := LIMIT(0.0, fPosition, 100.0);
END_IF;
eModeWas := refData.set.eMode;

(* the feedback and the position in use *)
bFbFit := FALSE;
fFbV := 0.0;
bFbBad := FALSE;
IF ipPosFb <> NULL THEN
  IF ipPosFb.bIsFitted THEN
    bFbFit := TRUE;
    fFbV := ipPosFb.fActValue;
    bFbBad := NOT ipPosFb.bIsGood OR NOT (fFbV = fFbV) OR fFbV < -5.0 OR fFbV > 105.0;
  END_IF;
END_IF;
bFbOk := bFbFit AND NOT bFbBad;
F_Protect(tNow := tNow, bCause := bFbFit AND bFbBad, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
          stSet := refData.set.stPosFb, stSts := refData.sts.stPosFb, stWork := stWPosFb);
F_Protect(tNow := tNow, bCause := bFbOk AND bSettled AND ABS(fDemand - fFbV) > refData.set.fDevLimit,
          bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
          stSet := refData.set.stDeviation, stSts := refData.sts.stDeviation, stWork := stWDev);
IF bFbOk THEN
  fPosition := LIMIT(0.0, fFbV, 100.0);
ELSE
  fPosition := fEstimate;
END_IF;
bLsO := refData.set.bUseOpenLs AND bOpenLs;
bLsC := refData.set.bUseClosedLs AND bClosedLs;
bIsOpen := bLsO OR (fPosition >= 0.0 AND fPosition >= refData.set.fOpenThreshold);
bIsClosed := bLsC OR (fPosition >= 0.0 AND fPosition <= refData.set.fClosedThreshold);
IF bLsO AND bLsC THEN
  bIsOpen := FALSE;               (* both made: neither *)
  bIsClosed := FALSE;
END_IF;

bTrip := stWPosFb.bTrip OR stWDev.bTrip;
bWarn := stWPosFb.bWarn OR stWDev.bWarn;
eOwn := E_UtError.None;
IF stWPosFb.bTrip OR stWPosFb.bWarn THEN
  eOwn := E_UtError.SensorBad;
ELSIF stWDev.bTrip OR stWDev.bWarn THEN
  eOwn := E_UtError.PositionDeviation;
END_IF;
Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset, tRestartDelay := T#0s);

refData.sts.fAim := fAim;
refData.sts.fPosition := fPosition;
refData.sts.bFbOk := bFbOk;
IF bFbFit THEN
  refData.sts.fFeedback := fFbV;
ELSE
  refData.sts.fFeedback := -1.0;
END_IF;
refData.sts.bOpen := bIsOpen;
refData.sts.bClosed := bIsClosed;

END_FUNCTION_BLOCK