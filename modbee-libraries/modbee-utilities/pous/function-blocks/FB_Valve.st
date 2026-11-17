(* FB_Valve — a two-position valve, cylinder or damper (DESIGN-0.2.md section 5.6; the core of src-v2 UT_VALVE).
On FB_Equipment: "running" is open. An owner (a zone, a route, a level control) drives it through
I_Equipment.Request (bRun = open); Hand opens / closes it from the record's bCmdStart / bCmdStop (or
FB_LocalControl). Off, the interlock or a trip put it in its safe position (set.eSafe), not merely closed.

Pins: bOpenLs, bClosedLs (end switches, used when set.bUseOpenLs / bUseClosedLs), refData -> bOpenOut (the
open coil / drive), bCloseOut (the close coil of a double-acting valve, or a normally-open valve's coil),
bIsOpen, bIsClosed, plus FB_Equipment's bInterlock, bPermissive, ipSystem and FB_Object's outputs.
Kinds (set.eType): SpringNc (coil = open), SpringNo (coil = closed), DoubleHeld (open and close coils held).
Open / closed: by its end switch when used, else after set.tOpenTime / tCloseTime from the command.
Protections: open / close timeout (the end switch not made in its travel time + 50 %), both end switches made,
position lost (an end switch lost at rest), slow stroke (set.tStrokeWarn > 0: a stroke confirmed by its end
switch that took longer, a sign of wear; set.stSlowStroke, default a warning, until a stroke within the time),
actuator in Local (bActRemote FALSE: the actuator's own Local / Remote switch; every output off, not available to
its owner, the travel checks wait; set.stActLocal, default a warning after 2 s). Strokes counted (tot.nStrokes).
Exercise: an FB_Exercise part on the valve (ipOwner := the valve) opens an idle valve in Auto for its run time
(a part's Request, honoured in Auto like the owner's own: interlock, trips and the permissive still apply).
Variants (EXTENDS FB_Valve): FB_ValveLatch (latching pulses), FB_ValveMotor (motorised: torque switches, Halt).
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Valve EXTENDS FB_Equipment
  VAR_INPUT
    bOpenLs : BOOL := FALSE;
    bClosedLs : BOOL;
    refData : REFERENCE TO ST_ValveData;
    bActRemote : BOOL := TRUE; (* the actuator's Local / Remote switch: FALSE = in Local, not driven *)
  END_VAR
  VAR_OUTPUT
    bOpenOut : BOOL;
    bCloseOut : BOOL;
    bIsOpen : BOOL;
    bIsClosed : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_ValveSet;
    nKeptLayout : UINT;
    stKeptTot : ST_ValveTot;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
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
    bWantOpen := refData.set.eSafe = E_SafePos.Open;
  ELSE
    bWantOpen := bRun;
  END_IF;
  IF NOT bActRemote THEN
    bOpenOut := FALSE;            (* the actuator is in Local: not driven *)
    bCloseOut := FALSE;
    RETURN;
  END_IF;
  CASE refData.set.eType OF
    E_ValveType.SpringNo:
      bOpenOut := FALSE;
      bCloseOut := NOT bWantOpen;
    E_ValveType.DoubleHeld:
      bOpenOut := bWantOpen;
      bCloseOut := NOT bWantOpen;
  ELSE
    bOpenOut := bWantOpen;
    bCloseOut := FALSE;
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
  Unavailable := NOT bActRemote;
END_METHOD

METHOD PROTECTED FeedbackOk : BOOL
  FeedbackOk := bIsOpen;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := refData.set.tOpenTime >= T#0s AND refData.set.tCloseTime >= T#0s AND refData.set.tRetryWindow >= T#0s
           AND refData.set.tStrokeWarn >= T#0s;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bOpenOut := FALSE;
  bCloseOut := FALSE;
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
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;

bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);
bResetNow := bReset;

(* where it is: the end switch when used, else the travel time since the command *)
IF bWantOpen <> bWantPrev OR (bActRemote AND NOT bRemoteWas) THEN
  tMovedAt := tNow;               (* a move, or the actuator back in Remote: the travel counts from now *)
  bReached := FALSE;
  bSeated := FALSE;
  IF bWantOpen THEN
    refData.tot.nStrokes := refData.tot.nStrokes + 1;
  END_IF;
END_IF;
bWantPrev := bWantOpen;
bRemoteWas := bActRemote;
bUseC := refData.set.bUseClosedLs OR bSeatUse;
IF NOT bWantOpen AND bSeatUse AND bSeatMade THEN
  bSeated := TRUE;                (* closed on torque: seated until the next command *)
END_IF;
bAtC := (refData.set.bUseClosedLs AND bClosedLs) OR bSeated;
IF bWantOpen THEN
  IF refData.set.bUseOpenLs THEN
    bIsOpen := bOpenLs;
  ELSE
    bIsOpen := tNow - tMovedAt >= refData.set.tOpenTime AND NOT bHalted AND bActRemote;
  END_IF;
  bIsClosed := FALSE;
  bTravelBad := refData.set.bUseOpenLs AND NOT bOpenLs AND tNow - tMovedAt > refData.set.tOpenTime * 3 / 2;
ELSE
  IF bUseC THEN
    bIsClosed := bAtC;
  ELSE
    bIsClosed := tNow - tMovedAt >= refData.set.tCloseTime AND NOT bHalted AND bActRemote;
  END_IF;
  bIsOpen := FALSE;
  bTravelBad := bUseC AND NOT bAtC AND tNow - tMovedAt > refData.set.tCloseTime * 3 / 2;
END_IF;

IF ((bWantOpen AND refData.set.bUseOpenLs AND bOpenLs) OR (NOT bWantOpen AND bAtC)) AND NOT bReached THEN
  bReached := TRUE;
  (* a stroke confirmed by its end switch: its time, slow or not *)
  refData.sts.tLastStroke := tNow - tMovedAt;
  bSlowCause := refData.set.tStrokeWarn > T#0s AND refData.sts.tLastStroke > refData.set.tStrokeWarn;
END_IF;
IF refData.set.tStrokeWarn <= T#0s THEN
  bSlowCause := FALSE;
END_IF;
(* halted, or the actuator in Local: no travel checks *)
bTravelBad := bTravelBad AND NOT bReached AND NOT bHalted AND bActRemote;

(* protections *)
bX := F_Protect(tNow := tNow, bCause := bTravelBad, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                stSet := refData.set.stTravel, stSts := refData.sts.stTravel, stWork := stWTravel);
bX := F_Protect(tNow := tNow, bCause := refData.set.bUseOpenLs AND refData.set.bUseClosedLs AND bOpenLs AND bClosedLs,
                bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                stSet := refData.set.stBothLimits, stSts := refData.sts.stBothLimits, stWork := stWBoth);
(* position lost: the end switch of the commanded position was made, then went *)
bX := F_Protect(tNow := tNow,
                bCause := bReached AND bActRemote AND ((bWantOpen AND refData.set.bUseOpenLs AND NOT bOpenLs)
                                        OR (NOT bWantOpen AND refData.set.bUseClosedLs AND NOT bClosedLs AND NOT bSeated)),
                bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                stSet := refData.set.stPositionLost, stSts := refData.sts.stPositionLost, stWork := stWLost);
bX := F_Protect(tNow := tNow, bCause := bSlowCause, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                stSet := refData.set.stSlowStroke, stSts := refData.sts.stSlowStroke, stWork := stWSlow);
bX := F_Protect(tNow := tNow, bCause := NOT bActRemote AND refData.set.eMode <> E_Mode.OutOfService,
                bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
                stSet := refData.set.stActLocal, stSts := refData.sts.stActLocal, stWork := stWLocal);
bTrip := stWTravel.bTrip OR stWBoth.bTrip OR stWLost.bTrip OR stWSlow.bTrip OR stWLocal.bTrip OR bVarTrip;
bWarn := stWTravel.bWarn OR stWBoth.bWarn OR stWLost.bWarn OR stWSlow.bWarn OR stWLocal.bWarn OR bVarWarn;
eOwn := E_UtError.None;
IF bVarTrip THEN
  eOwn := eVarError;
ELSIF stWTravel.bTrip OR stWTravel.bWarn THEN
  eOwn := E_UtError.TravelTimeout;
ELSIF stWBoth.bTrip OR stWBoth.bWarn THEN
  eOwn := E_UtError.BothLimits;
ELSIF stWLost.bTrip OR stWLost.bWarn THEN
  eOwn := E_UtError.PositionLost;
ELSIF stWLocal.bTrip OR stWLocal.bWarn THEN
  eOwn := E_UtError.ActuatorLocal;
ELSIF stWSlow.bTrip OR stWSlow.bWarn THEN
  eOwn := E_UtError.SlowStroke;
ELSIF bVarWarn THEN
  eOwn := eVarError;
END_IF;

Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset, tRestartDelay := T#0s);

refData.sts.bOpen := bIsOpen;
refData.sts.bClosed := bIsClosed;
refData.sts.bMoving := NOT bIsOpen AND NOT bIsClosed AND NOT bHalted;
refData.sts.bActLocal := NOT bActRemote;
IF tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;

END_FUNCTION_BLOCK