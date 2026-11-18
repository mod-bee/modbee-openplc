(* FB_Equipment — the engine every equipment block shares (motor, pump, valve): written once.

Modes (the record's set.eMode, kept over a power cut; ePowerUp Off forces Off at power-up; the record's command
nCmdMode 0 Off / 1 Hand / 2 Auto / 3 OutOfService writes it once (SMS, SCADA), a Command(ModeOff ...) the same):
Off   nothing runs; switching to Off resets trips whose cause has gone (set.bResetByOff).
Hand  bCmdStart / bCmdStop (the panel, or FB_LocalControl): a start while not permitted is dropped; a start
waits out the restart delay; Hand never resumes after a power cut. No owner reaches it. set.tHandMax
(0 = none) ends a Hand run after that long (stop reason MaxRun). Jog (Command(Jog) every scan, from
FB_MotorJog; Hand only, not while a Hand run is latched): runs while held, past trips, delays and the
permissive; only Off and bInterlock stop it.
Auto  follows its owner's Request (called every scan); an owner that stops calling = owner lost, stop.
A start waits for: permissive, the restart delay, the system's power-up hold, no part holding it.
bCmdStop stops it until the owner's request drops.
OutOfService (where the child allows it: motors, valves; not pumps): nothing runs, and no protection trips or
warns (taken out for maintenance); it is not ready, not available.
bInterlock FALSE stops it in every mode (not a fault). bPermissive FALSE blocks a start, never stops it.
Trips (the block's own protections and its parts') stop it in every mode; the first one is eErrorId. After a
reset clears a trip it runs again at once while its owner still asks (set.bRestartAfterReset FALSE: the owner's
request must drop and come back first: for machines that must not restart unexpectedly). set.bWarnNotAuto: a
warning (NotAuto) while it is not in Auto and the plant is (ipSystem; unwired: always expected in Auto).
tActIdleTime: the time since it last stopped (0 while running; power-on time only, from power-up);
tActHandLeft: a Hand run's time left under set.tHandMax (0 = none counting). A child shows both in its det.

A child calls, every scan:  bReset := Begin(refData, refData.set, refData.sts);
(its own protections, with bReset)
Finish(refData, refData.set, refData.sts, its trip / warning / error, its
restart delay);
and implements Drive (sets its outputs) and FeedbackOk (it is really running). *)

FUNCTION_BLOCK ABSTRACT FB_Equipment EXTENDS FB_Object IMPLEMENTS I_Equipment
  VAR_INPUT
    bInterlock : BOOL := TRUE; (* FALSE stops it in every mode *)
    bPermissive : BOOL := TRUE; (* FALSE blocks a start *)
  END_VAR
  VAR
    bReq : BOOL; (* the owner's request *)
    bHoldReq : BOOL;
    fSpeedReq : REAL := -1.0;
    bUrgentReq : BOOL; (* the owner's overflow call *)
    bReqSeen : BOOL; (* Request was called since the last scan *)
    bLinked : BOOL;
    bStopLatch : BOOL; (* bCmdStop in Auto: off until the owner's request drops *)
    bHandStartReq : BOOL;
    bHandRun : BOOL;
    bRunCmd : BOOL;
    bRunCmdPrev : BOOL;
    tStoppedAt : TIME;
    eModePrev : E_Mode;
    bTripNow : BOOL;
    bWarnNow : BOOL;
    bHoldStart : BOOL;
    eFirstOut : E_UtError;
    eFirstWarn : E_UtError;
    eStop : E_StopReason;
    bCmdStartIn : BOOL; (* commands through Command (FB_LocalControl ...) *)
    bCmdStopIn : BOOL;
    bCmdResetIn : BOOL;
    eModeIn : E_EquipCmd;
    bJogIn : BOOL; (* Command(Jog) since the last cycle *)
    bJogRevIn : BOOL; (* Command(JogRev) since the last cycle (a reversing variant reads it) *)
    bJogging : BOOL;
    tHandSince : TIME; (* the Hand run started *)
    bTripWas : BOOL; (* a trip stood last cycle *)
    bMustCycle : BOOL; (* a reset cleared a trip: the request must drop first *)
    bResetThisScan : BOOL; (* a reset this scan (Begin's result), for a variant's own record *)
    tIdleNow : TIME; (* since the last stop (0 while running) *)
    tHandLeftNow : TIME; (* a Hand run's time left under set.tHandMax (0 = none counting) *)
  END_VAR


(* ---- what the child implements ---- *)
METHOD PROTECTED ABSTRACT Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
END_METHOD

METHOD PROTECTED ABSTRACT FeedbackOk : BOOL
END_METHOD

(* ---- hooks a child may override ---- *)
(* the Auto run decision after the owner's request: delays, minimum run (default: as asked) *)
METHOD PROTECTED ShapeRun : BOOL
  VAR_INPUT
    bWant : BOOL;                 // the owner wants it running now
  END_VAR
  ShapeRun := bWant;
END_METHOD

(* the start mask is on: parts set to mask at start ignore their cause (default: never) *)
METHOD PROTECTED PartMasked : BOOL
  PartMasked := FALSE;
END_METHOD

(* something else makes it unavailable to its owner (default: nothing) *)
METHOD PROTECTED Unavailable : BOOL
  Unavailable := FALSE;
END_METHOD

(* ---- I_Equipment ---- *)
METHOD PUBLIC FINAL Request : E_UtError
  VAR_INPUT
    bRun : BOOL;
    bHold : BOOL;
    fSpeed : REAL := -1.0;
    bUrgent : BOOL;
  END_VAR
  bReq := bRun;
  bHoldReq := bHold;
  fSpeedReq := fSpeed;
  bUrgentReq := bUrgent;
  bReqSeen := TRUE;
  Request := eFirstOut;
END_METHOD

METHOD PUBLIC FINAL Command
  VAR_INPUT
    eCmd : E_EquipCmd;
  END_VAR
  CASE eCmd OF
    E_EquipCmd.Start: bCmdStartIn := TRUE;
    E_EquipCmd.Stop: bCmdStopIn := TRUE;
    E_EquipCmd.Reset: bCmdResetIn := TRUE;
    E_EquipCmd.ModeOff, E_EquipCmd.ModeHand, E_EquipCmd.ModeAuto: eModeIn := eCmd;
    E_EquipCmd.Jog: bJogIn := TRUE;
    E_EquipCmd.JogRev: bJogIn := TRUE; bJogRevIn := TRUE;
  ELSE
    ;
  END_CASE;
END_METHOD

PROPERTY PUBLIC eActMode : E_Mode
  GET
    eActMode := eModePrev;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsRunning : BOOL
  GET
    bIsRunning := bRunCmd AND FeedbackOk();
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsReady : BOOL
  GET
    bIsReady := eModePrev <> E_Mode.Off AND eModePrev <> E_Mode.OutOfService AND bInterlock AND bPermissive AND NOT bTripNow
                AND NOT Unavailable();   (* e.g. an actuator in Local, a pump's motor in Hand *)
  END_GET
END_PROPERTY

PROPERTY PUBLIC tActIdleTime : TIME
  GET
    tActIdleTime := tIdleNow;
  END_GET
END_PROPERTY

PROPERTY PUBLIC tActHandLeft : TIME
  GET
    tActHandLeft := tHandLeftNow;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsAvailable : BOOL
  GET
    bIsAvailable := eModePrev = E_Mode.Auto AND bInterlock AND NOT bTripNow AND NOT Unavailable();
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsAuto : BOOL
  GET
    bIsAuto := eModePrev = E_Mode.Auto;
  END_GET
END_PROPERTY

PROPERTY PUBLIC bIsFaulted : BOOL
  GET
    bIsFaulted := bTripNow;
  END_GET
END_PROPERTY

PROPERTY PUBLIC eActError : E_UtError
  GET
    eActError := eErrorId;
  END_GET
END_PROPERTY

PROPERTY PUBLIC eActStopReason : E_StopReason
  GET
    eActStopReason := eStop;
  END_GET
END_PROPERTY

PROPERTY PUBLIC fActRunHours : REAL
  GET
    fActRunHours := RunHours();
  END_GET
END_PROPERTY

(* the child allows OutOfService (TRUE here) *)
METHOD PROTECTED AllowOos : BOOL
  AllowOos := TRUE;
END_METHOD

(* not in Auto, for the NotAuto warning (here: its own mode; a pump adds its motor's) *)
METHOD PROTECTED NotAuto : BOOL
  VAR_INPUT
    eMode : E_Mode;
  END_VAR
  NotAuto := eMode <> E_Mode.Auto;
END_METHOD

(* the run hours a child counts (0 here) *)
METHOD PROTECTED RunHours : REAL
  RunHours := 0.0;
END_METHOD

(* ---- the engine, phase 1: time, power-up, mode, commands. Returns the reset request. ---- *)
METHOD PROTECTED FINAL Begin : BOOL
  VAR_INPUT
    refCmd : REFERENCE TO ST_EquipmentData;
    refSet : REFERENCE TO ST_EquipmentSet;
    refSts : REFERENCE TO ST_EquipmentSts;
  END_VAR
  VAR
    bReset : BOOL;
  END_VAR
  tNow := TIME();
  bReset := FALSE;
  IF bFirstScan THEN
    IF refSet.ePowerUp = E_PowerUp.Off THEN
      refSet.eMode := E_Mode.Off;
    END_IF;
    eModePrev := refSet.eMode;
    tStoppedAt := tNow;           // after a power cut, an automatic start waits out the restart delay
    bHandRun := FALSE;
  END_IF;
  (* the record's mode command: once, then -1 *)
  IF refCmd.nCmdMode >= 0 THEN
    CASE refCmd.nCmdMode OF
      0: refSet.eMode := E_Mode.Off;
      1: refSet.eMode := E_Mode.Hand;
      2: refSet.eMode := E_Mode.Auto;
      3: refSet.eMode := E_Mode.OutOfService;   // refused below where the block does not allow it
    ELSE
      refSts.bRefused := TRUE;
      refSts.eRefusedWhy := E_UtError.ChoiceBad;
    END_CASE;
    refCmd.nCmdMode := -1;
  END_IF;
  (* commands through Command: as the record's own *)
  CASE eModeIn OF
    E_EquipCmd.ModeOff: refSet.eMode := E_Mode.Off;
    E_EquipCmd.ModeHand: refSet.eMode := E_Mode.Hand;
    E_EquipCmd.ModeAuto: refSet.eMode := E_Mode.Auto;
  ELSE
    ;
  END_CASE;
  eModeIn := E_EquipCmd.None;
  IF bCmdStartIn THEN refCmd.bCmdStart := TRUE; bCmdStartIn := FALSE; END_IF;
  IF bCmdStopIn THEN refCmd.bCmdStop := TRUE; bCmdStopIn := FALSE; END_IF;
  IF bCmdResetIn THEN refCmd.bCmdReset := TRUE; bCmdResetIn := FALSE; END_IF;
  (* a mode outside the list is put back (a bad write) *)
  CASE refSet.eMode OF
    E_Mode.Off, E_Mode.Hand, E_Mode.Auto:
      ;
    E_Mode.OutOfService:
      IF NOT AllowOos() THEN
        refSet.eMode := eModePrev;
        refSts.bRefused := TRUE;
        refSts.eRefusedWhy := E_UtError.ChoiceBad;
      END_IF;
  ELSE
    refSet.eMode := eModePrev;
    refSts.bRefused := TRUE;
    refSts.eRefusedWhy := E_UtError.ChoiceBad;
  END_CASE;
  IF refSet.eMode <> eModePrev THEN
    bHandRun := FALSE;
    bHandStartReq := FALSE;
    bStopLatch := FALSE;
    IF refSet.eMode = E_Mode.Off AND refSet.bResetByOff THEN
      bReset := TRUE;
    END_IF;
    eModePrev := refSet.eMode;
  END_IF;
  IF refCmd.bCmdReset THEN
    bReset := TRUE;
    refCmd.bCmdReset := FALSE;
    refSts.bRefused := FALSE;
    refSts.eRefusedWhy := E_UtError.None;
  END_IF;
  IF SystemReset() THEN
    bReset := TRUE;
  END_IF;
  IF refCmd.bCmdStart THEN
    IF refSet.eMode = E_Mode.Hand THEN
      bHandStartReq := TRUE;
    END_IF;
    refCmd.bCmdStart := FALSE;
  END_IF;
  IF refCmd.bCmdStop THEN
    bHandRun := FALSE;
    bHandStartReq := FALSE;
    IF refSet.eMode = E_Mode.Auto THEN
      bStopLatch := TRUE;
    END_IF;
    refCmd.bCmdStop := FALSE;
  END_IF;
  bResetThisScan := bReset;
  Begin := bReset;
END_METHOD

(* ---- the engine, phase 2: parts, the run decision, outputs, status. ---- *)
METHOD PROTECTED FINAL Finish
  VAR_INPUT
    refCmd : REFERENCE TO ST_EquipmentData;
    refSet : REFERENCE TO ST_EquipmentSet;
    refSts : REFERENCE TO ST_EquipmentSts;
    bOwnTrip : BOOL;              // the child's own protections
    bOwnWarn : BOOL;
    eOwnError : E_UtError;        // the child's first active protection
    bReset : BOOL;                // what Begin returned
    tRestartDelay : TIME;         // after a stop, before a start (the child's own setting)
  END_VAR
  VAR
    bWant : BOOL;
    bDelayDone : BOOL;
    bJogNow : BOOL;
  END_VAR
  bJogNow := bJogIn;              (* a jog is held only while Command(Jog) keeps coming *)
  bJogIn := FALSE;
  bJogRevIn := FALSE;
  bJogging := FALSE;
  (* parts: the owner calls them, in its own cycle *)
  (* a part's Mask (priming) masks the others from the next scan, with the child's own start mask *)
  EvaluateParts(bRunning := bRunCmd, bResetWanted := bReset, bMasked := PartMasked() OR bPartMask);
  bHoldStart := bPartHold;

  bTripNow := (bOwnTrip OR bPartTrip) AND refSet.eMode <> E_Mode.OutOfService;
  bWarnNow := (bOwnWarn OR bPartWarn) AND refSet.eMode <> E_Mode.OutOfService;
  (* a reset that cleared a trip: the run request cycles first *)
  IF bTripWas AND NOT bTripNow AND bReset AND NOT refSet.bRestartAfterReset AND NOT bRunCmd THEN
    bMustCycle := TRUE;
  END_IF;
  bTripWas := bTripNow;
  IF refSet.bWarnNotAuto AND NotAuto(eMode := refSet.eMode) AND NOT bTripNow THEN
    IF ipSystem = NULL THEN
      bWarnNow := TRUE;
      IF eFirstWarn = E_UtError.None THEN eFirstWarn := E_UtError.NotAuto; END_IF;
    ELSIF ipSystem.bSystemAuto THEN
      bWarnNow := TRUE;
      IF eFirstWarn = E_UtError.None THEN eFirstWarn := E_UtError.NotAuto; END_IF;
    END_IF;
  END_IF;
  IF bTripNow THEN
    IF eFirstOut = E_UtError.None THEN
      IF bOwnTrip THEN eFirstOut := eOwnError; ELSE eFirstOut := ePartTrip; END_IF;
    END_IF;
  ELSE
    eFirstOut := E_UtError.None;
  END_IF;
  IF bWarnNow THEN
    IF eFirstWarn = E_UtError.None THEN
      IF bOwnWarn THEN eFirstWarn := eOwnError; ELSE eFirstWarn := ePartWarn; END_IF;
    END_IF;
  ELSE
    eFirstWarn := E_UtError.None;
  END_IF;

  (* the owner link: Request every scan, else the request is gone *)
  IF NOT bReqSeen THEN
    IF bLinked AND bReq AND refSet.eMode = E_Mode.Auto THEN
      eStop := E_StopReason.OwnerLost;
    END_IF;
    bReq := FALSE;
    bHoldReq := FALSE;
    bUrgentReq := FALSE;
  END_IF;
  bLinked := bReqSeen;
  bReqSeen := FALSE;
  IF NOT bReq OR refSet.eMode <> E_Mode.Auto THEN
    bMustCycle := FALSE;
  END_IF;
  IF NOT bReq THEN
    bStopLatch := FALSE;
  END_IF;

  bDelayDone := tNow - tStoppedAt >= tRestartDelay;
  IF refSet.eMode = E_Mode.Off OR refSet.eMode = E_Mode.OutOfService THEN
    bRunCmd := FALSE;
    eStop := E_StopReason.Off;
  ELSIF NOT bInterlock THEN
    bRunCmd := FALSE;
    bHandRun := FALSE;
    bHandStartReq := FALSE;
    eStop := E_StopReason.Interlock;
  ELSIF refSet.eMode = E_Mode.Hand AND bJogNow AND NOT bHandRun THEN
    bRunCmd := TRUE;              (* jog: held, past trips, delays and the permissive *)
    bJogging := TRUE;
  ELSIF bTripNow THEN
    bRunCmd := FALSE;
    bHandRun := FALSE;
    bHandStartReq := FALSE;
    eStop := E_StopReason.Fault;
  ELSIF bPartStop THEN
    bRunCmd := FALSE;
    eStop := E_StopReason.Part;
  ELSIF refSet.eMode = E_Mode.Hand THEN
    IF bHandStartReq THEN
      IF NOT bPermissive THEN
        bHandStartReq := FALSE;   // a Hand start while not permitted is dropped
      ELSIF bDelayDone OR bRunCmd THEN
        bHandRun := TRUE;
        bHandStartReq := FALSE;
        tHandSince := tNow;
      END_IF;
    END_IF;
    IF bHandRun AND refSet.tHandMax > T#0s AND tNow - tHandSince >= refSet.tHandMax THEN
      bHandRun := FALSE;          (* the Hand run limit *)
      eStop := E_StopReason.MaxRun;
    ELSIF bRunCmd AND NOT bHandRun THEN
      eStop := E_StopReason.Hand;
    END_IF;
    bRunCmd := bHandRun;
  ELSE
    bWant := ShapeRun(bWant := bReq AND NOT bHoldReq AND NOT bStopLatch AND NOT bMustCycle);
    IF NOT bWant THEN
      IF bRunCmd AND eStop <> E_StopReason.OwnerLost THEN
        eStop := E_StopReason.Request;
      END_IF;
      bRunCmd := FALSE;
    ELSIF NOT bRunCmd AND bPermissive AND bDelayDone AND (NOT bHoldStart OR bUrgentReq) AND NOT SystemHold() THEN
      (* an urgent (overflow) call is not held by a part's start hold: overflow beats anti-cycling *)
      bRunCmd := TRUE;
    END_IF;
  END_IF;
  IF bRunCmd AND NOT bRunCmdPrev THEN
    eStop := E_StopReason.None;
  END_IF;
  IF bRunCmdPrev AND NOT bRunCmd THEN
    tStoppedAt := tNow;
  END_IF;
  bRunCmdPrev := bRunCmd;
  IF bRunCmd THEN
    tIdleNow := T#0s;
  ELSE
    tIdleNow := tNow - tStoppedAt;
  END_IF;
  IF bHandRun AND refSet.tHandMax > T#0s THEN
    tHandLeftNow := MAX(T#0s, refSet.tHandMax - (tNow - tHandSince));
  ELSE
    tHandLeftNow := T#0s;
  END_IF;

  Drive(bRun := bRunCmd);

  (* status *)
  bError := bTripNow;
  bWarning := bWarnNow;
  IF bTripNow THEN
    eErrorId := eFirstOut;
  ELSE
    eErrorId := eFirstWarn;
  END_IF;
  IF refSet.eMode = E_Mode.Off OR refSet.eMode = E_Mode.OutOfService THEN
    eState := E_State.Off;
  ELSIF bTripNow THEN
    eState := E_State.Fault;
  ELSIF NOT bInterlock OR (bHoldReq AND bLinked) THEN
    eState := E_State.Held;
  ELSIF bRunCmd AND FeedbackOk() THEN
    eState := E_State.Running;
  ELSIF bRunCmd THEN
    eState := E_State.Starting;
  ELSIF FeedbackOk() THEN
    eState := E_State.Stopping;
  ELSIF (bReq AND refSet.eMode = E_Mode.Auto AND NOT bStopLatch) OR bHandStartReq THEN
    eState := E_State.Waiting;
  ELSE
    eState := E_State.Idle;
  END_IF;
  refSts.eState := eState;
  refSts.eErrorId := eErrorId;
  refSts.eStopReason := eStop;
  refSts.bRunning := bRunCmd AND FeedbackOk();
  refSts.bReady := refSet.eMode <> E_Mode.Off AND refSet.eMode <> E_Mode.OutOfService AND bInterlock AND bPermissive AND NOT bTripNow
                   AND NOT Unavailable();
  refSts.bAvailable := refSet.eMode = E_Mode.Auto AND bInterlock AND NOT bTripNow AND NOT Unavailable();
  refSts.bLinked := bLinked;
  refSts.bInterlocked := NOT bInterlock;
  refSts.bJogging := bJogging;
  refSts.bMustCycle := bMustCycle;
  bFirstScan := FALSE;
END_METHOD

END_FUNCTION_BLOCK