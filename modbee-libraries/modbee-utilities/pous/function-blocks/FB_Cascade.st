(* FB_Cascade — the staging of a pump cascade on one header holding a pressure or a flow (src-v2 UT_PUMP_CASCADE's
staging; DESIGN-0.2.md section 5.5). In 0.2 a cascade is built from blocks: FB_SpeedLoop (the PID, the setpoint,
sleep, the protections) drives an FB_Group of pumps (the group passes the loop's speed to every pump it calls:
one shared speed; rotation, failover, swap, staged stop, the jockey) and FB_Cascade decides how many:
nExtra -> FB_Group.nExtra. A fixed-speed set uses FB_SpeedLoop with Fixed control (its fError still compares
Pv with the setpoint) and set.bVsd FALSE here.
Pins: fSpeed (the shared speed %, the loop's fSpeed), bRun (the loop is running), nMembers (duty pumps,
FB_Group.nDuty), nRunning (duty pumps running, FB_Group.nDutyRunning; -1 = not wired: no settled check),
bPermissive, fError (the loop's fError: how far the value is short of the setpoint; unwired = the speed alone),
ePhase (the loop's ePhase; unwired = Control), ipFlow (the header flow: Flow / PerPump staging and the jockey;
unwired = none), fCapacity (FB_Group.fRunCapacity), fJockeyCapacity (FB_Group.fJockeyCapacity), bJockeyReady
(FB_Group.bJockeyReady), refData -> nExtra (-1 = the jockey alone), plus FB_Object's outputs.
Staging, one pump at a time, only while the loop is in Control (Manual speed: none added or dropped); the need
must last set.tStageDelay (add) or set.tDestageDelay (drop); after a change the next one waits the delay again;
a pump is added only when the group has settled (nRunning has reached 1 + nExtra) and bPermissive is on.
set.eStageBy:
  Pressure  set.bVsd: add with the speed at or above set.fStageAt and the value short of the setpoint by more
            than set.fShortBand; drop at or below set.fDestageAt (src-v2's dropSpeed; set it to the loop's
            minimum for "at the minimum only") when not short. No VSD (set.bVsd FALSE): add when the value is
            set.fAddBand short of the setpoint, drop when it is set.fDropBand past it.
  Flow      add above set.fAddPct % of the running capacity (fCapacity); drop below set.fDropPct % of the
            capacity left after the drop.
  PerPump   add when the flow per running pump is above set.fBepMax (and stays above set.fBepMin with one
            more); drop below set.fBepMin (and stays below set.fBepMax with one fewer).
Flow / PerPump also add on the Pressure rule (the pressure is never left short: a warning PvStaging and the
Pressure rule until the set next starts from none) and fall back to Pressure with a bad or missing meter
(warning SensorBad) or unusable settings (no capacity known, fBepMax not above fBepMin: warning BadSetting).
Jockey (an FB_Group member with I_Pump role Jockey, bJockeyReady): a start from none begins with the jockey
alone (nExtra -1; not while the loop fills the pipe). It hands over to a duty pump when it cannot keep up: the
flow above fAddPct % of fJockeyCapacity, or the Pressure rule (short of pressure below its capacity: the
jockey is skipped until the next start). With one duty pump left and the demand falling (the flow below
fDropPct % of fJockeyCapacity, or the Pressure drop rule) the set hands back to the jockey. The group keeps the
jockey on until the duty pump runs.
bRun FALSE drops them all (FB_Group's set.eStop decides at once or staged). A burst main (src-v2's highFlow):
an FB_LevelCheck (High) on the header flow meter as a part of the group. Its settings are kept by the block (a
retained last-good copy): restored at power-up, a bad write put back (bRefused, a warning until a reset). *)

FUNCTION_BLOCK FB_Cascade EXTENDS FB_Object
  VAR_INPUT
    fSpeed : REAL; (* the shared speed %, from the loop *)
    bRun : BOOL; (* the loop is running *)
    nMembers : INT := 2; (* duty pumps in the group (FB_Group.nDuty) *)
    nRunning : INT := -1; (* FB_Group.nDutyRunning (-1 = not wired: no settled check) *)
    bPermissive : BOOL := TRUE; (* FALSE: no pump added *)
    fError : REAL := 3.4E38; (* the loop's fError (unwired: the speed alone) *)
    ePhase : E_LoopPhase := E_LoopPhase.Control; (* the loop's ePhase *)
    ipFlow : I_Measurement; (* the header flow (unwired = none) *)
    fCapacity : REAL; (* FB_Group.fRunCapacity *)
    fJockeyCapacity : REAL; (* FB_Group.fJockeyCapacity *)
    bJockeyReady : BOOL; (* FB_Group.bJockeyReady *)
    refData : REFERENCE TO ST_CascadeData;
  END_VAR
  VAR_OUTPUT
    nExtra : INT; (* -> FB_Group.nExtra (-1 = the jockey alone) *)
  END_VAR
  VAR RETAIN
    stKept : ST_CascadeSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    tAddSince : TIME;
    tDropSince : TIME;
    bRunPrev : BOOL;
    bJSkip : BOOL; (* the jockey could not hold the pressure: skipped until the next start *)
    bPvForced : BOOL;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    bFlowOk : BOOL;
    bWired : BOOL;
    bShort : BOOL;
    bPvAdd : BOOL;
    bPvDrop : BOOL;
    bFlowAdd : BOOL;
    bAdd : BOOL;
    bDrop : BOOL;
    bHandback : BOOL;
    bJk : BOOL;
    bSettled : BOOL;
    bCfgWarn : BOOL;
    fFlow : REAL;
    fPerPump : REAL;
    fRunD : REAL;
    eCrit : E_StageBy;
  END_VAR


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_CascadeSet;
  END_VAR
  SetOk := stS.fDestageAt >= 0.0 AND stS.fStageAt <= 100.0 AND stS.fDestageAt < stS.fStageAt
           AND stS.tStageDelay >= T#0s AND stS.tDestageDelay >= T#0s
           AND stS.fShortBand >= 0.0 AND stS.fAddBand >= 0.0 AND stS.fDropBand >= 0.0
           AND stS.fDropPct >= 0.0 AND stS.fAddPct > stS.fDropPct AND stS.fAddPct <= 1000.0
           AND stS.fBepMin >= 0.0 AND stS.fBepMax >= 0.0 AND stS.fBepMax <= 3.4E38
           AND (stS.eStageBy = E_StageBy.Pressure OR stS.eStageBy = E_StageBy.Flow OR stS.eStageBy = E_StageBy.PerPump);
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  nExtra := 0;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  tAddSince := tNow;
  tDropSince := tNow;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;
  refData.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.bRefused := FALSE;
END_IF;

(* the flow, the rule in use *)
bFlowOk := FALSE;
fFlow := 0.0;
IF ipFlow <> NULL THEN               // IEC AND does not short-circuit: test NULL on its own
  IF ipFlow.bIsFitted AND ipFlow.bHasValue AND ipFlow.bIsGood THEN
    fFlow := ipFlow.fActValue;
    bFlowOk := fFlow = fFlow AND ABS(fFlow) <= 3.4E38;
  END_IF;
END_IF;
IF nRunning > 0 THEN fRunD := INT_TO_REAL(nRunning); ELSE fRunD := INT_TO_REAL(MAX(0, 1 + nExtra)); END_IF;
eCrit := refData.set.eStageBy;
bCfgWarn := FALSE;
refData.bFlowBad := eCrit <> E_StageBy.Pressure AND NOT bFlowOk;
IF refData.bFlowBad THEN
  eCrit := E_StageBy.Pressure;       // the meter has failed: stage on pressure
ELSIF (eCrit = E_StageBy.Flow AND fRunD > 0.0 AND NOT (fCapacity > 0.0))
      OR (eCrit = E_StageBy.PerPump AND NOT (refData.set.fBepMax > refData.set.fBepMin)) THEN
  eCrit := E_StageBy.Pressure;
  bCfgWarn := TRUE;
ELSIF bPvForced THEN
  eCrit := E_StageBy.Pressure;
END_IF;

(* the staging conditions *)
bWired := fError < 1.0E37;
bShort := bWired AND fError > refData.set.fShortBand;
IF refData.set.bVsd THEN
  bPvAdd := fSpeed >= refData.set.fStageAt AND (bShort OR NOT bWired);
  bPvDrop := fSpeed <= refData.set.fDestageAt AND NOT bShort;
ELSE
  bPvAdd := bWired AND fError > refData.set.fAddBand;
  bPvDrop := bWired AND fError < -refData.set.fDropBand;
  bCfgWarn := bCfgWarn OR NOT bWired;
END_IF;
IF fRunD > 0.0 THEN fPerPump := fFlow / fRunD; ELSE fPerPump := 0.0; END_IF;
bJk := nExtra < 0;
bAdd := FALSE;
bDrop := FALSE;
bHandback := FALSE;
bFlowAdd := TRUE;
IF bRun AND bOk AND ePhase = E_LoopPhase.Control THEN
  IF bJk THEN
    IF fJockeyCapacity > 0.0 AND bFlowOk THEN
      bFlowAdd := fFlow > refData.set.fAddPct / 100.0 * fJockeyCapacity;
      bAdd := bFlowAdd OR bPvAdd;
    ELSE
      bAdd := bPvAdd;
    END_IF;
  ELSE
    bHandback := nExtra = 0 AND bJockeyReady AND NOT bJSkip;
    CASE eCrit OF
      E_StageBy.Flow:
        bFlowAdd := fFlow > refData.set.fAddPct / 100.0 * fCapacity;
        bAdd := bFlowAdd OR bPvAdd;
        IF fRunD > 0.0 THEN
          bDrop := nExtra > 0 AND fFlow < refData.set.fDropPct / 100.0 * (fCapacity - fCapacity / fRunD);
        END_IF;
      E_StageBy.PerPump:
        IF fRunD > 0.0 THEN
          bFlowAdd := fPerPump > refData.set.fBepMax AND fFlow / (fRunD + 1.0) > refData.set.fBepMin;
          bAdd := bFlowAdd OR bPvAdd;
          bDrop := nExtra > 0 AND fPerPump < refData.set.fBepMin
                   AND (fRunD <= 1.0 OR fFlow / MAX(fRunD - 1.0, 1.0) < refData.set.fBepMax);
        END_IF;
    ELSE
      bAdd := bPvAdd;
      bDrop := nExtra > 0 AND bPvDrop;
    END_CASE;
    IF bHandback THEN
      IF fJockeyCapacity > 0.0 AND bFlowOk THEN
        bDrop := fFlow < refData.set.fDropPct / 100.0 * fJockeyCapacity;
      ELSE
        bDrop := bPvDrop;
      END_IF;
    END_IF;
  END_IF;
END_IF;
IF NOT bAdd OR nExtra >= nMembers - 1 THEN tAddSince := tNow; END_IF;
IF NOT bDrop THEN tDropSince := tNow; END_IF;

(* the stage *)
refData.tTimeLeft := T#0s;
IF NOT bRun OR NOT bOk THEN
  nExtra := 0;
ELSE
  IF NOT bRunPrev THEN
    (* from none: the jockey first (not for a pipe fill) *)
    bJSkip := FALSE;
    bPvForced := FALSE;
    tAddSince := tNow;
    tDropSince := tNow;
    IF bJockeyReady AND ePhase <> E_LoopPhase.Filling THEN nExtra := -1; ELSE nExtra := 0; END_IF;
  END_IF;
  IF nExtra < 0 AND (NOT bJockeyReady OR ePhase = E_LoopPhase.Filling) THEN
    nExtra := 0;                     // the jockey cannot, or a pipe fill: a duty pump
  END_IF;
  bSettled := nRunning < 0 OR nRunning >= MAX(0, 1 + nExtra);
  IF ePhase <> E_LoopPhase.Control THEN
    ;                                // manual speed, filling, ...: none added or dropped
  ELSIF bAdd AND nExtra < nMembers - 1 AND bSettled AND bPermissive AND tNow - tAddSince >= refData.set.tStageDelay THEN
    IF nExtra < 0 THEN
      nExtra := 0;                   // hand over to a duty pump
      IF NOT bFlowAdd THEN bJSkip := TRUE; END_IF;   // short of pressure below its capacity
    ELSE
      nExtra := nExtra + 1;
      IF NOT bFlowAdd THEN bPvForced := TRUE; END_IF;   // the flow rule left the pressure short
    END_IF;
    tAddSince := tNow;
    tDropSince := tNow;
  ELSIF bDrop AND bSettled AND tNow - tDropSince >= refData.set.tDestageDelay THEN
    IF nExtra > 0 THEN
      nExtra := nExtra - 1;
    ELSIF bHandback THEN
      nExtra := -1;                  // hand back to the jockey
    END_IF;
    tDropSince := tNow;
    tAddSince := tNow;
  ELSIF bAdd AND nExtra < nMembers - 1 THEN
    refData.tTimeLeft := MAX(T#0s, refData.set.tStageDelay - (tNow - tAddSince));   (* 0: waiting to settle *)
  ELSIF bDrop THEN
    refData.tTimeLeft := MAX(T#0s, refData.set.tDestageDelay - (tNow - tDropSince));
  END_IF;
  nExtra := LIMIT(-1, nExtra, MAX(0, nMembers - 1));
END_IF;
bRunPrev := bRun AND bOk;
refData.nExtra := nExtra;
refData.eStageUsed := eCrit;
refData.bJockeyTurn := nExtra < 0;
refData.bPvStaging := bPvForced;
bError := NOT bOk;
bWarning := NOT bError AND (refData.bRefused OR bCfgWarn OR refData.bFlowBad OR bPvForced);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSIF refData.bFlowBad THEN
  eErrorId := E_UtError.SensorBad;
ELSIF bCfgWarn THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bPvForced THEN
  eErrorId := E_UtError.PvStaging;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bRun THEN
  eState := E_State.Idle;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK