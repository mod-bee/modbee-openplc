(* FB_Motor2Speed EXTENDS FB_Motor — a two-speed starter, Dahlander or separate windings.
Everything of FB_Motor (modes, protections, totals, refData) plus the speed choice. bRunOutput = TRUE while either speed
is asked to run; the per-speed auxes confirm running (bRunFeedback is not used).
Pins added: bAutoHighSpeed (the Auto speed when the owner gives none), bLowSpeedFeedback / bHighSpeedFeedback (the auxes),
refTwoSpeedData (its record) -> bLowSpeedOutput, bHighSpeedOutput (never on together), bBridgeOutput (the Dahlander star point, with high only),
bRunningHigh (running at high).
Speed: Hand -> set.bHandHighSelected (kept; bCmdHandLowSpeed / bCmdHandHighSpeed, or FB_LocalControl's bLowSpeedButton / bHighSpeedButton, choose it and start in Hand); Auto -> the owner's speed
(Request fSpeed: <= set.fLowSpeedPct = low, above = high; none = bAutoHighSpeed). With set.bStartInLowSpeed a start to high
runs low for set.tLowSpeedStartTime first. Low -> high waits set.tLowToHighDeadTime, high -> low set.tHighToLowDeadTime (0 = the same)
(FB_Changeover). An aux that does not follow its coil within set.tAuxFeedbackTimeout trips set.stAuxFeedbackFault (default
Manual): bError Changeover. A planned gap never counts as feedback lost. fActSpeedPct: fLowSpeedPct or 100.
Jog: FB_MotorJog, at set.bJogAtHighSpeed's speed. Its settings are kept by the block (a retained last-good copy): restored at
power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Motor2Speed EXTENDS FB_Motor IMPLEMENTS I_LocalChoice
  VAR_INPUT
    bAutoHighSpeed : BOOL := FALSE; (* Auto speed when the owner gives none *)
    bLowSpeedFeedback : BOOL; (* the low speed contactor's aux *)
    bHighSpeedFeedback : BOOL; (* the high speed contactor's aux *)
    refTwoSpeedData : REFERENCE TO ST_Motor2SpeedData; (* the two-speed record *)
  END_VAR
  VAR_OUTPUT
    bLowSpeedOutput : BOOL; (* the low speed contactor *)
    bHighSpeedOutput : BOOL; (* never with bLowSpeedOutput *)
    bBridgeOutput : BOOL; (* Dahlander: the star point, with high only *)
    bRunningHigh : BOOL; (* running at high speed *)
  END_VAR
  VAR CONSTANT
    cTwoLayout : UINT := 2; (* the layout of its own kept settings *)
  END_VAR
  VAR RETAIN
    stKeptTwo : ST_Motor2SpeedSet;
    nKeptTwoLayout : UINT;
  END_VAR
  VAR
    fbCo : FB_Changeover;
    bConfirmed : BOOL; (* an aux has confirmed this run: a later planned gap counts as running *)
    stWChangeover : ST_ProtectionWork;
    bQWas : BOOL;
    tStartAt : TIME;
    bTwoFirst : BOOL := TRUE;
  END_VAR
  VAR_TEMP
    bWantHigh : BOOL;
    tDown : TIME;
  END_VAR


(* a panel choice (FB_LocalControl bLowSpeedButton / bHighSpeedButton): in Hand, as bCmdHandLowSpeed / bCmdHandHighSpeed *)
METHOD PUBLIC Choose : BOOL
  VAR_INPUT
    eLocalChoice : E_LocalChoice;    // the local selection: Low, High, Forward, Reverse, Pos1..Pos3 or Halt
  END_VAR
  Choose := eLocalChoice = E_LocalChoice.Low OR eLocalChoice = E_LocalChoice.High;
  IF Choose AND __ISVALIDREF(refTwoSpeedData) AND __ISVALIDREF(refData) THEN
    IF refData.set.eMode = E_Mode.Hand THEN
      refTwoSpeedData.bCmdHandLowSpeed := eLocalChoice = E_LocalChoice.Low;
      refTwoSpeedData.bCmdHandHighSpeed := eLocalChoice = E_LocalChoice.High;
    END_IF;
  END_IF;
END_METHOD

METHOD PRIVATE TwoWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_Motor2SpeedSet;
  END_VAR
  TwoWhy := E_UtError.None;
  IF NOT (stS.tLowToHighDeadTime >= T#0s) THEN
    TwoWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tHighToLowDeadTime >= T#0s) THEN
    TwoWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tLowSpeedStartTime >= T#0s) THEN
    TwoWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.fLowSpeedPct >= 0.0) THEN
    TwoWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fLowSpeedPct <= 100.0) THEN
    TwoWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tAuxFeedbackTimeout > T#0s) THEN
    TwoWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stAuxFeedbackFault.tTripDelay >= T#0s) THEN
    TwoWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stAuxFeedbackFault.tAutoRecoverAfter >= T#0s) THEN
    TwoWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stAuxFeedbackFault.nMaxRetriesBeforeLockout >= 0) THEN
    TwoWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE TwoOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_Motor2SpeedSet;
  END_VAR
  TwoOk := TwoWhy(stS := stS) = E_UtError.None;
END_METHOD

(* running is the aux of the speed that runs; a planned gap in a confirmed run counts as running *)
METHOD PROTECTED OVERRIDE FeedbackOk : BOOL
  IF NOT __ISVALIDREF(refData) THEN
    FeedbackOk := FALSE;
  ELSIF NOT refData.set.bRunFeedbackFitted THEN
    FeedbackOk := bLowSpeedOutput OR bHighSpeedOutput;
  ELSE
    FeedbackOk := (bLowSpeedOutput AND bLowSpeedFeedback) OR (bHighSpeedOutput AND bHighSpeedFeedback) OR (bRunOutput AND fbCo.bPlannedGap AND bConfirmed)
                  OR (NOT bRunOutput AND (bLowSpeedFeedback OR bHighSpeedFeedback));
  END_IF;
END_METHOD

PROPERTY PUBLIC fActSpeedPct : REAL    // the speed now, % (0 when stopped)
  GET
    IF bHighSpeedOutput THEN
      fActSpeedPct := 100.0;
    ELSIF bLowSpeedOutput AND __ISVALIDREF(refTwoSpeedData) THEN
      fActSpeedPct := refTwoSpeedData.set.fLowSpeedPct;
    ELSE
      fActSpeedPct := 0.0;
    END_IF;
  END_GET
END_PROPERTY

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
  IF NOT __ISVALIDREF(refTwoSpeedData) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  F_Protect(tNow := tNow, bConditionPresent := fbCo.bAuxWrong, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
            stSettings := refTwoSpeedData.set.stAuxFeedbackFault, stStatus := refTwoSpeedData.sts.stAuxFeedbackFault, stWorking := stWChangeover);
  bTrip := stWChangeover.bTripping;
  bWarn := stWChangeover.bWarning;
  bHold := FALSE;
  IF bTrip OR bWarn THEN
    eError := E_UtError.Changeover;
  END_IF;
END_METHOD

(* Hand speed commands, before the motor runs its scan *)
IF __ISVALIDREF(refTwoSpeedData) THEN
  IF bTwoFirst THEN
    IF nKeptTwoLayout = cTwoLayout THEN
      refTwoSpeedData.set := stKeptTwo;
    ELSE
      stKeptTwo := refTwoSpeedData.set;
      nKeptTwoLayout := cTwoLayout;
    END_IF;
    bTwoFirst := FALSE;
  ELSIF TwoOk(stS := refTwoSpeedData.set) THEN
    stKeptTwo := refTwoSpeedData.set;
  ELSIF TwoOk(stS := stKeptTwo) THEN
    refTwoSpeedData.sts.eSettingRefusedErrorId := TwoWhy(stS := refTwoSpeedData.set);
    refTwoSpeedData.set := stKeptTwo;
    refTwoSpeedData.sts.bSettingRefused := TRUE;
  END_IF;
  IF bResetThisScan THEN                  // the equipment's reset clears a refused write
    refTwoSpeedData.sts.bSettingRefused := FALSE;
    refTwoSpeedData.sts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  IF refTwoSpeedData.bCmdHandLowSpeed OR refTwoSpeedData.bCmdHandHighSpeed THEN
    refTwoSpeedData.set.bHandHighSelected := refTwoSpeedData.bCmdHandHighSpeed;
    refTwoSpeedData.bCmdHandLowSpeed := FALSE;
    refTwoSpeedData.bCmdHandHighSpeed := FALSE;
    IF __ISVALIDREF(refData) THEN
      IF refData.set.eMode = E_Mode.Hand THEN
        Command(eCommand := E_EquipCmd.Start);
      END_IF;
    END_IF;
  END_IF;
END_IF;

SUPER^();                         // the motor: modes, protections, bRunOutput

IF NOT __ISVALIDREF(refTwoSpeedData) THEN
  bLowSpeedOutput := FALSE;
  bHighSpeedOutput := FALSE;
  bBridgeOutput := FALSE;
  RETURN;
END_IF;

(* the speed wanted *)
bWantHigh := bAutoHighSpeed;
IF fSpeedReq >= 0.0 AND fSpeedReq = fSpeedReq THEN
  bWantHigh := fSpeedReq > refTwoSpeedData.set.fLowSpeedPct;
END_IF;
IF __ISVALIDREF(refData) THEN     (* IEC AND does not short-circuit *)
  IF refData.set.eMode = E_Mode.Hand THEN
    bWantHigh := refTwoSpeedData.set.bHandHighSelected;
    IF bJogIn THEN bWantHigh := refTwoSpeedData.set.bJogAtHighSpeed; END_IF;   // a jog (FB_MotorJog) at its own speed
  END_IF;
END_IF;
IF bRunOutput AND NOT bQWas THEN
  tStartAt := tNow;
END_IF;
bQWas := bRunOutput;
IF bWantHigh AND refTwoSpeedData.set.bStartInLowSpeed AND tNow - tStartAt < refTwoSpeedData.set.tLowSpeedStartTime THEN
  bWantHigh := FALSE;             (* a start to high runs low first *)
END_IF;
tDown := refTwoSpeedData.set.tHighToLowDeadTime;
IF tDown <= T#0s THEN
  tDown := refTwoSpeedData.set.tLowToHighDeadTime;
END_IF;
fbCo(bRun := bRunOutput, bSelectSideB := bWantHigh, bSideAFeedback := bLowSpeedFeedback, bSideBFeedback := bHighSpeedFeedback,
     bContactorFeedbackFitted := refData.set.bRunFeedbackFitted, tAToBDeadTime := refTwoSpeedData.set.tLowToHighDeadTime, tBToADeadTime := tDown,
     tAuxFeedbackTimeout := refTwoSpeedData.set.tAuxFeedbackTimeout);
bLowSpeedOutput := fbCo.bSideAOutput;
bHighSpeedOutput := fbCo.bSideBOutput;
bConfirmed := bRunOutput AND (bConfirmed OR (bLowSpeedOutput AND bLowSpeedFeedback) OR (bHighSpeedOutput AND bHighSpeedFeedback)
                      OR NOT refData.set.bRunFeedbackFitted);
bBridgeOutput := bHighSpeedOutput AND refTwoSpeedData.set.bDahlanderWinding;
bRunningHigh := bHighSpeedOutput;
refTwoSpeedData.sts.bRunningHigh := bHighSpeedOutput;

END_FUNCTION_BLOCK