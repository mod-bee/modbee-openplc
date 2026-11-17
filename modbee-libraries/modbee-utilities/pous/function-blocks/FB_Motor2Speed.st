(* FB_Motor2Speed EXTENDS FB_Motor — a two-speed starter, Dahlander or separate windings.
Everything of FB_Motor (modes, protections, totals, refData) plus the speed choice. bQ = TRUE while either speed
is asked to run; the per-speed auxes confirm running (bFeedback is not used).
Pins added: bAutoHigh (the Auto speed when the owner gives none), bFeedbackLow / bFeedbackHigh (the auxes),
refTwo (its record) -> bQLow, bQHigh (never on together), bQBridge (the Dahlander star point, with high only),
bHighSpeed (running at high).
Speed: Hand -> set.bHandHigh (kept; bCmdLow / bCmdHigh, or FB_LocalControl's bLow / bHigh, choose it and start in Hand); Auto -> the owner's speed
(Request fSpeed: <= set.fLowSpeedPct = low, above = high; none = bAutoHigh). With set.bStartInLow a start to high
runs low for set.tLowStart first. Low -> high waits set.tSpeedChange, high -> low set.tDownChange (0 = the same)
(FB_Changeover). An aux that does not follow its coil within set.tChangeover trips set.stChangeover (default
Manual): bError Changeover. A planned gap never counts as feedback lost. fActSpeed: fLowSpeedPct or 100.
Jog: FB_MotorJog. Its settings are kept by the block (a retained last-good copy): restored at
power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Motor2Speed EXTENDS FB_Motor IMPLEMENTS I_LocalChoice
  VAR_INPUT
    bAutoHigh : BOOL := FALSE; (* Auto speed when the owner gives none *)
    bFeedbackLow : BOOL;
    bFeedbackHigh : BOOL;
    refTwo : REFERENCE TO ST_Motor2SpeedData;
  END_VAR
  VAR_OUTPUT
    bQLow : BOOL;
    bQHigh : BOOL; (* never with bQLow *)
    bQBridge : BOOL; (* Dahlander: the star point, with high only *)
    bHighSpeed : BOOL;
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


(* a panel choice (FB_LocalControl bLow / bHigh): in Hand, as bCmdLow / bCmdHigh *)
METHOD PUBLIC Choose : BOOL
  VAR_INPUT
    eChoice : E_LocalChoice;
  END_VAR
  Choose := eChoice = E_LocalChoice.Low OR eChoice = E_LocalChoice.High;
  IF Choose AND __ISVALIDREF(refTwo) AND __ISVALIDREF(refData) THEN
    IF refData.set.eMode = E_Mode.Hand THEN
      refTwo.bCmdLow := eChoice = E_LocalChoice.Low;
      refTwo.bCmdHigh := eChoice = E_LocalChoice.High;
    END_IF;
  END_IF;
END_METHOD

METHOD PRIVATE TwoOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_Motor2SpeedSet;
  END_VAR
  TwoOk := stS.tSpeedChange >= T#0s AND stS.tDownChange >= T#0s AND stS.tLowStart >= T#0s
           AND stS.fLowSpeedPct >= 0.0 AND stS.fLowSpeedPct <= 100.0 AND stS.tChangeover > T#0s
           AND stS.stChangeover.tDelay >= T#0s AND stS.stChangeover.tRecover >= T#0s
           AND stS.stChangeover.nMaxRetries >= 0;
END_METHOD

(* running is the aux of the speed that runs; a planned gap in a confirmed run counts as running *)
METHOD PROTECTED OVERRIDE FeedbackOk : BOOL
  IF NOT __ISVALIDREF(refData) THEN
    FeedbackOk := FALSE;
  ELSIF NOT refData.set.bUseFeedback THEN
    FeedbackOk := bQLow OR bQHigh;
  ELSE
    FeedbackOk := (bQLow AND bFeedbackLow) OR (bQHigh AND bFeedbackHigh) OR (bQ AND fbCo.bInGap AND bConfirmed)
                  OR (NOT bQ AND (bFeedbackLow OR bFeedbackHigh));
  END_IF;
END_METHOD

PROPERTY PUBLIC fActSpeed : REAL
  GET
    IF bQHigh THEN
      fActSpeed := 100.0;
    ELSIF bQLow AND __ISVALIDREF(refTwo) THEN
      fActSpeed := refTwo.set.fLowSpeedPct;
    ELSE
      fActSpeed := 0.0;
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
  IF NOT __ISVALIDREF(refTwo) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  F_Protect(tNow := tNow, bCause := fbCo.bCause, bResetReq := bReset, tRetryWindow := T#1h,
            stSet := refTwo.set.stChangeover, stSts := refTwo.sts.stChangeover, stWork := stWChangeover);
  bTrip := stWChangeover.bTrip;
  bWarn := stWChangeover.bWarn;
  bHold := FALSE;
  IF bTrip OR bWarn THEN
    eError := E_UtError.Changeover;
  END_IF;
END_METHOD

(* Hand speed commands, before the motor runs its scan *)
IF __ISVALIDREF(refTwo) THEN
  IF bTwoFirst THEN
    IF nKeptTwoLayout = cLayout THEN
      refTwo.set := stKeptTwo;
    ELSE
      stKeptTwo := refTwo.set;
      nKeptTwoLayout := cLayout;
    END_IF;
    bTwoFirst := FALSE;
  ELSIF TwoOk(stS := refTwo.set) THEN
    stKeptTwo := refTwo.set;
  ELSIF TwoOk(stS := stKeptTwo) THEN
    refTwo.set := stKeptTwo;
    refTwo.sts.bRefused := TRUE;
  END_IF;
  IF refTwo.bCmdLow OR refTwo.bCmdHigh THEN
    refTwo.set.bHandHigh := refTwo.bCmdHigh;
    refTwo.bCmdLow := FALSE;
    refTwo.bCmdHigh := FALSE;
    IF __ISVALIDREF(refData) THEN
      IF refData.set.eMode = E_Mode.Hand THEN
        Command(eCmd := E_EquipCmd.Start);
      END_IF;
    END_IF;
  END_IF;
END_IF;

SUPER^();                         // the motor: modes, protections, bQ

IF NOT __ISVALIDREF(refTwo) THEN
  bQLow := FALSE;
  bQHigh := FALSE;
  bQBridge := FALSE;
  RETURN;
END_IF;

(* the speed wanted *)
bWantHigh := bAutoHigh;
IF fSpeedReq >= 0.0 AND fSpeedReq = fSpeedReq THEN
  bWantHigh := fSpeedReq > refTwo.set.fLowSpeedPct;
END_IF;
IF __ISVALIDREF(refData) THEN     (* IEC AND does not short-circuit *)
  IF refData.set.eMode = E_Mode.Hand THEN
    bWantHigh := refTwo.set.bHandHigh;
  END_IF;
END_IF;
IF bQ AND NOT bQWas THEN
  tStartAt := tNow;
END_IF;
bQWas := bQ;
IF bWantHigh AND refTwo.set.bStartInLow AND tNow - tStartAt < refTwo.set.tLowStart THEN
  bWantHigh := FALSE;             (* a start to high runs low first *)
END_IF;
tDown := refTwo.set.tDownChange;
IF tDown <= T#0s THEN
  tDown := refTwo.set.tSpeedChange;
END_IF;
fbCo(bRun := bQ, bWantB := bWantHigh, bFbA := bFeedbackLow, bFbB := bFeedbackHigh,
     bUseFb := refData.set.bUseFeedback, tGapAB := refTwo.set.tSpeedChange, tGapBA := tDown,
     tOpenTime := refTwo.set.tChangeover);
bQLow := fbCo.bQA;
bQHigh := fbCo.bQB;
bConfirmed := bQ AND (bConfirmed OR (bQLow AND bFeedbackLow) OR (bQHigh AND bFeedbackHigh)
                      OR NOT refData.set.bUseFeedback);
bQBridge := bQHigh AND refTwo.set.bDahlander;
bHighSpeed := bQHigh;
refTwo.sts.bHighSpeed := bQHigh;

END_FUNCTION_BLOCK