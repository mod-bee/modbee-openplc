(* FB_Stages — the extra level stages of a pump station. Stage 1 is FB_LevelControl's own start / stop; this block
adds stages 2..4 and tells an FB_Group how many more pumps to call (nExtraPumps -> FB_Group.nExtraMembers). Stage n is on from
its start point until its stop point: Empty starts above and stops below (fStartLevel > fStopLevel), Fill starts below and
stops above (fStartLevel < fStopLevel); a stage the wrong way round, not a number, or both 0 is not used. Stages 2 and 3
call one pump each; stage 4 calls every remaining pump of a station of more than 3 (nPumps). bLevelControlRunning FALSE (the
level control not running: off, level not trusted, inhibited) drops every stage. A bad level drops them too.
bDemandActive (FB_LevelControl.bDemandActive): while a demand runs, at least set.nDemandPumps pumps run.
Pins: ipLevel, eControlMode (the level control's), bLevelControlRunning, nPumps, bRunAllPumps (every pump: FB_LevelFloats.bRunAllPumps, the
overflow backup), bDemandActive, refData -> nExtraPumps, plus FB_Object's outputs. Its
settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_Stages EXTENDS FB_Object
  VAR_INPUT
    ipLevel : I_Measurement; (* required *)
    eControlMode : E_LevelMode; (* Empty (sump) or Fill (tank): the level control's *)
    bLevelControlRunning : BOOL; (* the stages may act (the level control is running) *)
    nPumps : INT := 2; (* pumps in the station *)
    bRunAllPumps : BOOL; (* every pump (FB_LevelFloats.bRunAllPumps: the overflow backup) *)
    bDemandActive : BOOL; (* a demand runs (FB_LevelControl.bDemandActive) *)
    refData : REFERENCE TO ST_StagesData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    nExtraPumps : INT; (* -> FB_Group.nExtraMembers *)
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


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_StagesSet;
  END_VAR
  VAR
    nI : INT;
  END_VAR
  SetWhy := E_UtError.None;
  IF stS.nDemandPumps < 1 THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF stS.nDemandPumps > 32 THEN
    SetWhy := E_UtError.AboveMax;
  END_IF;
  FOR nI := 2 TO 4 DO
    IF SetWhy = E_UtError.None
       AND NOT (ABS(stS.aExtraPumpLevels[nI].fStartLevel) <= REAL#3.4E38 AND ABS(stS.aExtraPumpLevels[nI].fStopLevel) <= REAL#3.4E38) THEN
      SetWhy := E_UtError.ValueBad;
    END_IF;
  END_FOR;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_StagesSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipLevel = NULL THEN
  nExtraPumps := 0;
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
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOkSet := TRUE;
END_IF;
IF SystemReset() THEN                // the plant reset clears a refused write
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;
bEmpty := eControlMode = E_LevelMode.Empty;
bGood := ipLevel.bIsGood;
fLevel := ipLevel.fActValue;
FOR nS := 2 TO 4 DO
  bUsable := (bEmpty AND refData.set.aExtraPumpLevels[nS].fStartLevel > refData.set.aExtraPumpLevels[nS].fStopLevel)
             OR (NOT bEmpty AND refData.set.aExtraPumpLevels[nS].fStartLevel < refData.set.aExtraPumpLevels[nS].fStopLevel);
  IF NOT bLevelControlRunning OR NOT bUsable OR NOT bGood OR NOT (fLevel = fLevel) THEN
    aLatch[nS] := FALSE;
  ELSIF bEmpty THEN
    IF fLevel >= refData.set.aExtraPumpLevels[nS].fStartLevel THEN
      aLatch[nS] := TRUE;
    ELSIF fLevel <= refData.set.aExtraPumpLevels[nS].fStopLevel THEN
      aLatch[nS] := FALSE;
    END_IF;
  ELSIF fLevel <= refData.set.aExtraPumpLevels[nS].fStartLevel THEN
    aLatch[nS] := TRUE;
  ELSIF fLevel >= refData.set.aExtraPumpLevels[nS].fStopLevel THEN
    aLatch[nS] := FALSE;
  END_IF;
END_FOR;
nExtraPumps := BOOL_TO_INT(aLatch[2]) + BOOL_TO_INT(aLatch[3]);
IF aLatch[4] AND nPumps > 3 THEN
  nExtraPumps := nExtraPumps + nPumps - 3;   (* stage 4: every remaining pump *)
END_IF;
IF bLevelControlRunning AND bDemandActive AND nExtraPumps < refData.set.nDemandPumps - 1 THEN
  nExtraPumps := refData.set.nDemandPumps - 1;   (* a demand runs at least nDemandPumps *)
END_IF;
IF bRunAllPumps THEN
  nExtraPumps := nPumps - 1;         (* the overflow backup: every pump *)
END_IF;
nExtraPumps := LIMIT(0, nExtraPumps, MAX(0, nPumps - 1));
refData.sts.nExtraPumps := nExtraPumps;
bError := FALSE;
bWarning := refData.sts.bSettingRefused;
IF refData.sts.bSettingRefused THEN eErrorId := E_UtError.SettingRefused; ELSE eErrorId := E_UtError.None; END_IF;
IF nExtraPumps > 0 THEN eState := E_State.Running; ELSE eState := E_State.Idle; END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK