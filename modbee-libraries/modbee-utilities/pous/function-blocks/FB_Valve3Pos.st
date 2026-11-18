(* FB_Valve3Pos — a three-position valve: a 3-way diverter (A / closed / B), a spring-centred double solenoid, a
three-coil valve, or a motorised valve with a mid position. Positions 1, 2, 3.
On FB_Equipment: an owner (a route, a zone) drives it through I_Equipment.Request: bRun = go, fSpeed = the position
1..3 (none: set.nAutoPos, default 3); its request off = set.nRestPos, or with set.bPosLatch the last position
asked (it stays there until another is asked). Hand: set.nHandPos (kept; nCmdPos 1..3, or
FB_LocalControl's bPos1..bPos3, writes it and starts in Hand); a motorised valve: FB_LocalControl's bHalt stops it
where it is until the next position or command. Off, the interlock or a trip: set.nSafePos. "Running" is away
from the rest position. An FB_Exercise part on it moves an idle valve (in Auto) to nAutoPos for its run time.
Pins: bLs1, bLs2, bLs3 (the positions' switches, with set.bUseLs1..3), refData -> bOut1, bOut2, bOut3,
nPosition (1..3 reached, -1 moving / not known), plus FB_Equipment's and FB_Object's outputs.
Kinds (set.eKind): SpringCentre (bOut1 / bOut3 held, none for 2: the springs centre it), ThreeCoil (bOut1..3 held),
Motor (bOut1 drives toward 1, bOut3 toward 3, set.tReversal between; the mid by bLs2, or timed set.tMid from a
known end (0 = half tTravel); a position not known goes to 1 first). Arrival: the position's switch when used,
else set.tTravel after the move started. A switch that does not come within tTravel + 50 % of a move: the travel
protection (TravelTimeout); a switch lost after arrival is set.stPositionLost's. Settings are kept by the block
(a retained last-good copy): restored at power-up, a bad write put back; a bad setting with no good copy is a trip (BadSetting) with every output off (a spring-centred valve
centres). Moves counted (tot.nStrokes: each new target 1..3), kept hourly; the record's bCmdPreset sets it to
nPresetStrokes; sts.tLastStroke is the last move's time. With the switches: set.stBothLimits (two made at once),
set.stPositionLost (the reached position's switch lost), set.stNoMovement (off by default: moving, and the switch
of the position it left still made). Simulation (the record's bSimulate, not kept, cleared by a system reset): the
switches are ignored and the travel times decide, with a warning (Simulated). *)

FUNCTION_BLOCK FB_Valve3Pos EXTENDS FB_Equipment IMPLEMENTS I_LocalChoice
  VAR_INPUT
    bLs1 : BOOL := FALSE;
    bLs2 : BOOL;
    bLs3 : BOOL;
    refData : REFERENCE TO ST_Valve3PosData;
  END_VAR
  VAR_OUTPUT
    bOut1 : BOOL;
    bOut2 : BOOL;
    bOut3 : BOOL;
    nPosition : INT; (* 1..3 reached, -1 moving / not known *)
  END_VAR
  VAR RETAIN
    stKept : ST_Valve3PosSet;
    stKeptTot : ST_ValveTot;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 3;
  END_VAR
  VAR
    nTarget : INT; (* 1..3; 0 hold *)
    nTargetPrev : INT;
    nPos : INT := -1; (* reached (-1 moving / not known) *)
    nLeg : INT; (* motor: where this leg goes (0 = none) *)
    nLegPrev : INT;
    nLastEnd : INT; (* motor: the last position reached (0 = not known) *)
    tMovedAt : TIME;
    fbCo : FB_Changeover;
    stWTravel : ST_ProtectionWork;
    stWBoth : ST_ProtectionWork;
    stWLost : ST_ProtectionWork;
    stWNoMove : ST_ProtectionWork;
    nLeftPos : INT; (* the position a move left (its switch must go) *)
    nPosWas : INT;
    bCfgBad : BOOL; (* a bad setting with no good copy to put back *)
    nCountedTarget : INT; (* the last target counted as a stroke *)
    tKeptAt : TIME;
    nLatched : INT; (* bPosLatch: the last position asked (0 none) *)
    bHalted : BOOL; (* Hand, motor: stopped where it is *)
    bHaltReq : BOOL;
  END_VAR
  VAR_TEMP
    aUse : ARRAY [1..3] OF BOOL; (* a position's switch is used (not while simulated) *)
    aMade : ARRAY [1..3] OF BOOL;
    nMade : INT;
    bLost : BOOL;
    bNoMove : BOOL;
    bReset : BOOL;
    bTrip : BOOL;
    bWarn : BOOL;
    eOwn : E_UtError;
    tTrav : TIME;
    tMidT : TIME;
    bAtSw : BOOL;
    bUseSw : BOOL;
    bTimed : BOOL;
    bTravelBad : BOOL;
  END_VAR


(* bRun: go. The target, for the outputs below. *)
METHOD PROTECTED Drive
  VAR_INPUT
    bRun : BOOL;
  END_VAR
  IF bCfgBad THEN
    nTarget := 0;                 (* every output off *)
  ELSIF NOT bRun AND (eStop = E_StopReason.Off OR eStop = E_StopReason.Interlock OR eStop = E_StopReason.Fault) THEN
    nTarget := refData.set.nSafePos;
    nLatched := 0;
  ELSIF bHalted THEN
    nTarget := 0;                 (* Hand halt: stopped where it is *)
  ELSIF NOT bRun AND refData.set.bPosLatch AND nLatched >= 1 AND refData.set.eMode = E_Mode.Auto THEN
    nTarget := nLatched;          (* the last position asked stays *)
  ELSIF NOT bRun THEN
    nTarget := refData.set.nRestPos;
  ELSIF refData.set.eMode = E_Mode.Hand THEN
    nTarget := refData.set.nHandPos;
    nLatched := 0;
  ELSIF fSpeedReq >= 0.5 AND fSpeedReq <= 3.5 THEN
    nTarget := REAL_TO_INT(fSpeedReq);
    nLatched := nTarget;
  ELSE
    nTarget := refData.set.nAutoPos;
    nLatched := nTarget;
  END_IF;
END_METHOD

(* the Auto decision: the owner's request, or a part's (FB_Exercise) *)
METHOD PROTECTED OVERRIDE ShapeRun : BOOL
  VAR_INPUT
    bWant : BOOL;
  END_VAR
  ShapeRun := bWant OR bPartRequest;
END_METHOD

(* a panel choice (FB_LocalControl bPos1..bPos3, bHalt): in Hand *)
METHOD PUBLIC Choose : BOOL
  VAR_INPUT
    eChoice : E_LocalChoice;
  END_VAR
  Choose := FALSE;
  IF NOT __ISVALIDREF(refData) THEN
    RETURN;
  END_IF;
  CASE eChoice OF
    E_LocalChoice.Pos1, E_LocalChoice.Pos2, E_LocalChoice.Pos3:
      Choose := TRUE;
      IF refData.set.eMode = E_Mode.Hand THEN
        CASE eChoice OF
          E_LocalChoice.Pos1: refData.nCmdPos := 1;
          E_LocalChoice.Pos2: refData.nCmdPos := 2;
        ELSE
          refData.nCmdPos := 3;
        END_CASE;
      END_IF;
    E_LocalChoice.Halt:
      Choose := refData.set.eKind = E_Valve3Kind.Motor;
      IF Choose AND refData.set.eMode = E_Mode.Hand THEN
        bHaltReq := TRUE;
      END_IF;
  ELSE
    ;
  END_CASE;
END_METHOD

(* "running" is away from the rest position *)
METHOD PROTECTED FeedbackOk : BOOL
  FeedbackOk := nPos >= 1 AND __ISVALIDREF(refData);
  IF FeedbackOk THEN
    FeedbackOk := nPos <> refData.set.nRestPos;
  END_IF;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_Valve3PosSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.eKind = E_Valve3Kind.SpringCentre OR stS.eKind = E_Valve3Kind.ThreeCoil
          OR stS.eKind = E_Valve3Kind.Motor) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.tTravel > T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tMid >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tMid < stS.tTravel) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.tReversal >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.nSafePos >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nSafePos <= 3) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.nRestPos >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nRestPos <= 3) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.nHandPos >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nHandPos <= 3) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tRetryWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stTravel.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stTravel.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stTravel.nMaxRetries >= 0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.nAutoPos >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nAutoPos <= 3) THEN
    SetWhy := E_UtError.AboveMax;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_Valve3PosSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bOut1 := FALSE;
  bOut2 := FALSE;
  bOut3 := FALSE;
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
ELSIF SetOk(stS := refData.set) THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
bCfgBad := NOT SetOk(stS := refData.set);
(* Hand halt (motor): until the next position, open / close command or a change of mode *)
IF bHaltReq AND refData.set.eMode = E_Mode.Hand AND refData.set.eKind = E_Valve3Kind.Motor THEN
  bHalted := TRUE;
ELSIF refData.set.eMode <> E_Mode.Hand OR refData.nCmdPos >= 1 OR bCmdStartIn OR bCmdStopIn
      OR refData.bCmdStart OR refData.bCmdStop THEN
  bHalted := FALSE;
END_IF;
bHaltReq := FALSE;
IF refData.nCmdPos >= 1 AND refData.nCmdPos <= 3 THEN
  refData.set.nHandPos := refData.nCmdPos;
  IF refData.set.eMode = E_Mode.Hand THEN
    Command(eCmd := E_EquipCmd.Start);
  END_IF;
END_IF;
refData.nCmdPos := -1;

bReset := Begin(refCmd := refData, refSet := refData.set, refSts := refData.sts);
IF SystemReset() THEN refData.bSimulate := FALSE; END_IF;
aUse[1] := refData.set.bUseLs1 AND NOT refData.bSimulate;
aUse[2] := refData.set.bUseLs2 AND NOT refData.bSimulate;
aUse[3] := refData.set.bUseLs3 AND NOT refData.bSimulate;
aMade[1] := aUse[1] AND bLs1;
aMade[2] := aUse[2] AND bLs2;
aMade[3] := aUse[3] AND bLs3;
IF refData.bCmdPreset THEN
  refData.tot.nStrokes := refData.nPresetStrokes;
  stKeptTot := refData.tot;
  refData.bCmdPreset := FALSE;
END_IF;
tTrav := refData.set.tTravel;
tMidT := refData.set.tMid;
IF tMidT <= T#0s THEN
  tMidT := tTrav / 2;
END_IF;

(* where it is, and the outputs (on last scan's target: the engine's Drive sets the new one in Finish) *)
bOut1 := FALSE;
bOut2 := FALSE;
bOut3 := FALSE;
bTravelBad := FALSE;
IF refData.set.eKind = E_Valve3Kind.Motor THEN
  (* one leg at a time toward the target, from a known end; a position not known finds 1 first *)
  IF nTarget = 0 OR nPos = nTarget THEN
    nLeg := 0;
  ELSIF nTarget = 2 AND nLastEnd <> 1 AND nLastEnd <> 3 THEN
    nLeg := 1;                    (* the mid needs a known end to move from *)
  ELSE
    nLeg := nTarget;
  END_IF;
  IF nLeg <> nLegPrev THEN
    tMovedAt := tNow;
    IF nLeg <> 0 THEN
      nPos := -1;                 (* moving *)
    END_IF;
  END_IF;
  nLegPrev := nLeg;
  IF bHalted AND nPos < 1 THEN
    nLastEnd := 0;                (* stopped between positions: not known *)
  END_IF;
  IF nLeg <> 0 THEN
    CASE nLeg OF
      1: bUseSw := aUse[1]; bAtSw := bLs1;
      2: bUseSw := aUse[2]; bAtSw := bLs2;
    ELSE
      bUseSw := aUse[3]; bAtSw := bLs3;
    END_CASE;
    bTimed := nLeg = 2 AND NOT bUseSw;
    IF (bUseSw AND bAtSw) OR (bTimed AND tNow - tMovedAt >= tMidT)
       OR (NOT bUseSw AND NOT bTimed AND tNow - tMovedAt >= tTrav) THEN
      nPos := nLeg;               (* there *)
      nLastEnd := nLeg;
    END_IF;
    bTravelBad := bUseSw AND NOT bAtSw AND nPos <> nLeg AND tNow - tMovedAt > tTrav * 3 / 2;  // moving only
  END_IF;
  (* the drive: B (bOut3) toward 3, A (bOut1) toward 1; the mid moves away from the end it left *)
  fbCo(bRun := nLeg <> 0 AND nPos <> nLeg, bWantB := nLeg = 3 OR (nLeg = 2 AND nLastEnd = 1),
       bUseFb := FALSE, tGapAB := refData.set.tReversal, tGapBA := refData.set.tReversal);
  bOut1 := fbCo.bQA;
  bOut3 := fbCo.bQB;
ELSE
  (* solenoids hold their coil *)
  IF nTarget <> nTargetPrev THEN
    tMovedAt := tNow;
    nPos := -1;
  END_IF;
  IF nTarget >= 1 THEN
    CASE nTarget OF
      1: bUseSw := aUse[1]; bAtSw := bLs1;
      2: bUseSw := aUse[2]; bAtSw := bLs2;
    ELSE
      bUseSw := aUse[3]; bAtSw := bLs3;
    END_CASE;
    IF (bUseSw AND bAtSw) OR (NOT bUseSw AND tNow - tMovedAt >= tTrav) THEN
      nPos := nTarget;
    END_IF;
    bTravelBad := bUseSw AND NOT bAtSw AND nPos <> nTarget AND tNow - tMovedAt > tTrav * 3 / 2;  // moving only
    bOut1 := nTarget = 1;
    bOut2 := nTarget = 2 AND refData.set.eKind = E_Valve3Kind.ThreeCoil;
    bOut3 := nTarget = 3;
  END_IF;
END_IF;
nTargetPrev := nTarget;
IF nPos >= 1 THEN
  refData.sts.nActualPos := nPos;
END_IF;

(* a move: its start position and, on arrival, its time *)
IF nPos = -1 AND nPosWas >= 1 THEN
  nLeftPos := nPosWas;
END_IF;
IF nPos >= 1 AND nPosWas = -1 THEN
  refData.sts.tLastStroke := tNow - tMovedAt;
  nLeftPos := 0;
END_IF;
nPosWas := nPos;
nMade := 0;
IF aMade[1] THEN nMade := nMade + 1; END_IF;
IF aMade[2] THEN nMade := nMade + 1; END_IF;
IF aMade[3] THEN nMade := nMade + 1; END_IF;
bLost := FALSE;
IF nPos >= 1 AND nPos = nTarget THEN       // at its target: the target's switch, when used, stays made
  bLost := aUse[nPos] AND NOT aMade[nPos];
END_IF;
bNoMove := FALSE;
IF nPos = -1 AND nLeftPos >= 1 AND nLeftPos <= 3 AND NOT bHalted THEN
  bNoMove := aMade[nLeftPos];              // moving, and the switch it left still made
END_IF;

(* the protections *)
F_Protect(tNow := tNow, bCause := bTravelBad, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
          stSet := refData.set.stTravel, stSts := refData.sts.stTravel, stWork := stWTravel);
F_Protect(tNow := tNow, bCause := nMade >= 2, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
          stSet := refData.set.stBothLimits, stSts := refData.sts.stBothLimits, stWork := stWBoth);
F_Protect(tNow := tNow, bCause := bLost, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
          stSet := refData.set.stPositionLost, stSts := refData.sts.stPositionLost, stWork := stWLost);
F_Protect(tNow := tNow, bCause := bNoMove, bResetReq := bReset, tRetryWindow := refData.set.tRetryWindow,
          stSet := refData.set.stNoMovement, stSts := refData.sts.stNoMovement, stWork := stWNoMove);
bTrip := stWTravel.bTrip OR stWBoth.bTrip OR stWLost.bTrip OR stWNoMove.bTrip;
bWarn := stWTravel.bWarn OR stWBoth.bWarn OR stWLost.bWarn OR stWNoMove.bWarn OR refData.bSimulate;
eOwn := E_UtError.None;
IF bCfgBad THEN
  bTrip := TRUE;
  eOwn := E_UtError.BadSetting;
ELSIF stWBoth.bTrip OR stWBoth.bWarn THEN
  eOwn := E_UtError.BothLimits;
ELSIF stWNoMove.bTrip OR stWNoMove.bWarn THEN
  eOwn := E_UtError.NoMovement;
ELSIF stWTravel.bTrip OR stWTravel.bWarn THEN
  eOwn := E_UtError.TravelTimeout;
ELSIF stWLost.bTrip OR stWLost.bWarn THEN
  eOwn := E_UtError.PositionLost;
ELSIF refData.bSimulate THEN
  eOwn := E_UtError.Simulated;
END_IF;
(* strokes: each new target 1..3 *)
IF nTarget >= 1 AND nTarget <> nCountedTarget THEN
  refData.tot.nStrokes := refData.tot.nStrokes + 1;
END_IF;
IF nTarget >= 1 THEN
  nCountedTarget := nTarget;
END_IF;
IF tNow - tKeptAt >= T#1h THEN
  stKeptTot := refData.tot;
  tKeptAt := tNow;
END_IF;
Finish(refCmd := refData, refSet := refData.set, refSts := refData.sts,
       bOwnTrip := bTrip, bOwnWarn := bWarn, eOwnError := eOwn, bReset := bReset, tRestartDelay := T#0s);
nPosition := nPos;
refData.sts.nTargetPos := nTarget;

END_FUNCTION_BLOCK