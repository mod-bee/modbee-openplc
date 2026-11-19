(* FB_MotorStarDelta EXTENDS FB_Motor — a star-delta starter.
Everything of FB_Motor (modes, protections, totals, refData) plus the star -> delta sequence. bRunOutput = the main
contactor; bRunFeedback = the main contactor's aux.
Pins added: bStarFeedback, bDeltaFeedback (the star / delta auxes, used with set.bContactorFeedbackFitted), refStarDeltaData (its
record), fCurrentPct (the motor current, % of full load: wire FB_MotorCurrent's fCurrentPct; < 0 = not wired)
-> bStarOutput, bDeltaOutput (never on together).
Sequence: main and star together; star for set.tStarTime (or, with set.fToDeltaBelowPct > 0, until the star current
has risen to and fallen back below that % of full load, whichever comes first) and the main confirmed; star off;
the open transition (set.tStarToDeltaDeadTime, and with bContactorFeedbackFitted the star aux open); delta on (FB_Changeover). An aux
that does not follow its coil within set.tAuxFeedbackTimeout trips set.stAuxFeedbackFault (default Manual): bError Changeover.
fToDeltaBelowPct > 0 with fCurrentPct not wired: a warning (BadSetting), the star time alone.
Jog: FB_MotorJog.
Its settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_MotorStarDelta EXTENDS FB_Motor
  VAR_INPUT
    bStarFeedback : BOOL := FALSE; (* star contactor aux (optional) *)
    bDeltaFeedback : BOOL; (* delta contactor aux *)
    fCurrentPct : REAL := -1.0; (* the motor current, % of full load (FB_MotorCurrent.fCurrentPct; < 0 = not wired) *)
    refStarDeltaData : REFERENCE TO ST_StarDeltaData; (* the star-delta record *)
  END_VAR
  VAR_OUTPUT
    bStarOutput : BOOL; (* never with bDeltaOutput *)
    bDeltaOutput : BOOL; (* the delta contactor *)
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
  ELSIF NOT (stS.tStarToDeltaDeadTime >= T#0s) THEN
    SdWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tAuxFeedbackTimeout > T#0s) THEN
    SdWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stAuxFeedbackFault.tTripDelay >= T#0s) THEN
    SdWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stAuxFeedbackFault.tAutoRecoverAfter >= T#0s) THEN
    SdWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stAuxFeedbackFault.nMaxRetriesBeforeLockout >= 0) THEN
    SdWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.fToDeltaBelowPct >= 0.0) THEN
    SdWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fToDeltaBelowPct <= REAL#3.4E38) THEN
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
  IF NOT __ISVALIDREF(refStarDeltaData) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  F_Protect(tNow := tNow, bConditionPresent := fbCo.bAuxWrong, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
            stSettings := refStarDeltaData.set.stAuxFeedbackFault, stStatus := refStarDeltaData.sts.stAuxFeedbackFault, stWorking := stWChangeover);
  bTrip := stWChangeover.bTripping;
  bWarn := stWChangeover.bWarning OR (refStarDeltaData.set.fToDeltaBelowPct > 0.0 AND fCurrentPct < 0.0);
  bHold := fbCo.bStartHeld AND NOT bRunOutput;
  IF bTrip OR stWChangeover.bWarning THEN
    eError := E_UtError.Changeover;
  ELSIF bWarn THEN
    eError := E_UtError.BadSetting;   (* the star current is asked for but not wired: the star time alone *)
  END_IF;
END_METHOD

SUPER^();                         // the motor: modes, protections (with DriveChecks), bRunOutput = main

IF NOT __ISVALIDREF(refStarDeltaData) THEN
  bStarOutput := FALSE;
  bDeltaOutput := FALSE;
  RETURN;
END_IF;
IF bSdFirst THEN
  IF nKeptSdLayout = cLayout THEN
    refStarDeltaData.set := stKeptSd;
  ELSE
    stKeptSd := refStarDeltaData.set;
    nKeptSdLayout := cLayout;
  END_IF;
  bSdFirst := FALSE;
ELSIF SdOk(stS := refStarDeltaData.set) THEN
  stKeptSd := refStarDeltaData.set;
ELSIF SdOk(stS := stKeptSd) THEN
  refStarDeltaData.sts.eSettingRefusedErrorId := SdWhy(stS := refStarDeltaData.set);
  refStarDeltaData.set := stKeptSd;
  refStarDeltaData.sts.bSettingRefused := TRUE;
END_IF;
IF bResetThisScan THEN                  // the equipment's reset clears a refused write
  refStarDeltaData.sts.bSettingRefused := FALSE;
  refStarDeltaData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the star time, or the star current risen and fallen, with the main confirmed *)
IF bStarOutput AND NOT bStarWas THEN
  tStarAt := tNow;
  bSeenHigh := FALSE;
END_IF;
bStarWas := bStarOutput;
IF bStarOutput AND refStarDeltaData.set.fToDeltaBelowPct > 0.0 AND fCurrentPct >= 0.0 THEN
  IF fCurrentPct >= refStarDeltaData.set.fToDeltaBelowPct THEN
    bSeenHigh := TRUE;
  ELSIF bSeenHigh AND FeedbackOk() THEN
    bToDelta := TRUE;             (* the star current has fallen: the motor is up to speed *)
  END_IF;
END_IF;
IF bStarOutput AND tNow - tStarAt >= refStarDeltaData.set.tStarTime AND FeedbackOk() THEN
  bToDelta := TRUE;
END_IF;
refStarDeltaData.sts.bStarCurrentRisen := bSeenHigh;
IF NOT bRunOutput THEN
  bToDelta := FALSE;
END_IF;
fbCo(bRun := bRunOutput, bSelectSideB := bToDelta, bSideAFeedback := bStarFeedback, bSideBFeedback := bDeltaFeedback,
     bContactorFeedbackFitted := refStarDeltaData.set.bContactorFeedbackFitted, tAToBDeadTime := refStarDeltaData.set.tStarToDeltaDeadTime, tBToADeadTime := refStarDeltaData.set.tStarToDeltaDeadTime,
     tAuxFeedbackTimeout := refStarDeltaData.set.tAuxFeedbackTimeout);
bStarOutput := fbCo.bSideAOutput;
bDeltaOutput := fbCo.bSideBOutput;
refStarDeltaData.sts.bInStar := bStarOutput;
refStarDeltaData.sts.bInDelta := bDeltaOutput;
IF bStarOutput AND tNow - tStarAt < refStarDeltaData.set.tStarTime THEN
  refStarDeltaData.sts.tStarTimeLeft := refStarDeltaData.set.tStarTime - (tNow - tStarAt);
ELSE
  refStarDeltaData.sts.tStarTimeLeft := T#0s;
END_IF;

END_FUNCTION_BLOCK