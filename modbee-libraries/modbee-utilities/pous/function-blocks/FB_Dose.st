(* FB_Dose — the engine every dosing block shares (FB_DoseBatch, FB_DoseFlow, FB_DoseTimed): written once.
bRun / bStart / bStop / bResetFaults and the record's commands (bCmdStart, bCmdStop, bCmdPause, bCmdResetFaults: once per
write); bInterlock FALSE stops the pump in every variant (Flow / Timed resume by themselves, a Batch is held);
bPermissive FALSE holds back a dose start; bPause and bCmdPause (until the next start) pause; bStop, bCmdStop, bAbortWhileHeld,
the record's bCmdAbort (stop reason Abort), set.bDosingEnabled FALSE end a dose (a held bRun must drop before it doses again); bStockLowSwitch -> set.stStockLowFault;
set.stMaxDoseTimeFault and set.fMaxQuantityPerDose cap a dose. ipDosingPump (optional): Request(bRun := bPumpRunCommand, bPause := NOT bInterlock,
fSpeed := fPumpSpeedPct); dosing counts only while it runs.
Modes (set.eMode, kept; the record's nCmdDoseMode 0 Off / 1 Hand / 2 Auto, once, or a Command from FB_LocalControl,
which drives a dose like a pump: IMPLEMENTS I_Equipment): Auto doses as above; Hand: a start (bStart, bCmdStart,
the panel's start button) runs the pump at set.fHandSpeedPct % until a stop, set.tMaxHandRunTime (0 = no limit), the
interlock FALSE, an abort, set.bDosingEnabled FALSE, a stop-trip or the mode left; with set.bHandNeedsCarrier the carrier
must be proven (Flow / Timed; a Batch has none), else the pump waits (Held); a Hand run counts into the totals but
is no dose (nDoseCount); Off: nothing doses. Hand never resumes after a power cut. An owner's Request(bRun) is a
bRun (bPause = not asked); a variant's own pins and records work in Auto only.
tot (millionths of a unit, and the doses) is kept at each dose end and every hour.
A variant calls, every scan:  bResetFaults := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);
                              (its settings, its dosing: bBusy, bPaused, bPumpGo, fPumpSpeedPct, fDosed, fDlv, eEnd,
                               bDoneNow, its protections)
                              Finish(refCmd, refSet, refSts, bOk, its trip / warning and codes, its phase,
                                     its time left); *)

FUNCTION_BLOCK ABSTRACT FB_Dose EXTENDS FB_Object IMPLEMENTS I_Equipment
  VAR_INPUT
    bRun : BOOL; (* Batch: rising starts a dose; Flow / Timed: doses while TRUE *)
    bStart : BOOL; (* rising: Batch starts / resumes; Flow / Timed: a run latched until a stop *)
    bStop : BOOL; (* rising: ends the dose (a held bRun must drop first) *)
    bResetFaults : BOOL; (* rising: resets trips whose cause has gone *)
    bInterlock : BOOL := TRUE; (* FALSE: the pump off *)
    bPermissive : BOOL := TRUE; (* FALSE: holds back a dose start *)
    bStockLowSwitch : BOOL; (* the chemical stock is low (a level switch) *)
    bPause : BOOL; (* pause *)
    bAbortWhileHeld : BOOL; (* end, refuse a start *)
    ipDosingPump : I_Equipment; (* optional: the dosing pump *)
  END_VAR
  VAR_OUTPUT
    bPumpRunCommand : BOOL; (* run the dosing pump *)
    fPumpSpeedPct : REAL; (* % *)
    bBusy : BOOL; (* a dose is on *)
    bDone : BOOL; (* a Batch dose completed (one scan) *)
  END_VAR
  VAR RETAIN
    stKeptTot : ST_DoseTot;
    nKeptTotLayout : UINT;
  END_VAR
  VAR CONSTANT
    cTotLayout : UINT := 1;
  END_VAR
  VAR
    bAbortNow : BOOL; (* bAbortWhileHeld or the record's bCmdAbort, this scan *)
    tPrevAt : TIME;
    tStepT : TIME; (* this scan's time step *)
    fStepS : LREAL; (* the same in seconds *)
    bStartPrev : BOOL; (* the pins' edges (a method cannot read an R_EDGE input) *)
    bStopPrev : BOOL;
    bResetPrev : BOOL;
    bStartSeen : BOOL;
    bStopSeen : BOOL;
    bHoldSeen : BOOL;
    bResetSeen : BOOL;
    bStartReq : BOOL; (* this scan *)
    bStopReq : BOOL;
    bResetReq : BOOL;
    bHoldLatch : BOOL;
    bStartLatch : BOOL; (* Flow / Timed: a started run *)
    bRunBlocked : BOOL; (* a stop while bRun is held: until it drops *)
    bRunReq : BOOL; (* Flow / Timed: dose now *)
    bRunPrev : BOOL;
    bRunEdge : BOOL;
    bEndReq : BOOL; (* a dose must end this scan *)
    bPaused : BOOL;
    bPumpGo : BOOL;
    fDosed : LREAL; (* dosed this scan *)
    fDlv : LREAL; (* this dose so far *)
    bDoneNow : BOOL;
    eEnd : E_StopReason;
    bBusyPrev : BOOL;
    tDoseStart : TIME;
    bQtyEnd : BOOL; (* fMaxQuantityPerDose reached: end the dose next scan *)
    bMaxTrip : BOOL;
    bStockTrip : BOOL;
    bTripHold : BOOL; (* a trip holds the dose (the variant adds its own) *)
    bCounting : BOOL; (* the pump runs: dosing counts *)
    stWMax : ST_ProtectionWork;
    stWStock : ST_ProtectionWork;
    fTotFrac : LREAL;
    tTotKeptAt : TIME;
    bRunIn : BOOL; (* bRun or an owner's Request *)
    bOwnRun : BOOL;
    bOwnSeen : BOOL;
    eCmdPend : E_EquipCmd; (* a Command, applied in the next cycle *)
    eModeNow : E_Mode;
    bHandRun : BOOL;
    bHandShow : BOOL; (* bBusy was set for a Hand run (cleared at the next scan) *)
    bHandWas : BOOL;
    bStartHand : BOOL; (* a start this scan, whatever the mode *)
    tHandAt : TIME;
    eHandEnd : E_StopReason;
    eStopShown : E_StopReason;
    bHandCarrier : BOOL; (* the carrier is proven: a variant with a carrier sets it every scan *)
  END_VAR


(* I_Equipment: an owner's request, a Command (FB_LocalControl) and the state, as a pump's *)
METHOD PUBLIC Request : E_UtError
  VAR_INPUT
    bRun : BOOL;    // run wanted
    bHoldOff : BOOL;    // held off, still linked to the owner
    fSpeedSetpointPct : REAL := -1.0;    // speed wanted; below 0 = its own
    bOverflowUrgent : BOOL;    // an overflow call: a part's start hold does not hold it
  END_VAR
  bOwnRun := bRun AND NOT bHoldOff;
  bOwnSeen := TRUE;
  Request := eErrorId;
END_METHOD

METHOD PUBLIC Command
  VAR_INPUT
    eCommand : E_EquipCmd;    // a record command applied in the block's next cycle
  END_VAR
  eCmdPend := eCommand;
END_METHOD

PROPERTY PUBLIC eActMode : E_Mode    // the mode it is in now
  GET
    eActMode := eModeNow;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsRunning : BOOL    // running now
  GET
    bIsRunning := bBusy AND bPumpGo;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsReady : BOOL    // could start now if asked
  GET
    bIsReady := NOT bError AND eModeNow <> E_Mode.Off;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsAvailable : BOOL    // in Auto, not tripped, not interlocked
  GET
    bIsAvailable := NOT bError AND eModeNow = E_Mode.Auto;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsAuto : BOOL    // in Auto now
  GET
    bIsAuto := eModeNow = E_Mode.Auto;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFaulted : BOOL    // a trip or setting fault is active
  GET
    bIsFaulted := bError;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eActError : E_UtError    // the error shown now
  GET
    eActError := eErrorId;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eActStopReason : E_StopReason    // why it last stopped (None while one runs)
  GET
    eActStopReason := eStopShown;
  END_GET
END_PROPERTY
PROPERTY PUBLIC fActRunHours : REAL   // a dose counts no hours
  GET
    fActRunHours := 0.0;
  END_GET
END_PROPERTY

(* the shared settings are good *)
METHOD PROTECTED FINAL BaseSetWhy : E_UtError
  VAR_INPUT
    refSet : REFERENCE TO ST_DoseSet;
  END_VAR
  BaseSetWhy := E_UtError.None;
  IF NOT (refSet.fFlowAtFullSpeed >= 0.0) THEN
    BaseSetWhy := E_UtError.BelowMin;
  ELSIF NOT (refSet.fFlowAtFullSpeed <= REAL#3.4E38) THEN
    BaseSetWhy := E_UtError.AboveMax;
  ELSIF NOT (refSet.fMaxQuantityPerDose >= 0.0) THEN
    BaseSetWhy := E_UtError.BelowMin;
  ELSIF NOT (refSet.fMaxQuantityPerDose <= 1.0E15) THEN
    BaseSetWhy := E_UtError.AboveMax;
  ELSIF NOT (refSet.tRetryCountWindow >= T#0s) THEN
    BaseSetWhy := E_UtError.TimeBad;
  ELSIF NOT (refSet.eMode = E_Mode.Off OR refSet.eMode = E_Mode.Hand OR refSet.eMode = E_Mode.Auto) THEN
    BaseSetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (refSet.fHandSpeedPct >= 0.0) THEN
    BaseSetWhy := E_UtError.BelowMin;
  ELSIF NOT (refSet.fHandSpeedPct <= 100.0) THEN
    BaseSetWhy := E_UtError.AboveMax;
  ELSIF NOT (refSet.tMaxHandRunTime >= T#0s) THEN
    BaseSetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PROTECTED FINAL BaseSetOk : BOOL
  VAR_INPUT
    refSet : REFERENCE TO ST_DoseSet;
  END_VAR
  BaseSetOk := BaseSetWhy(refSet := refSet) = E_UtError.None;
END_METHOD

(* why the dose ends now (bEndReq, or the run request gone) *)
METHOD PROTECTED FINAL EndWhy : E_StopReason
  VAR_INPUT
    refSet : REFERENCE TO ST_DoseSet;
  END_VAR
  IF bMaxTrip THEN
    EndWhy := E_StopReason.MaxRun;
  ELSIF bQtyEnd THEN
    EndWhy := E_StopReason.MaxQuantity;
  ELSIF bAbortNow THEN
    EndWhy := E_StopReason.Abort;
  ELSIF NOT refSet.bDosingEnabled THEN
    EndWhy := E_StopReason.Off;
  ELSIF bStopReq THEN
    EndWhy := E_StopReason.Manual;
  ELSE
    EndWhy := E_StopReason.Request;
  END_IF;
END_METHOD

METHOD PROTECTED FINAL Begin : BOOL
  VAR_INPUT
    refCmd : REFERENCE TO ST_DoseData;
    refSet : REFERENCE TO ST_DoseSet;
    refSts : REFERENCE TO ST_DoseSts;
  END_VAR
  tNow := TIME();
  IF bHandShow THEN
    bBusy := FALSE;               (* a Hand run showed it busy: the variant's own state is idle *)
    bHandShow := FALSE;
  END_IF;
  IF bFirstScan THEN
    tStepT := T#0s;
    bRunPrev := bRun OR bOwnRun;  (* a bRun already on at power-up is not an edge *)
    tTotKeptAt := tNow;
    IF nKeptTotLayout = cTotLayout THEN
      refCmd.tot := stKeptTot;
    ELSE
      stKeptTot := refCmd.tot;
      nKeptTotLayout := cTotLayout;
    END_IF;
  ELSE
    tStepT := tNow - tPrevAt;
    IF tStepT < T#0s THEN
      tStepT := T#0s;
    END_IF;
  END_IF;
  tPrevAt := tNow;
  fStepS := LINT_TO_LREAL(TIME_TO_LINT(tStepT)) / 1000.0;
  IF NOT bOwnSeen THEN
    bOwnRun := FALSE;             (* an owner's request is gone when it stops asking *)
  END_IF;
  bOwnSeen := FALSE;
  bRunIn := bRun OR bOwnRun;
  bHandCarrier := TRUE;

  (* commands: once per write *)
  bStartReq := (bStart AND NOT bStartPrev) OR (refCmd.bCmdStart AND NOT bStartSeen);
  bStartPrev := bStart;
  bStartSeen := refCmd.bCmdStart;
  refCmd.bCmdStart := FALSE;
  bStopReq := (bStop AND NOT bStopPrev) OR (refCmd.bCmdStop AND NOT bStopSeen);
  bStopPrev := bStop;
  bStopSeen := refCmd.bCmdStop;
  refCmd.bCmdStop := FALSE;
  bAbortNow := bAbortWhileHeld OR refCmd.bCmdAbort;
  refCmd.bCmdAbort := FALSE;
  IF refCmd.bCmdPause AND NOT bHoldSeen THEN
    bHoldLatch := TRUE;
  END_IF;
  bHoldSeen := refCmd.bCmdPause;
  refCmd.bCmdPause := FALSE;
  bResetReq := (bResetFaults AND NOT bResetPrev) OR (refCmd.bCmdResetFaults AND NOT bResetSeen) OR SystemReset();
  bResetPrev := bResetFaults;
  bResetSeen := refCmd.bCmdResetFaults;
  refCmd.bCmdResetFaults := FALSE;
  CASE eCmdPend OF
    E_EquipCmd.Start: bStartReq := TRUE;
    E_EquipCmd.Stop: bStopReq := TRUE;
    E_EquipCmd.Reset: bResetReq := TRUE;
  ELSE
    ;
  END_CASE;
  (* the mode: the record's command or a Command (applied once) *)
  IF refCmd.nCmdDoseMode >= 0 THEN
    CASE refCmd.nCmdDoseMode OF
      0: refSet.eMode := E_Mode.Off;
      1: refSet.eMode := E_Mode.Hand;
      2: refSet.eMode := E_Mode.Auto;
    ELSE
      refSts.bSettingRefused := TRUE;    (* a dose has no other mode *)
      refSts.eSettingRefusedErrorId := E_UtError.ChoiceBad;
    END_CASE;
    refCmd.nCmdDoseMode := -1;
  END_IF;
  CASE eCmdPend OF
    E_EquipCmd.ModeOff: refSet.eMode := E_Mode.Off;
    E_EquipCmd.ModeHand: refSet.eMode := E_Mode.Hand;
    E_EquipCmd.ModeAuto: refSet.eMode := E_Mode.Auto;
  ELSE
    ;
  END_CASE;
  eCmdPend := E_EquipCmd.None;
  eModeNow := refSet.eMode;
  bStartHand := bStartReq;
  IF refSet.eMode <> E_Mode.Auto THEN
    bStartReq := FALSE;           (* a start in Hand is the hand run's, not a dose's *)
  END_IF;
  IF bStartReq THEN
    bHoldLatch := FALSE;
  END_IF;
  IF bResetReq THEN
    refSts.bMaxQuantityReached := FALSE;
    refSts.bSettingRefused := FALSE;
    refSts.eSettingRefusedErrorId := E_UtError.None;
  END_IF;
  bRunEdge := bRunIn AND NOT bRunPrev AND refSet.eMode = E_Mode.Auto;
  bRunPrev := bRunIn;

  (* the end of a dose, and the Flow / Timed run request (a held bRun must drop after a stop) *)
  bEndReq := bStopReq OR bAbortNow OR bMaxTrip OR bQtyEnd OR NOT refSet.bDosingEnabled;
  IF bStartReq AND NOT bEndReq THEN
    bStartLatch := TRUE;
  END_IF;
  IF bEndReq THEN
    bStartLatch := FALSE;
    IF bRunIn THEN
      bRunBlocked := TRUE;
    END_IF;
  END_IF;
  IF NOT bRunIn THEN
    bRunBlocked := FALSE;
  END_IF;
  bRunReq := refSet.bDosingEnabled AND NOT bEndReq AND ((bRunIn AND NOT bRunBlocked) OR bStartLatch)
             AND refSet.eMode = E_Mode.Auto;

  (* Hand: a start runs the pump at fHandSpeedPct until a stop, tMaxHandRunTime, the interlock ... *)
  bHandWas := bHandRun;
  IF refSet.eMode = E_Mode.Hand THEN
    IF bHandRun THEN
      IF bEndReq THEN
        bHandRun := FALSE;
        IF bAbortNow THEN
          eHandEnd := E_StopReason.Abort;
        ELSIF bMaxTrip THEN
          eHandEnd := E_StopReason.MaxRun;
        ELSIF bQtyEnd THEN
          eHandEnd := E_StopReason.MaxQuantity;
        ELSIF NOT refSet.bDosingEnabled THEN
          eHandEnd := E_StopReason.Off;
        ELSE
          eHandEnd := E_StopReason.Manual;
        END_IF;
      ELSIF NOT bInterlock THEN
        bHandRun := FALSE;
        eHandEnd := E_StopReason.Interlock;
      ELSIF refSet.tMaxHandRunTime > T#0s AND tNow - tHandAt >= refSet.tMaxHandRunTime THEN
        bHandRun := FALSE;
        eHandEnd := E_StopReason.MaxRun;
      END_IF;
    ELSIF bStartHand AND NOT bEndReq AND bInterlock AND refSet.bDosingEnabled THEN
      bHandRun := TRUE;
      tHandAt := tNow;
      fDlv := 0.0;
      bHoldLatch := FALSE;
    END_IF;
  ELSE
    bHandRun := FALSE;
    IF bHandWas THEN
      eHandEnd := E_StopReason.Request;
    END_IF;
  END_IF;

  (* stock low holds every variant *)
  bStockTrip := F_Protect(tNow := tNow, bConditionPresent := bStockLowSwitch, bResetRequest := bResetReq,
                          tRetryCountWindow := refSet.tRetryCountWindow, stSettings := refSet.stStockLowFault,
                          stStatus := refSts.stStockLowFault, stWorking := stWStock);
  bTripHold := bStockTrip;
  bCounting := TRUE;
  IF ipDosingPump <> NULL THEN
    bCounting := ipDosingPump.bIsRunning;
  END_IF;
  bPumpGo := FALSE;
  fPumpSpeedPct := 0.0;
  fDosed := 0.0;
  bDoneNow := FALSE;
  Begin := bResetReq;
END_METHOD

METHOD PROTECTED FINAL Finish
  VAR_INPUT
    refCmd : REFERENCE TO ST_DoseData;
    refSet : REFERENCE TO ST_DoseSet;
    refSts : REFERENCE TO ST_DoseSts;
    bOk : BOOL;                   // the variant's settings are good
    bVTrip : BOOL;                // the variant's own trip / warning, and their codes
    eVTrip : E_UtError;
    bVWarn : BOOL;
    eVWarn : E_UtError;
    eVPhase : E_DosePhase;        // the variant's phase while it doses
    tVLeft : TIME;
  END_VAR
  VAR
    bEnded : BOOL;
    nW : LINT;
    eReqErr : E_UtError;
  END_VAR
  (* a Hand run takes the place of the variant's (idle) dosing *)
  IF bHandRun THEN
    bBusy := TRUE;
    bHandShow := TRUE;
    bPaused := bPause OR bHoldLatch OR bTripHold OR (refSet.bHandNeedsCarrier AND NOT bHandCarrier);
    bPumpGo := NOT bPaused;
    fPumpSpeedPct := 0.0;
    fDosed := 0.0;
    IF bPumpGo THEN
      fPumpSpeedPct := LIMIT(0.0, refSet.fHandSpeedPct, 100.0);
      IF bCounting THEN
        fDosed := REAL_TO_LREAL(refSet.fFlowAtFullSpeed * fPumpSpeedPct / 100.0) * fStepS / 3600.0;
      END_IF;
    END_IF;
    fDlv := fDlv + fDosed;
  ELSIF bHandWas THEN
    eEnd := eHandEnd;
    refSts.fDeliveredLastDose := fDlv;
  END_IF;
  (* caps: fMaxQuantityPerDose, stMaxDoseTimeFault *)
  bQtyEnd := FALSE;
  IF bBusy AND refSet.fMaxQuantityPerDose > 0.0 AND fDlv >= refSet.fMaxQuantityPerDose THEN
    refSts.bMaxQuantityReached := TRUE;
    bQtyEnd := TRUE;              (* the dose ends next scan *)
  END_IF;
  IF bBusy AND NOT bBusyPrev THEN
    tDoseStart := tNow;
  END_IF;
  IF bBusy OR bBusyPrev THEN
    refCmd.det.tThisDoseTime := tNow - tDoseStart;
  END_IF;
  bMaxTrip := F_Protect(tNow := tNow, bConditionPresent := bBusy, bResetRequest := bResetReq, tRetryCountWindow := refSet.tRetryCountWindow,
                        stSettings := refSet.stMaxDoseTimeFault, stStatus := refSts.stMaxDoseTimeFault, stWorking := stWMax);
  bEnded := (NOT bBusy AND bBusyPrev) OR bDoneNow;
  IF bEnded THEN
    refSts.eStopReason := eEnd;
  END_IF;
  IF NOT bBusy THEN
    bPumpGo := FALSE;
    fPumpSpeedPct := 0.0;
  END_IF;
  bBusyPrev := bBusy;

  (* the pump *)
  bPumpRunCommand := bPumpGo AND bInterlock;
  IF ipDosingPump <> NULL THEN
    eReqErr := ipDosingPump.Request(bRun := bPumpRunCommand, bHoldOff := NOT bInterlock, fSpeedSetpointPct := fPumpSpeedPct);
  END_IF;

  (* totals: millionths in a LINT; kept at each dose end and every hour *)
  IF fDosed > 0.0 AND fDosed <= 1.0E15 THEN
    fTotFrac := fTotFrac + fDosed * 1000000.0;
    nW := LREAL_TO_LINT(fTotFrac);
    IF LINT_TO_LREAL(nW) > fTotFrac THEN
      nW := nW - 1;
    END_IF;
    refCmd.tot.nDosedMillionths := refCmd.tot.nDosedMillionths + nW;
    fTotFrac := fTotFrac - LINT_TO_LREAL(nW);
  END_IF;
  IF bDoneNow THEN
    refCmd.tot.nDoseCount := refCmd.tot.nDoseCount + 1;
  END_IF;
  IF bEnded OR tNow - tTotKeptAt >= T#1h THEN
    stKeptTot := refCmd.tot;
    tTotKeptAt := tNow;
  END_IF;

  (* status *)
  bDone := bDoneNow;
  IF NOT bBusy THEN
    IF refSts.eStopReason = E_StopReason.Done THEN
      refSts.eDosePhase := E_DosePhase.Done;
    ELSIF refSts.eStopReason <> E_StopReason.None AND refSts.eStopReason <> E_StopReason.Request THEN
      refSts.eDosePhase := E_DosePhase.Aborted;
    ELSE
      refSts.eDosePhase := E_DosePhase.Idle;
    END_IF;
  ELSIF bPaused THEN
    refSts.eDosePhase := E_DosePhase.Held;
  ELSIF bHandRun THEN
    refSts.eDosePhase := E_DosePhase.Dosing;
  ELSE
    refSts.eDosePhase := eVPhase;
  END_IF;
  refSts.bPaused := bBusy AND bPaused;
  refSts.eModeInUse := refSet.eMode;
  refSts.bHandRunActive := bHandRun;
  eStopShown := refSts.eStopReason;
  refSts.fPumpSpeedPct := fPumpSpeedPct;
  refSts.fDeliveredThisDose := fDlv;
  IF tVLeft > T#0s THEN
    refCmd.det.tTimeLeft := tVLeft;
  ELSE
    refCmd.det.tTimeLeft := T#0s;
  END_IF;

  bError := NOT bOk OR bStockTrip OR bMaxTrip OR bVTrip;
  bWarning := NOT bError AND (refSts.bMaxQuantityReached OR stWStock.bWarning OR stWMax.bWarning OR bVWarn
                              OR stWStock.bSettingBad OR stWMax.bSettingBad OR refSts.bSettingRefused);
  IF NOT bOk THEN
    eErrorId := E_UtError.BadSetting;
  ELSIF bStockTrip THEN
    eErrorId := E_UtError.StockLow;
  ELSIF bMaxTrip THEN
    eErrorId := E_UtError.MaxRun;
  ELSIF bVTrip THEN
    eErrorId := eVTrip;
  ELSIF refSts.bMaxQuantityReached THEN
    eErrorId := E_UtError.MaxQuantity;
  ELSIF stWStock.bWarning THEN
    eErrorId := E_UtError.StockLow;
  ELSIF stWMax.bWarning THEN
    eErrorId := E_UtError.MaxRun;
  ELSIF bVWarn THEN
    eErrorId := eVWarn;
  ELSIF stWStock.bSettingBad OR stWMax.bSettingBad THEN
    eErrorId := E_UtError.BadSetting;
  ELSIF refSts.bSettingRefused THEN
    eErrorId := E_UtError.SettingRefused;
  ELSE
    eErrorId := E_UtError.None;
  END_IF;
  IF bError THEN
    eState := E_State.Fault;
  ELSIF NOT refSet.bDosingEnabled OR refSet.eMode = E_Mode.Off THEN
    eState := E_State.Off;
  ELSIF bBusy AND bPaused THEN
    eState := E_State.Held;
  ELSIF bBusy THEN
    eState := E_State.Running;
  ELSE
    eState := E_State.Idle;
  END_IF;
  bFirstScan := FALSE;
END_METHOD

END_FUNCTION_BLOCK