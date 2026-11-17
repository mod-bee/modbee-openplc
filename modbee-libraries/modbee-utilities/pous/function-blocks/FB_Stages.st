(* FB_Stages — the extra level stages of a pump station (DESIGN-0.2.md section 5.5; src-v2 UT_STAGE_RUN). Stage 1 is
FB_LevelControl's own start / stop; this block adds stages 2..4 and tells an FB_Group how many more pumps to call
(nExtra -> FB_Group.nExtra). Stage n is on from its start point until its stop point: Empty starts above and stops
below (fStart > fStop), Fill starts below and stops above (fStart < fStop); a stage the wrong way round, not a
number, or both 0 is not used. Stages 2 and 3 call one pump each; stage 4 calls every remaining pump of a station
of more than 3 (nMembers). bRun FALSE (the level control not running: off, level not trusted, inhibited) drops
every stage. A bad level drops them too.
bDemand (FB_LevelControl.bDemandActive): while a demand runs, at least set.nDemandPumps pumps run (src-v2
demandPumps, default 1: no extra).
Pins: ipLevel, eMode (the level control's), bRun, nMembers, bDemand, refData -> nExtra, plus FB_Object's outputs. Its
settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Stages EXTENDS FB_Object
  VAR_INPUT
    ipLevel : I_Measurement; (* required *)
    eMode : E_LevelMode; (* Empty (sump) or Fill (tank): the level control's *)
    bRun : BOOL; (* the stages may act (the level control is running) *)
    nMembers : INT := 2; (* pumps in the station *)
    bDemand : BOOL; (* a demand runs (FB_LevelControl.bDemandActive) *)
    refData : REFERENCE TO ST_StagesData;
  END_VAR
  VAR_OUTPUT
    nExtra : INT; (* -> FB_Group.nExtra *)
  END_VAR
  VAR RETAIN
    stKept : ST_StagesSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    aLatch : ARRAY [2..4] OF BOOL;
  END_VAR
  VAR_TEMP
    bOkSet : BOOL;
    bGood : BOOL;
    bUsable : BOOL;
    bEmpty : BOOL;
    fLevel : REAL;
    nS : INT;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_StagesSet;
  END_VAR
  VAR
    nI : INT;
  END_VAR
  SetOk := stS.nDemandPumps >= 1 AND stS.nDemandPumps <= 32;
  FOR nI := 2 TO 4 DO
    SetOk := SetOk AND ABS(stS.aStage[nI].fStart) <= REAL#3.4E38 AND ABS(stS.aStage[nI].fStop) <= REAL#3.4E38;
  END_FOR;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipLevel = NULL THEN
  nExtra := 0;
  bError := TRUE;
  IF ipLevel = NULL THEN eErrorId := E_UtError.NoMeasurement; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
END_IF;
bOkSet := SetOk(stS := refData.set);
IF bOkSet THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.bRefused := TRUE;
  bOkSet := TRUE;
END_IF;
bEmpty := eMode = E_LevelMode.Empty;
bGood := ipLevel.bIsGood;
fLevel := ipLevel.fActValue;
FOR nS := 2 TO 4 DO
  bUsable := (bEmpty AND refData.set.aStage[nS].fStart > refData.set.aStage[nS].fStop)
             OR (NOT bEmpty AND refData.set.aStage[nS].fStart < refData.set.aStage[nS].fStop);
  IF NOT bRun OR NOT bUsable OR NOT bGood OR NOT (fLevel = fLevel) THEN
    aLatch[nS] := FALSE;
  ELSIF bEmpty THEN
    IF fLevel >= refData.set.aStage[nS].fStart THEN
      aLatch[nS] := TRUE;
    ELSIF fLevel <= refData.set.aStage[nS].fStop THEN
      aLatch[nS] := FALSE;
    END_IF;
  ELSIF fLevel <= refData.set.aStage[nS].fStart THEN
    aLatch[nS] := TRUE;
  ELSIF fLevel >= refData.set.aStage[nS].fStop THEN
    aLatch[nS] := FALSE;
  END_IF;
END_FOR;
nExtra := BOOL_TO_INT(aLatch[2]) + BOOL_TO_INT(aLatch[3]);
IF aLatch[4] AND nMembers > 3 THEN
  nExtra := nExtra + nMembers - 3;   (* stage 4: every remaining pump *)
END_IF;
IF bRun AND bDemand AND nExtra < refData.set.nDemandPumps - 1 THEN
  nExtra := refData.set.nDemandPumps - 1;   (* a demand runs at least nDemandPumps *)
END_IF;
nExtra := LIMIT(0, nExtra, MAX(0, nMembers - 1));
refData.nExtra := nExtra;
bError := FALSE;
bWarning := refData.bRefused;
IF refData.bRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF nExtra > 0 THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK