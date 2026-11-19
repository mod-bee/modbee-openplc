(* FB_Valve — a two-position valve, cylinder or damper.
On FB_Equipment: "running" is open. An owner (a zone, a route, a level control) drives it through
I_Equipment.Request (bRun = open); Hand opens / closes it from the record's bCmdStart / bCmdStop (or
FB_LocalControl). Off, the interlock or a trip put it in its safe position (set.eSafePosition), not merely closed.

Pins: bOpenLimitSwitch, bClosedLimitSwitch (end switches, used when set.bOpenLimitSwitchFitted / bClosedLimitSwitchFitted), refData -> bOpenOutput (the
open coil / drive), bCloseOutput (the close coil of a double-acting valve, or a normally-open valve's coil),
bIsOpen, bIsClosed, plus FB_Equipment's bInterlock, bPermissive, ipSystem and FB_Object's outputs.
Kinds (set.eValveType): SpringNc (coil = open), SpringNo (coil = closed), DoubleHeld (open and close coils held).
Open / closed: by its end switch when used, else after set.tOpenStrokeTime / tCloseStrokeTime from the command.
Protections: open / close timeout (the end switch not made in its travel time + 50 %), both end switches made,
position lost (an end switch lost at rest), slow stroke (set.tSlowStrokeAbove > 0: a stroke confirmed by its end
switch that took longer, a sign of wear; set.stSlowStrokeFault, default a warning, until a stroke within the time),
actuator in Local (bActuatorRemote FALSE: the actuator's own Local / Remote switch; every output off, not available to
its owner, the travel checks wait; set.stActuatorInLocalFault, default a warning after 2 s), no movement (set.stNoMovementFault, off
by default: commanded away and the end switch of the position it left still made). Strokes counted (tot.nStrokeCount;
the record's bCmdPresetStrokes sets it to nPresetStrokeCount); the last stroke's time per direction (sts.tLastOpenStrokeTime /
tLastCloseStrokeTime, with sts.tLastStrokeTime the latest). Simulation (the record's bSimulate, not kept, cleared by a
system reset): the end switches are ignored and the travel times decide, with a warning (Simulated).
Exercise: an FB_Exercise part on the valve (ipOwner := the valve) opens an idle valve in Auto for its run time
(a part's Request, honoured in Auto like the owner's own: interlock, trips and the permissive still apply).
Variants (EXTENDS FB_Valve): FB_ValveLatch (latching pulses), FB_ValveMotor (motorised: torque switches, Halt).
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Valve EXTENDS FB_Equipment
  VAR_INPUT
    bOpenLimitSwitch : BOOL := FALSE; (* open end switch (TRUE = made) *)
    bClosedLimitSwitch : BOOL; (* closed end switch (TRUE = made) *)
    bActuatorRemote : BOOL := TRUE; (* the actuator's Local / Remote switch: FALSE = in Local, not driven *)
    refData : REFERENCE TO ST_ValveData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bOpenOutput : BOOL; (* the open coil / drive *)
    bCloseOutput : BOOL; (* the close coil of a double-acting valve, or a normally-open valve's coil *)
    bIsOpen : BOOL; (* open: its end switch, or the travel time passed *)
    bIsClosed : BOOL; (* closed: its end switch, or the travel time passed *)
  END_VAR
  VAR RETAIN
    stKept : ST_ValveSet;
    nKeptLayout : UINT;
    stKeptTot : ST_ValveTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    bWantOpen : BOOL; (* the position commanded *)
    bWantPrev : BOOL;
    tMovedAt : TIME;
    stWTravel : ST_ProtectionWork;
    stWBoth : ST_ProtectionWork;
    stWLost : ST_ProtectionWork;
    tKeptAt : TIME;
    bReached : BOOL; (* the end switch of the commanded position has been made since the command *)
    stWSlow : ST_ProtectionWork;
    stWLocal : ST_ProtectionWork;
    stWNoMove : ST_ProtectionWork;
    bSlowCause : BOOL; (* the last confirmed stroke was slow *)
    bSeated : BOOL; (* closed on torque since the close command *)
    bRemoteWas : BOOL := TRUE;
    bSeatUse : BOOL; (* the closed position is also proven by the seat (close on torque) *)
    bSeatMade : BOOL; (* the seat is made now *)
    bHalted : BOOL; (* stopped where it is (position not known) *)
    bVarTrip : BOOL; (* the variant's own protections *)
    bVarWarn : BOOL;
    eVarError : E_UtError;
    bResetNow : BOOL; (* this scan's reset (Begin's), for a variant's own protections *)
  END_VAR
  VAR_TEMP
    bReset : BOOL;
    bTrip : BOOL;
    bWarn : BOOL;
    eOwn : E_UtError;
    bTravelBad : BOOL;
    bX : BOOL;
    bUseC : BOOL; (* the closed position has a proof (its switch, or the seat) *)
    bAtC : BOOL; (* that proof is made *)
    bUseOpen : BOOL; (* the open end switch is used (not while simulated) *)
    bUseClosed : BOOL;
  END_VAR


(* bRun: open. Stopped by Off, the interlock or a trip: the safe position. *)
METHOD PROTECTED Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
  VAR
    bSafe : BOOL;
  END_VAR
  bSafe := NOT bRun AND (eStop = E_StopReason.Off OR eStop = E_StopReason.Interlock OR eStop = E_StopReason.Fault);
  IF bSafe THEN
    bWantOpen := refData.set.eSafePosition = E_SafePos.Open;
  ELSE
    bWantOpen := bRun;
  END_IF;
  IF NOT bActuatorRemote THEN
    bOpenOutput := FALSE;            (* the actuator is in Local: not driven *)
    bCloseOutput := FALSE;
    RETURN;
  END_IF;
  CASE refData.set.eValveType OF
    E_ValveType.SpringNo:
      bOpenOutput := FALSE;
      bCloseOutput := NOT bWantOpen;
    E_ValveType.DoubleHeld:
      bOpenOutput := bWantOpen;
      bCloseOutput := NOT bWantOpen;
  ELSE
    bOpenOutput := bWantOpen;
    bCloseOutput := FALSE;
  END_CASE;
END_METHOD

(* the Auto decision: the owner's request, or a part's (FB_Exercise) *)
METHOD PROTECTED OVERRIDE ShapeRun : BOOL
  VAR_INPUT
    bWant : BOOL;
  END_VAR
  ShapeRun := bWant OR bPartRequest;
END_METHOD

(* an actuator in Local is not available to its owner *)
METHOD PROTECTED OVERRIDE Unavailable : BOOL
  Unavailable := NOT bActuatorRemote;
END_METHOD

METHOD PROTECTED FeedbackOk : BOOL
  FeedbackOk := bIsOpen;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tOpenStrokeTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tCloseStrokeTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tSlowStrokeAbove >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bOpenOutput := FALSE;
  bCloseOutput := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
  tKeptAt := TIME();
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;

bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);
bResetNow := bReset;
IF SystemReset() THEN refData.bSimulate := FALSE; END_IF;
bUseOpen := refData.set.bOpenLimitSwitchFitted AND NOT refData.bSimulate;
bUseClosed := refData.set.bClosedLimitSwitchFitted AND NOT refData.bSimulate;
IF refData.bCmdPresetStrokes THEN
  refData.tot.nStrokeCount := refData.nPresetStrokeCount;
  stKeptTot := refData.tot;
  refData.bCmdPresetStrokes := FALSE;
END_IF;

(* where it is: the end switch when used, else the travel time since the command *)
IF bWantOpen <> bWantPrev OR (bActuatorRemote AND NOT bRemoteWas) THEN
  tMovedAt := tNow;               (* a move, or the actuator back in Remote: the travel counts from now *)
  bReached := FALSE;
  bSeated := FALSE;
  IF bWantOpen THEN
    refData.tot.nStrokeCount := refData.tot.nStrokeCount + 1;
  END_IF;
END_IF;
bWantPrev := bWantOpen;
bRemoteWas := bActuatorRemote;
bUseC := bUseClosed OR bSeatUse;
IF NOT bWantOpen AND bSeatUse AND bSeatMade THEN
  bSeated := TRUE;                (* closed on torque: seated until the next command *)
END_IF;
bAtC := (bUseClosed AND bClosedLimitSwitch) OR bSeated;
IF bWantOpen THEN
  IF bUseOpen THEN
    bIsOpen := bOpenLimitSwitch;
  ELSE
    bIsOpen := tNow - tMovedAt >= refData.set.tOpenStrokeTime AND NOT bHalted AND bActuatorRemote;
  END_IF;
  bIsClosed := FALSE;
  bTravelBad := bUseOpen AND NOT bOpenLimitSwitch AND tNow - tMovedAt > refData.set.tOpenStrokeTime * 3 / 2;
ELSE
  IF bUseC THEN
    bIsClosed := bAtC;
  ELSE
    bIsClosed := tNow - tMovedAt >= refData.set.tCloseStrokeTime AND NOT bHalted AND bActuatorRemote;
  END_IF;
  bIsOpen := FALSE;
  bTravelBad := bUseC AND NOT bAtC AND tNow - tMovedAt > refData.set.tCloseStrokeTime * 3 / 2;
END_IF;

IF ((bWantOpen AND bUseOpen AND bOpenLimitSwitch) OR (NOT bWantOpen AND bAtC)) AND NOT bReached THEN
  bReached := TRUE;
  (* a stroke confirmed by its end switch: its time, slow or not *)
  refData.sts.tLastStrokeTime := tNow - tMovedAt;
  IF bWantOpen THEN
    refData.sts.tLastOpenStrokeTime := refData.sts.tLastStrokeTime;
  ELSE
    refData.sts.tLastCloseStrokeTime := refData.sts.tLastStrokeTime;
  END_IF;
  bSlowCause := refData.set.tSlowStrokeAbove > T#0s AND refData.sts.tLastStrokeTime > refData.set.tSlowStrokeAbove;
END_IF;
IF refData.set.tSlowStrokeAbove <= T#0s THEN
  bSlowCause := FALSE;
END_IF;
(* halted, or the actuator in Local: no travel checks *)
bTravelBad := bTravelBad AND NOT bReached AND NOT bHalted AND bActuatorRemote;

(* protections *)
bX := F_Protect(tNow := tNow, bConditionPresent := bTravelBad, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                stSettings := refData.set.stStrokeTimeoutFault, stStatus := refData.sts.stStrokeTimeoutFault, stWorking := stWTravel);
bX := F_Protect(tNow := tNow, bConditionPresent := bUseOpen AND bUseClosed AND bOpenLimitSwitch AND bClosedLimitSwitch,
                bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                stSettings := refData.set.stBothLimitsFault, stStatus := refData.sts.stBothLimitsFault, stWorking := stWBoth);
(* position lost: the end switch of the commanded position was made, then went *)
bX := F_Protect(tNow := tNow,
                bConditionPresent := bReached AND bActuatorRemote AND ((bWantOpen AND bUseOpen AND NOT bOpenLimitSwitch)
                                        OR (NOT bWantOpen AND bUseClosed AND NOT bClosedLimitSwitch AND NOT bSeated)),
                bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                stSettings := refData.set.stPositionLostFault, stStatus := refData.sts.stPositionLostFault, stWorking := stWLost);
bX := F_Protect(tNow := tNow, bConditionPresent := bSlowCause, bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                stSettings := refData.set.stSlowStrokeFault, stStatus := refData.sts.stSlowStrokeFault, stWorking := stWSlow);
bX := F_Protect(tNow := tNow, bConditionPresent := NOT bActuatorRemote AND refData.set.eMode <> E_Mode.OutOfService,
                bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                stSettings := refData.set.stActuatorInLocalFault, stStatus := refData.sts.stActuatorInLocalFault, stWorking := stWLocal);
(* no movement: commanded away, the switch of the position it left still made *)
bX := F_Protect(tNow := tNow,
                bConditionPresent := NOT bReached AND NOT bHalted AND bActuatorRemote
                          AND ((bWantOpen AND bUseClosed AND bClosedLimitSwitch) OR (NOT bWantOpen AND bUseOpen AND bOpenLimitSwitch)),
                bResetRequest := bReset, tRetryCountWindow := refData.set.tRetryCountWindow,
                stSettings := refData.set.stNoMovementFault, stStatus := refData.sts.stNoMovementFault, stWorking := stWNoMove);
bTrip := stWTravel.bTripping OR stWBoth.bTripping OR stWLost.bTripping OR stWSlow.bTripping OR stWLocal.bTripping OR stWNoMove.bTripping
         OR bVarTrip;
bWarn := stWTravel.bWarning OR stWBoth.bWarning OR stWLost.bWarning OR stWSlow.bWarning OR stWLocal.bWarning OR stWNoMove.bWarning
         OR bVarWarn OR refData.bSimulate;
eOwn := E_UtError.None;
IF bVarTrip THEN
  eOwn := eVarError;
ELSIF stWNoMove.bTripping OR stWNoMove.bWarning THEN
  eOwn := E_UtError.NoMovement;
ELSIF stWTravel.bTripping OR stWTravel.bWarning THEN
  eOwn := E_UtError.TravelTimeout;
ELSIF stWBoth.bTripping OR stWBoth.bWarning THEN
  eOwn := E_UtError.BothLimits;
ELSIF stWLost.bTripping OR stWLost.bWarning THEN
  eOwn := E_UtError.PositionLost;
ELSIF stWLocal.bTripping OR stWLocal.bWarning THEN
  eOwn := E_UtError.ActuatorLocal;
ELSIF stWSlow.bTripping OR stWSlow.bWarning THEN
  eOwn := E_UtError.SlowStroke;
ELSIF bVarWarn THEN
  eOwn := eVarError;
ELSIF refData.bSimulate THEN
  eOwn := E_UtError.Simulated;
END_IF;

Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset, tRestartDelay := T#0s);

refData.sts.bIsOpen := bIsOpen;
refData.sts.bIsClosed := bIsClosed;
refData.sts.bTravelling := NOT bIsOpen AND NOT bIsClosed AND NOT bHalted;
refData.sts.bActuatorInLocal := NOT bActuatorRemote;
IF tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;

END_FUNCTION_BLOCK