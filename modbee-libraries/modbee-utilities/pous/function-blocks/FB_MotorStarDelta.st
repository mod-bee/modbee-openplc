(* FB_MotorStarDelta EXTENDS FB_Motor — a star-delta starter.
Everything of FB_Motor (modes, protections, totals, refData) plus the star -> delta sequence. bQ = the main
contactor; bFeedback = the main contactor's aux.
Pins added: bFeedbackStar, bFeedbackDelta (the star / delta auxes, used with set.bUseStarDeltaFb), refSd (its
record), fCurrentPct (the motor current, % of full load: wire FB_MotorCurrent's fPercent; < 0 = not wired)
-> bQStar, bQDelta (never on together).
Sequence: main and star together; star for set.tStarTime (or, with set.fStarCurrentPct > 0, until the star current
has risen to and fallen back below that % of full load, whichever comes first) and the main confirmed; star off;
the open transition (set.tTransition, and with bUseStarDeltaFb the star aux open); delta on (FB_Changeover). An aux
that does not follow its coil within set.tChangeover trips set.stChangeover (default Manual): bError Changeover.
fStarCurrentPct > 0 with fCurrentPct not wired: a warning (BadSetting), the star time alone.
Jog: FB_MotorJog.
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_MotorStarDelta EXTENDS FB_Motor
  VAR_INPUT
    bFeedbackStar : BOOL := FALSE; (* star contactor aux (optional) *)
    bFeedbackDelta : BOOL; (* delta contactor aux *)
    refSd : REFERENCE TO ST_StarDeltaData;
    fCurrentPct : REAL := -1.0; (* the motor current, % of full load (FB_MotorCurrent.fPercent; < 0 = not wired) *)
  END_VAR
  VAR_OUTPUT
    bQStar : BOOL; (* never with bQDelta *)
    bQDelta : BOOL;
  END_VAR
  VAR RETAIN
    stKeptSd : ST_StarDeltaSet;
    nKeptSdLayout : UINT;
  END_VAR
  VAR
    fbCo : FB_Changeover;
    stWChangeover : ST_ProtectionWork;
    tStarAt : TIME;
    bStarWas : BOOL;
    bToDelta : BOOL;
    bSdFirst : BOOL := TRUE;
    bSeenHigh : BOOL; (* the star current has risen to the threshold *)
  END_VAR


METHOD PRIVATE SdWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_StarDeltaSet;
  END_VAR
  SdWhy := E_UtError.None;
  IF NOT (stS.tStarTime > T#0s) THEN
    SdWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tTransition >= T#0s) THEN
    SdWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tChangeover > T#0s) THEN
    SdWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stChangeover.tDelay >= T#0s) THEN
    SdWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stChangeover.tRecover >= T#0s) THEN
    SdWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stChangeover.nMaxRetries >= 0) THEN
    SdWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.fStarCurrentPct >= 0.0) THEN
    SdWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fStarCurrentPct <= REAL#3.4E38) THEN
    SdWhy := E_UtError.AboveMax;
  END_IF;
END_METHOD

METHOD PRIVATE SdOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_StarDeltaSet;
  END_VAR
  SdOk := SdWhy(stS := stS) = E_UtError.None;
END_METHOD

(* the changeover supervision, with the motor's own protections; a dead time holds a new start *)
METHOD PROTECTED OVERRIDE DriveChecks
  VAR_INPUT
    bReset : BOOL;
  END_VAR
  VAR_OUTPUT
    bTrip : BOOL;
    bWarn : BOOL;
    bHold : BOOL;
    eError : E_UtError;
  END_VAR
  eError := E_UtError.None;
  IF NOT __ISVALIDREF(refSd) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  F_Protect(tNow := tNow, bCause := fbCo.bCause, bResetReq := bReset, tRetryWindow := T#1h,
            stSet := refSd.set.stChangeover, stSts := refSd.sts.stChangeover, stWork := stWChangeover);
  bTrip := stWChangeover.bTrip;
  bWarn := stWChangeover.bWarn OR (refSd.set.fStarCurrentPct > 0.0 AND fCurrentPct < 0.0);
  bHold := fbCo.bStartBlock AND NOT bQ;
  IF bTrip OR stWChangeover.bWarn THEN
    eError := E_UtError.Changeover;
  ELSIF bWarn THEN
    eError := E_UtError.BadSetting;   (* the star current is asked for but not wired: the star time alone *)
  END_IF;
END_METHOD

SUPER^();                         // the motor: modes, protections (with DriveChecks), bQ = main

IF NOT __ISVALIDREF(refSd) THEN
  bQStar := FALSE;
  bQDelta := FALSE;
  RETURN;
END_IF;
IF bSdFirst THEN
  IF nKeptSdLayout = cLayout THEN
    refSd.set := stKeptSd;
  ELSE
    stKeptSd := refSd.set;
    nKeptSdLayout := cLayout;
  END_IF;
  bSdFirst := FALSE;
ELSIF SdOk(stS := refSd.set) THEN
  stKeptSd := refSd.set;
ELSIF SdOk(stS := stKeptSd) THEN
  refSd.sts.eRefusedWhy := SdWhy(stS := refSd.set);
  refSd.set := stKeptSd;
  refSd.sts.bRefused := TRUE;
END_IF;
IF bResetThisScan THEN                  // the equipment's reset clears a refused write
  refSd.sts.bRefused := FALSE;
  refSd.sts.eRefusedWhy := E_UtError.None;
END_IF;

(* the star time, or the star current risen and fallen, with the main confirmed *)
IF bQStar AND NOT bStarWas THEN
  tStarAt := tNow;
  bSeenHigh := FALSE;
END_IF;
bStarWas := bQStar;
IF bQStar AND refSd.set.fStarCurrentPct > 0.0 AND fCurrentPct >= 0.0 THEN
  IF fCurrentPct >= refSd.set.fStarCurrentPct THEN
    bSeenHigh := TRUE;
  ELSIF bSeenHigh AND FeedbackOk() THEN
    bToDelta := TRUE;             (* the star current has fallen: the motor is up to speed *)
  END_IF;
END_IF;
IF bQStar AND tNow - tStarAt >= refSd.set.tStarTime AND FeedbackOk() THEN
  bToDelta := TRUE;
END_IF;
refSd.sts.bCurrentRisen := bSeenHigh;
IF NOT bQ THEN
  bToDelta := FALSE;
END_IF;
fbCo(bRun := bQ, bWantB := bToDelta, bFbA := bFeedbackStar, bFbB := bFeedbackDelta,
     bUseFb := refSd.set.bUseStarDeltaFb, tGapAB := refSd.set.tTransition, tGapBA := refSd.set.tTransition,
     tOpenTime := refSd.set.tChangeover);
bQStar := fbCo.bQA;
bQDelta := fbCo.bQB;
refSd.sts.bInStar := bQStar;
refSd.sts.bInDelta := bQDelta;
IF bQStar AND tNow - tStarAt < refSd.set.tStarTime THEN
  refSd.sts.tStarLeft := refSd.set.tStarTime - (tNow - tStarAt);
ELSE
  refSd.sts.tStarLeft := T#0s;
END_IF;

END_FUNCTION_BLOCK