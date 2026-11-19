(* FB_MotorRev EXTENDS FB_Motor — a reversing starter.
Everything of FB_Motor (modes, protections, totals, refData) plus the direction. bRunOutput = TRUE while either direction
is asked to run; the direction auxes confirm running (bRunFeedback is not used).
Pins added: bAutoReverse (the Auto direction), bForwardFeedback / bReverseFeedback (the auxes), bForwardLimitSwitch / bReverseLimitSwitch (end
of travel: that direction stops and will not start), refReversingData (its record) -> bForwardOutput, bReverseOutput (never on together),
bRunningReverse (running in reverse).
Direction: Hand -> set.bHandReverseSelected (kept; bCmdHandForward / bCmdHandReverse, or FB_LocalControl's bReverseButton, choose it and start in Hand); Auto -> bAutoReverse.
A change waits set.tReversingDeadTime (FB_Changeover); with set.bStopBeforeReverse a direction change stops and needs
a new start (the run request going away). An aux that does not follow its coil within set.tAuxFeedbackTimeout trips
set.stAuxFeedbackFault (default Manual): bError Changeover. A planned gap never counts as feedback lost.
Jog: FB_MotorJog, in reverse with its bJogReverse. Its settings are kept by the block (a retained last-good copy): restored at
power-up, a bad write put back. *)

FUNCTION_BLOCK FB_MotorRev EXTENDS FB_Motor IMPLEMENTS I_LocalChoice
  VAR_INPUT
    bAutoReverse : BOOL := FALSE; (* Auto direction *)
    bForwardFeedback : BOOL; (* the forward contactor's aux *)
    bReverseFeedback : BOOL; (* the reverse contactor's aux *)
    bForwardLimitSwitch : BOOL; (* end of travel forward *)
    bReverseLimitSwitch : BOOL; (* end of travel reverse: that direction stops and will not start *)
    refReversingData : REFERENCE TO ST_MotorRevData; (* the reversing record *)
  END_VAR
  VAR_OUTPUT
    bForwardOutput : BOOL; (* the forward contactor *)
    bReverseOutput : BOOL; (* never with bForwardOutput *)
    bRunningReverse : BOOL; (* running in reverse *)
  END_VAR
  VAR CONSTANT
    cRevLayout : UINT := 2; (* the layout of its own kept settings *)
  END_VAR
  VAR RETAIN
    stKeptRev : ST_MotorRevSet;
    nKeptRevLayout : UINT;
  END_VAR
  VAR
    fbCo : FB_Changeover;
    bConfirmed : BOOL; (* an aux has confirmed this run: a later planned gap counts as running *)
    stWChangeover : ST_ProtectionWork;
    bWantRev : BOOL; (* the direction wanted this scan *)
    bRunRev : BOOL; (* the direction running (or about to) *)
    bDirStop : BOOL; (* stopped for a direction change: waits for the request to go *)
    bRevFirst : BOOL := TRUE;
  END_VAR


(* a panel choice (FB_LocalControl bReverseButton): in Hand, as bCmdHandForward / bCmdHandReverse *)
METHOD PUBLIC Choose : BOOL
  VAR_INPUT
    eLocalChoice : E_LocalChoice;    // the local selection: Low, High, Forward, Reverse, Pos1..Pos3 or Halt
  END_VAR
  Choose := eLocalChoice = E_LocalChoice.Forward OR eLocalChoice = E_LocalChoice.Reverse;
  IF Choose AND __ISVALIDREF(refReversingData) AND __ISVALIDREF(refData) THEN
    IF refData.set.eMode = E_Mode.Hand THEN
      refReversingData.bCmdHandForward := eLocalChoice = E_LocalChoice.Forward;
      refReversingData.bCmdHandReverse := eLocalChoice = E_LocalChoice.Reverse;
    END_IF;
  END_IF;
END_METHOD

METHOD PRIVATE RevWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_MotorRevSet;
  END_VAR
  RevWhy := E_UtError.None;
  IF NOT (stS.tReversingDeadTime >= T#0s) THEN
    RevWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tAuxFeedbackTimeout > T#0s) THEN
    RevWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stAuxFeedbackFault.tTripDelay >= T#0s) THEN
    RevWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stAuxFeedbackFault.tAutoRecoverAfter >= T#0s) THEN
    RevWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stAuxFeedbackFault.nMaxRetriesBeforeLockout >= 0) THEN
    RevWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE RevOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MotorRevSet;
  END_VAR
  RevOk := RevWhy(stS := stS) = E_UtError.None;
END_METHOD

(* running is the aux of the direction that runs; a planned gap in a confirmed run counts as running *)
METHOD PROTECTED OVERRIDE FeedbackOk : BOOL
  IF NOT __ISVALIDREF(refData) THEN
    FeedbackOk := FALSE;
  ELSIF NOT refData.set.bRunFeedbackFitted THEN
    FeedbackOk := bForwardOutput OR bReverseOutput;
  ELSE
    FeedbackOk := (bForwardOutput AND bForwardFeedback) OR (bReverseOutput AND bReverseFeedback) OR (bRunOutput AND fbCo.bPlannedGap AND bConfirmed)
                  OR (NOT bRunOutput AND (bForwardFeedback OR bReverseFeedback));
  END_IF;
END_METHOD

(* the end limits and a stop for a direction change hold the run *)
METHOD PROTECTED OVERRIDE ShapeRun : BOOL
  VAR_INPUT
    bWant : BOOL;
  END_VAR
  IF NOT bWant THEN
    bDirStop := FALSE;
  END_IF;
  ShapeRun := SUPER^.ShapeRun(bWant := bWant) AND NOT bDirStop
              AND NOT (bWantRev AND bReverseLimitSwitch) AND NOT (NOT bWantRev AND bForwardLimitSwitch);
END_METHOD

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
  IF NOT __ISVALIDREF(refReversingData) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  F_Protect(tNow := tNow, bConditionPresent := fbCo.bAuxWrong, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
            stSettings := refReversingData.set.stAuxFeedbackFault, stStatus := refReversingData.sts.stAuxFeedbackFault, stWorking := stWChangeover);
  bTrip := stWChangeover.bTripping;
  bWarn := stWChangeover.bWarning;
  bHold := FALSE;
  IF bTrip OR bWarn THEN
    eError := E_UtError.Changeover;
  END_IF;
END_METHOD

(* the direction wanted, before the motor runs its scan *)
IF __ISVALIDREF(refReversingData) THEN
  IF bRevFirst THEN
    IF nKeptRevLayout = cRevLayout THEN
      refReversingData.set := stKeptRev;
    ELSE
      stKeptRev := refReversingData.set;
      nKeptRevLayout := cRevLayout;
    END_IF;
    bRevFirst := FALSE;
  ELSIF RevOk(stS := refReversingData.set) THEN
    stKeptRev := refReversingData.set;
  ELSIF RevOk(stS := stKeptRev) THEN
    refReversingData.sts.eSettingRefusedErrorId := RevWhy(stS := refReversingData.set);
    refReversingData.set := stKeptRev;
    refReversingData.sts.bSettingRefused := TRUE;
  END_IF;
  IF bResetThisScan THEN                  // the equipment's reset clears a refused write
    refReversingData.sts.bSettingRefused := FALSE;
    refReversingData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  IF refReversingData.bCmdHandForward OR refReversingData.bCmdHandReverse THEN
    refReversingData.set.bHandReverseSelected := refReversingData.bCmdHandReverse;
    refReversingData.bCmdHandForward := FALSE;
    refReversingData.bCmdHandReverse := FALSE;
    IF __ISVALIDREF(refData) THEN
      IF refData.set.eMode = E_Mode.Hand THEN
        Command(eCommand := E_EquipCmd.Start);
      END_IF;
    END_IF;
  END_IF;
  bWantRev := bAutoReverse;
  IF __ISVALIDREF(refData) THEN
    IF refData.set.eMode = E_Mode.Hand THEN
      bWantRev := refReversingData.set.bHandReverseSelected;
      IF bJogIn THEN bWantRev := bJogRevIn; END_IF;   // a jog (FB_MotorJog): its bJogReverse
    END_IF;
  END_IF;
  IF bRunOutput AND bWantRev <> bRunRev AND refReversingData.set.bStopBeforeReverse THEN
    bDirStop := TRUE;             (* stop; a new start is needed *)
  END_IF;
END_IF;

SUPER^();                         // the motor: modes, protections, ShapeRun, bRunOutput

IF NOT __ISVALIDREF(refReversingData) THEN
  bForwardOutput := FALSE;
  bReverseOutput := FALSE;
  RETURN;
END_IF;
IF NOT bRunOutput OR NOT bDirStop THEN
  bRunRev := bWantRev;
END_IF;
fbCo(bRun := bRunOutput AND NOT (bRunRev AND bReverseLimitSwitch) AND NOT (NOT bRunRev AND bForwardLimitSwitch), bSelectSideB := bRunRev,
     bSideAFeedback := bForwardFeedback, bSideBFeedback := bReverseFeedback, bContactorFeedbackFitted := refData.set.bRunFeedbackFitted,
     tAToBDeadTime := refReversingData.set.tReversingDeadTime, tBToADeadTime := refReversingData.set.tReversingDeadTime,
     tAuxFeedbackTimeout := refReversingData.set.tAuxFeedbackTimeout);
bForwardOutput := fbCo.bSideAOutput;
bReverseOutput := fbCo.bSideBOutput;
bConfirmed := bRunOutput AND (bConfirmed OR (bForwardOutput AND bForwardFeedback) OR (bReverseOutput AND bReverseFeedback)
                      OR NOT refData.set.bRunFeedbackFitted);
bRunningReverse := bReverseOutput;
refReversingData.sts.bRunningReverse := bReverseOutput;
refReversingData.sts.bAtForwardLimit := bForwardLimitSwitch;
refReversingData.sts.bAtReverseLimit := bReverseLimitSwitch;

END_FUNCTION_BLOCK