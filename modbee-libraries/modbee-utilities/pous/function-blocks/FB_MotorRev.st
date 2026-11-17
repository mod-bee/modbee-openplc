(* FB_MotorRev EXTENDS FB_Motor — a reversing starter (src-v2 UT_MOTOR_REV).
Everything of FB_Motor (modes, protections, totals, refData) plus the direction. bQ = TRUE while either direction
is asked to run; the direction auxes confirm running (bFeedback is not used).
Pins added: bReverse (the Auto direction), bFeedbackFwd / bFeedbackRev (the auxes), bLimitFwd / bLimitRev (end
of travel: that direction stops and will not start), refRev (its record) -> bQFwd, bQRev (never on together),
bReversed (running in reverse).
Direction: Hand -> set.bHandReverse (kept; bCmdFwd / bCmdRev, or FB_LocalControl's bRev, choose it and start in Hand); Auto -> bReverse.
A change waits set.tReversalDelay (FB_Changeover); with set.bStopBeforeReverse a direction change stops and needs
a new start (the run request going away). An aux that does not follow its coil within set.tChangeover trips
set.stChangeover (default Manual): bError Changeover. A planned gap never counts as feedback lost.
Jog: FB_MotorJog. Its settings are kept by the block (a retained last-good copy): restored at
power-up, a bad write put back. *)

FUNCTION_BLOCK FB_MotorRev EXTENDS FB_Motor IMPLEMENTS I_LocalChoice
  VAR_INPUT
    bReverse : BOOL := FALSE; (* Auto direction *)
    bFeedbackFwd : BOOL;
    bFeedbackRev : BOOL;
    bLimitFwd : BOOL; (* end of travel forward *)
    bLimitRev : BOOL;
    refRev : REFERENCE TO ST_MotorRevData;
  END_VAR
  VAR_OUTPUT
    bQFwd : BOOL;
    bQRev : BOOL; (* never with bQFwd *)
    bReversed : BOOL;
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


(* a panel choice (FB_LocalControl bRev): in Hand, as bCmdFwd / bCmdRev *)
METHOD PUBLIC Choose : BOOL
  VAR_INPUT
    eChoice : E_LocalChoice;
  END_VAR
  Choose := eChoice = E_LocalChoice.Forward OR eChoice = E_LocalChoice.Reverse;
  IF Choose AND __ISVALIDREF(refRev) AND __ISVALIDREF(refData) THEN
    IF refData.set.eMode = E_Mode.Hand THEN
      refRev.bCmdFwd := eChoice = E_LocalChoice.Forward;
      refRev.bCmdRev := eChoice = E_LocalChoice.Reverse;
    END_IF;
  END_IF;
END_METHOD

METHOD PRIVATE RevOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MotorRevSet;
  END_VAR
  RevOk := stS.tReversalDelay >= T#0s AND stS.tChangeover > T#0s
           AND stS.stChangeover.tDelay >= T#0s AND stS.stChangeover.tRecover >= T#0s
           AND stS.stChangeover.nMaxRetries >= 0;
END_METHOD

(* running is the aux of the direction that runs; a planned gap in a confirmed run counts as running *)
METHOD PROTECTED OVERRIDE FeedbackOk : BOOL
  IF NOT __ISVALIDREF(refData) THEN
    FeedbackOk := FALSE;
  ELSIF NOT refData.set.bUseFeedback THEN
    FeedbackOk := bQFwd OR bQRev;
  ELSE
    FeedbackOk := (bQFwd AND bFeedbackFwd) OR (bQRev AND bFeedbackRev) OR (bQ AND fbCo.bInGap AND bConfirmed)
                  OR (NOT bQ AND (bFeedbackFwd OR bFeedbackRev));
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
              AND NOT (bWantRev AND bLimitRev) AND NOT (NOT bWantRev AND bLimitFwd);
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
  IF NOT __ISVALIDREF(refRev) THEN
    bTrip := TRUE;
    eError := E_UtError.NoRecord;
    RETURN;
  END_IF;
  F_Protect(tNow := tNow, bCause := fbCo.bCause, bResetReq := bReset, tRetryWindow := T#1h,
            stSet := refRev.set.stChangeover, stSts := refRev.sts.stChangeover, stWork := stWChangeover);
  bTrip := stWChangeover.bTrip;
  bWarn := stWChangeover.bWarn;
  bHold := FALSE;
  IF bTrip OR bWarn THEN
    eError := E_UtError.Changeover;
  END_IF;
END_METHOD

(* the direction wanted, before the motor runs its scan *)
IF __ISVALIDREF(refRev) THEN
  IF bRevFirst THEN
    IF nKeptRevLayout = cLayout THEN
      refRev.set := stKeptRev;
    ELSE
      stKeptRev := refRev.set;
      nKeptRevLayout := cLayout;
    END_IF;
    bRevFirst := FALSE;
  ELSIF RevOk(stS := refRev.set) THEN
    stKeptRev := refRev.set;
  ELSIF RevOk(stS := stKeptRev) THEN
    refRev.set := stKeptRev;
    refRev.sts.bRefused := TRUE;
  END_IF;
  IF refRev.bCmdFwd OR refRev.bCmdRev THEN
    refRev.set.bHandReverse := refRev.bCmdRev;
    refRev.bCmdFwd := FALSE;
    refRev.bCmdRev := FALSE;
    IF __ISVALIDREF(refData) THEN
      IF refData.set.eMode = E_Mode.Hand THEN
        Command(eCmd := E_EquipCmd.Start);
      END_IF;
    END_IF;
  END_IF;
  bWantRev := bReverse;
  IF __ISVALIDREF(refData) THEN
    IF refData.set.eMode = E_Mode.Hand THEN
      bWantRev := refRev.set.bHandReverse;
    END_IF;
  END_IF;
  IF bQ AND bWantRev <> bRunRev AND refRev.set.bStopBeforeReverse THEN
    bDirStop := TRUE;             (* stop; a new start is needed *)
  END_IF;
END_IF;

SUPER^();                         // the motor: modes, protections, ShapeRun, bQ

IF NOT __ISVALIDREF(refRev) THEN
  bQFwd := FALSE;
  bQRev := FALSE;
  RETURN;
END_IF;
IF NOT bQ OR NOT bDirStop THEN
  bRunRev := bWantRev;
END_IF;
fbCo(bRun := bQ AND NOT (bRunRev AND bLimitRev) AND NOT (NOT bRunRev AND bLimitFwd), bWantB := bRunRev,
     bFbA := bFeedbackFwd, bFbB := bFeedbackRev, bUseFb := refData.set.bUseFeedback,
     tGapAB := refRev.set.tReversalDelay, tGapBA := refRev.set.tReversalDelay,
     tOpenTime := refRev.set.tChangeover);
bQFwd := fbCo.bQA;
bQRev := fbCo.bQB;
bConfirmed := bQ AND (bConfirmed OR (bQFwd AND bFeedbackFwd) OR (bQRev AND bFeedbackRev)
                      OR NOT refData.set.bUseFeedback);
bReversed := bQRev;
refRev.sts.bReverse := bQRev;
refRev.sts.bAtLimitFwd := bLimitFwd;
refRev.sts.bAtLimitRev := bLimitRev;

END_FUNCTION_BLOCK