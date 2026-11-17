(* FB_Dose — the engine every dosing block shares (FB_DoseBatch, FB_DoseFlow, FB_DoseTimed; src-v2 UT_DOSE's common
part): written once.
bRun / bStart / bStop / bReset and the record's commands (bCmdStart, bCmdStop, bCmdHold, bCmdReset: once per
write); bInterlock FALSE stops the pump in every variant (Flow / Timed resume by themselves, a Batch is held);
bPermissive FALSE holds back a dose start; bHold and bCmdHold (until the next start) pause; bStop, bCmdStop, bAbort,
set.bEnabled FALSE end a dose (a held bRun must drop before it doses again); bStockLow -> set.stStockLow;
set.stMaxTime and set.fMaxQuantity cap a dose. ipPump (optional): Request(bRun := bPumpRun, bHold := NOT bInterlock,
fSpeed := fRate); dosing counts only while it runs.
Modes (set.eMode, kept; the record's nCmdMode 0 Off / 1 Hand / 2 Auto, once, or a Command from FB_LocalControl,
which drives a dose like a pump: IMPLEMENTS I_Equipment): Auto doses as above; Hand: a start (bStart, bCmdStart,
the panel's start button) runs the pump at set.fHandRate % until a stop, set.tHandMax (0 = no limit), the
interlock FALSE, an abort, set.bEnabled FALSE, a stop-trip or the mode left; with set.bHandNeedsCarrier the carrier
must be proven (Flow / Timed; a Batch has none), else the pump waits (Held); a Hand run counts into the totals but
is no dose (nDoses); Off: nothing doses. Hand never resumes after a power cut. An owner's Request(bRun) is a
bRun (bHold = not asked); a variant's own pins and records work in Auto only.
tot (millionths of a unit, and the doses) is kept at each dose end and every hour.
A variant calls, every scan:  bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);
                              (its settings, its dosing: bBusy, bPaused, bPumpGo, fRate, fDosed, fDlv, eEnd,
                               bDoneNow, its protections)
                              Finish(refCmd, refSet, refSts, bOk, its trip / warning and codes, its phase,
                                     its time left); *)

FUNCTION_BLOCK ABSTRACT FB_Dose EXTENDS FB_Object IMPLEMENTS I_Equipment
  VAR_INPUT
    bRun : BOOL; (* Batch: rising starts a dose; Flow / Timed: doses while TRUE *)
    bStart : BOOL; (* rising: Batch starts / resumes; Flow / Timed: a run latched until a stop *)
    bStop : BOOL; (* rising: ends the dose (a held bRun must drop first) *)
    bReset : BOOL; (* rising: resets trips whose cause has gone *)
    bInterlock : BOOL := TRUE; (* FALSE: the pump off *)
    bPermissive : BOOL := TRUE; (* FALSE: holds back a dose start *)
    bStockLow : BOOL;
    bHold : BOOL; (* pause *)
    bAbort : BOOL; (* end, refuse a start *)
    ipPump : I_Equipment; (* optional: the dosing pump *)
  END_VAR
  VAR_OUTPUT
    bPumpRun : BOOL;
    fRate : REAL; (* % *)
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
    bQtyEnd : BOOL; (* fMaxQuantity reached: end the dose next scan *)
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
    bRun : BOOL;
    bHold : BOOL;
    fSpeed : REAL := -1.0;
    bUrgent : BOOL;
  END_VAR
  bOwnRun := bRun AND NOT bHold;
  bOwnSeen := TRUE;
  Request := eErrorId;
END_METHOD

METHOD PUBLIC Command
  VAR_INPUT
    eCmd : E_EquipCmd;
  END_VAR
  eCmdPend := eCmd;
END_METHOD

PROPERTY PUBLIC eActMode : E_Mode
  GET
    eActMode := eModeNow;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsRunning : BOOL
  GET
    bIsRunning := bBusy AND bPumpGo;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsReady : BOOL
  GET
    bIsReady := NOT bError AND eModeNow <> E_Mode.Off;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsAvailable : BOOL
  GET
    bIsAvailable := NOT bError AND eModeNow = E_Mode.Auto;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsAuto : BOOL
  GET
    bIsAuto := eModeNow = E_Mode.Auto;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bIsFaulted : BOOL
  GET
    bIsFaulted := bError;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eActError : E_UtError
  GET
    eActError := eErrorId;
  END_GET
END_PROPERTY
PROPERTY PUBLIC eActStopReason : E_StopReason
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
METHOD PROTECTED FINAL BaseSetOk : BOOL
  VAR_INPUT
    refSet : REFERENCE TO ST_DoseSet;
  END_VAR
  BaseSetOk := refSet.fPumpCapacity >= 0.0 AND refSet.fPumpCapacity <= REAL#3.4E38
               AND refSet.fMaxQuantity >= 0.0 AND refSet.fMaxQuantity <= 1.0E15 AND refSet.tRetryWindow >= T#0s
               AND (refSet.eMode = E_Mode.Off OR refSet.eMode = E_Mode.Hand OR refSet.eMode = E_Mode.Auto)
               AND refSet.fHandRate >= 0.0 AND refSet.fHandRate <= 100.0 AND refSet.tHandMax >= T#0s;
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
  ELSIF bAbort THEN
    EndWhy := E_StopReason.Abort;
  ELSIF NOT refSet.bEnabled THEN
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
  IF refCmd.bCmdHold AND NOT bHoldSeen THEN
    bHoldLatch := TRUE;
  END_IF;
  bHoldSeen := refCmd.bCmdHold;
  refCmd.bCmdHold := FALSE;
  bResetReq := (bReset AND NOT bResetPrev) OR (refCmd.bCmdReset AND NOT bResetSeen) OR SystemReset();
  bResetPrev := bReset;
  bResetSeen := refCmd.bCmdReset;
  refCmd.bCmdReset := FALSE;
  CASE eCmdPend OF
    E_EquipCmd.Start: bStartReq := TRUE;
    E_EquipCmd.Stop: bStopReq := TRUE;
    E_EquipCmd.Reset: bResetReq := TRUE;
  ELSE
    ;
  END_CASE;
  (* the mode: the record's command or a Command (applied once) *)
  IF refCmd.nCmdMode >= 0 THEN
    CASE refCmd.nCmdMode OF
      0: refSet.eMode := E_Mode.Off;
      1: refSet.eMode := E_Mode.Hand;
      2: refSet.eMode := E_Mode.Auto;
    ELSE
      refSts.bRefused := TRUE;    (* a dose has no other mode *)
    END_CASE;
    refCmd.nCmdMode := -1;
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
    refSts.bQuantityHit := FALSE;
    refSts.bRefused := FALSE;
  END_IF;
  bRunEdge := bRunIn AND NOT bRunPrev AND refSet.eMode = E_Mode.Auto;
  bRunPrev := bRunIn;

  (* the end of a dose, and the Flow / Timed run request (a held bRun must drop after a stop) *)
  bEndReq := bStopReq OR bAbort OR bMaxTrip OR bQtyEnd OR NOT refSet.bEnabled;
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
  bRunReq := refSet.bEnabled AND NOT bEndReq AND ((bRunIn AND NOT bRunBlocked) OR bStartLatch)
             AND refSet.eMode = E_Mode.Auto;

  (* Hand: a start runs the pump at fHandRate until a stop, tHandMax, the interlock ... *)
  bHandWas := bHandRun;
  IF refSet.eMode = E_Mode.Hand THEN
    IF bHandRun THEN
      IF bEndReq THEN
        bHandRun := FALSE;
        IF bAbort THEN
          eHandEnd := E_StopReason.Abort;
        ELSIF bMaxTrip THEN
          eHandEnd := E_StopReason.MaxRun;
        ELSIF bQtyEnd THEN
          eHandEnd := E_StopReason.MaxQuantity;
        ELSIF NOT refSet.bEnabled THEN
          eHandEnd := E_StopReason.Off;
        ELSE
          eHandEnd := E_StopReason.Manual;
        END_IF;
      ELSIF NOT bInterlock THEN
        bHandRun := FALSE;
        eHandEnd := E_StopReason.Interlock;
      ELSIF refSet.tHandMax > T#0s AND tNow - tHandAt >= refSet.tHandMax THEN
        bHandRun := FALSE;
        eHandEnd := E_StopReason.MaxRun;
      END_IF;
    ELSIF bStartHand AND NOT bEndReq AND bInterlock AND refSet.bEnabled THEN
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
  bStockTrip := F_Protect(tNow := tNow, bCause := bStockLow, bResetReq := bResetReq,
                          tRetryWindow := refSet.tRetryWindow, stSet := refSet.stStockLow,
                          stSts := refSts.stStockLow, stWork := stWStock);
  bTripHold := bStockTrip;
  bCounting := TRUE;
  IF ipPump <> NULL THEN
    bCounting := ipPump.bIsRunning;
  END_IF;
  bPumpGo := FALSE;
  fRate := 0.0;
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
    bPaused := bHold OR bHoldLatch OR bTripHold OR (refSet.bHandNeedsCarrier AND NOT bHandCarrier);
    bPumpGo := NOT bPaused;
    fRate := 0.0;
    fDosed := 0.0;
    IF bPumpGo THEN
      fRate := LIMIT(0.0, refSet.fHandRate, 100.0);
      IF bCounting THEN
        fDosed := REAL_TO_LREAL(refSet.fPumpCapacity * fRate / 100.0) * fStepS / 3600.0;
      END_IF;
    END_IF;
    fDlv := fDlv + fDosed;
  ELSIF bHandWas THEN
    eEnd := eHandEnd;
    refSts.fLastDelivered := fDlv;
  END_IF;
  (* caps: fMaxQuantity, stMaxTime *)
  bQtyEnd := FALSE;
  IF bBusy AND refSet.fMaxQuantity > 0.0 AND fDlv >= refSet.fMaxQuantity THEN
    refSts.bQuantityHit := TRUE;
    bQtyEnd := TRUE;              (* the dose ends next scan *)
  END_IF;
  IF bBusy AND NOT bBusyPrev THEN
    tDoseStart := tNow;
  END_IF;
  IF bBusy OR bBusyPrev THEN
    refCmd.det.tDoseTime := tNow - tDoseStart;
  END_IF;
  bMaxTrip := F_Protect(tNow := tNow, bCause := bBusy, bResetReq := bResetReq, tRetryWindow := refSet.tRetryWindow,
                        stSet := refSet.stMaxTime, stSts := refSts.stMaxTime, stWork := stWMax);
  bEnded := (NOT bBusy AND bBusyPrev) OR bDoneNow;
  IF bEnded THEN
    refSts.eStopReason := eEnd;
  END_IF;
  IF NOT bBusy THEN
    bPumpGo := FALSE;
    fRate := 0.0;
  END_IF;
  bBusyPrev := bBusy;

  (* the pump *)
  bPumpRun := bPumpGo AND bInterlock;
  IF ipPump <> NULL THEN
    eReqErr := ipPump.Request(bRun := bPumpRun, bHold := NOT bInterlock, fSpeed := fRate);
  END_IF;

  (* totals: millionths in a LINT; kept at each dose end and every hour *)
  IF fDosed > 0.0 AND fDosed <= 1.0E15 THEN
    fTotFrac := fTotFrac + fDosed * 1000000.0;
    nW := LREAL_TO_LINT(fTotFrac);
    IF LINT_TO_LREAL(nW) > fTotFrac THEN
      nW := nW - 1;
    END_IF;
    refCmd.tot.nDosed := refCmd.tot.nDosed + nW;
    fTotFrac := fTotFrac - LINT_TO_LREAL(nW);
  END_IF;
  IF bDoneNow THEN
    refCmd.tot.nDoses := refCmd.tot.nDoses + 1;
  END_IF;
  IF bEnded OR tNow - tTotKeptAt >= T#1h THEN
    stKeptTot := refCmd.tot;
    tTotKeptAt := tNow;
  END_IF;

  (* status *)
  bDone := bDoneNow;
  IF NOT bBusy THEN
    IF refSts.eStopReason = E_StopReason.Done THEN
      refSts.ePhase := E_DosePhase.Done;
    ELSIF refSts.eStopReason <> E_StopReason.None AND refSts.eStopReason <> E_StopReason.Request THEN
      refSts.ePhase := E_DosePhase.Aborted;
    ELSE
      refSts.ePhase := E_DosePhase.Idle;
    END_IF;
  ELSIF bPaused THEN
    refSts.ePhase := E_DosePhase.Held;
  ELSIF bHandRun THEN
    refSts.ePhase := E_DosePhase.Dosing;
  ELSE
    refSts.ePhase := eVPhase;
  END_IF;
  refSts.bHeld := bBusy AND bPaused;
  refSts.eMode := refSet.eMode;
  refSts.bHandRun := bHandRun;
  eStopShown := refSts.eStopReason;
  refSts.fRate := fRate;
  refSts.fDelivered := fDlv;
  IF tVLeft > T#0s THEN
    refCmd.det.tTimeLeft := tVLeft;
  ELSE
    refCmd.det.tTimeLeft := T#0s;
  END_IF;

  bError := NOT bOk OR bStockTrip OR bMaxTrip OR bVTrip;
  bWarning := NOT bError AND (refSts.bQuantityHit OR stWStock.bWarn OR stWMax.bWarn OR bVWarn
                              OR stWStock.bBadSetting OR stWMax.bBadSetting OR refSts.bRefused);
  IF NOT bOk THEN
    eErrorId := E_UtError.BadSetting;
  ELSIF bStockTrip THEN
    eErrorId := E_UtError.StockLow;
  ELSIF bMaxTrip THEN
    eErrorId := E_UtError.MaxRun;
  ELSIF bVTrip THEN
    eErrorId := eVTrip;
  ELSIF refSts.bQuantityHit THEN
    eErrorId := E_UtError.MaxQuantity;
  ELSIF stWStock.bWarn THEN
    eErrorId := E_UtError.StockLow;
  ELSIF stWMax.bWarn THEN
    eErrorId := E_UtError.MaxRun;
  ELSIF bVWarn THEN
    eErrorId := eVWarn;
  ELSIF stWStock.bBadSetting OR stWMax.bBadSetting THEN
    eErrorId := E_UtError.BadSetting;
  ELSIF refSts.bRefused THEN
    eErrorId := E_UtError.SettingRefused;
  ELSE
    eErrorId := E_UtError.None;
  END_IF;
  IF bError THEN
    eState := E_State.Fault;
  ELSIF NOT refSet.bEnabled OR refSet.eMode = E_Mode.Off THEN
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