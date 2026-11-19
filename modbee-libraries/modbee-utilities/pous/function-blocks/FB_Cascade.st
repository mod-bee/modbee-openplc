(* FB_Cascade — the staging of a pump cascade on one header holding a pressure or a flow. A cascade is built from
blocks: FB_SpeedLoop (the PID, the setpoint, sleep, the protections) drives an FB_Group of pumps (the group passes
the loop's speed to every pump it calls: one shared speed; rotation, failover, swap, staged stop, the jockey) and
FB_Cascade decides how many: nExtraPumps -> FB_Group.nExtraMembers. A fixed-speed set uses FB_SpeedLoop with Fixed control
(its fShortOfSetpoint still compares Pv with the setpoint) and set.bPumpsOnVsd FALSE here.
Pins: fSpeedSetpointPct (the shared speed %, the loop's fSpeedSetpointPct), bLoopRunning (the loop is running), nDutyPumps (duty pumps,
FB_Group.nDutyMembers), nDutyPumpsRunning (duty pumps running, FB_Group.nDutyMembersRunning; -1 = not wired: no settled check),
bPermissive, fShortOfSetpoint (the loop's fShortOfSetpoint: how far the value is short of the setpoint; unwired = the speed alone),
eLoopPhase (the loop's eLoopPhase; unwired = Control), ipHeaderFlow (the header flow: Flow / PerPump staging and the jockey;
unwired = none), fRunningCapacity (FB_Group.fRunningCapacity), fJockeyCapacity (FB_Group.fJockeyCapacity), bJockeyReady
(FB_Group.bJockeyReady), refData -> nExtraPumps (-1 = the jockey alone), plus FB_Object's outputs. The record shows
the rule in use (eStageRuleInUse), the jockey's turn, bPressureRuleFallback, bFlowNotGood and fFlowPerPump (the flow per running pump).
Staging, one pump at a time, only while the loop is in Control (Manual speed: none added or dropped); the need
must last set.tAddPumpDelay (add) or set.tDropPumpDelay (drop); after a change the next one waits the delay again;
a pump is added only when the group has settled (nDutyPumpsRunning has reached 1 + nExtraPumps) and bPermissive is on.
set.eStageRule:
  Pressure  set.bPumpsOnVsd: add with the speed at or above set.fAddPumpAtSpeedPct and the value short of the setpoint by more
            than set.fAddWhenShortBy; drop at or below set.fDropPumpAtSpeedPct (set it to the loop's
            minimum for "at the minimum only") when not short. No VSD (set.bPumpsOnVsd FALSE): add when the value is
            set.fFixedAddWhenShortBy short of the setpoint, drop when it is set.fFixedDropWhenPastBy past it.
  Flow      add above set.fAddAboveCapacityPct % of the running capacity (fRunningCapacity); drop below set.fDropBelowCapacityPct % of the
            capacity left after the drop.
  PerPump   add when the flow per running pump is above set.fAddAboveFlowPerPump (and stays above set.fDropBelowFlowPerPump with one
            more); drop below set.fDropBelowFlowPerPump (and stays below set.fAddAboveFlowPerPump with one fewer).
Flow / PerPump also add on the Pressure rule (the pressure is never left short: a warning PvStaging and the
Pressure rule until the set next starts from none) and fall back to Pressure with a bad or missing meter
(warning SensorBad) or unusable settings (no capacity known, fAddAboveFlowPerPump not above fDropBelowFlowPerPump: warning BadSetting).
Jockey (an FB_Group member with I_Pump role Jockey, bJockeyReady): a start from none begins with the jockey
alone (nExtraPumps -1; not while the loop fills the pipe). It hands over to a duty pump when it cannot keep up: the
flow above fAddAboveCapacityPct % of fJockeyCapacity, or the Pressure rule (short of pressure below its capacity: the
jockey is skipped until the next start). With one duty pump left and the demand falling (the flow below
fDropBelowCapacityPct % of fJockeyCapacity, or the Pressure drop rule) the set hands back to the jockey. The group keeps the
jockey on until the duty pump runs.
bLoopRunning FALSE drops them all (FB_Group's set.eStopOrder decides at once or staged). A burst main:
an FB_LevelCheck (High) on the header flow meter as a part of the group. Its settings are kept by the block (a
retained last-good copy): restored at power-up, a bad write put back (bSettingRefused / eSettingRefusedErrorId, a warning until a
reset). *)

FUNCTION_BLOCK FB_Cascade EXTENDS FB_Object
  VAR_INPUT
    fSpeedSetpointPct : REAL; (* the shared speed %, from the loop *)
    bLoopRunning : BOOL; (* the loop is running *)
    nDutyPumps : INT := 2; (* duty pumps in the group (FB_Group.nDutyMembers) *)
    nDutyPumpsRunning : INT := -1; (* FB_Group.nDutyMembersRunning (-1 = not wired: no settled check) *)
    bPermissive : BOOL := TRUE; (* FALSE: no pump added *)
    fShortOfSetpoint : REAL := 3.4E38; (* the loop's fShortOfSetpoint (unwired: the speed alone) *)
    eLoopPhase : E_LoopPhase := E_LoopPhase.Control; (* the loop's eLoopPhase *)
    ipHeaderFlow : I_Measurement; (* the header flow (unwired = none) *)
    fRunningCapacity : REAL; (* FB_Group.fRunningCapacity *)
    fJockeyCapacity : REAL; (* FB_Group.fJockeyCapacity *)
    bJockeyReady : BOOL; (* FB_Group.bJockeyReady *)
    refData : REFERENCE TO ST_CascadeData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    nExtraPumps : INT; (* -> FB_Group.nExtraMembers (-1 = the jockey alone) *)
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


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_CascadeSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.fDropPumpAtSpeedPct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fAddPumpAtSpeedPct <= 100.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fDropPumpAtSpeedPct < stS.fAddPumpAtSpeedPct) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.tAddPumpDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tDropPumpDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.fAddWhenShortBy >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fFixedAddWhenShortBy >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fFixedDropWhenPastBy >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fDropBelowCapacityPct >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fAddAboveCapacityPct > stS.fDropBelowCapacityPct) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.fAddAboveCapacityPct <= 1000.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fDropBelowFlowPerPump >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fAddAboveFlowPerPump >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fAddAboveFlowPerPump <= 3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.eStageRule = E_StageBy.Pressure OR stS.eStageRule = E_StageBy.Flow
             OR stS.eStageRule = E_StageBy.PerPump) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_CascadeSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  nExtraPumps := 0;
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
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the flow, the rule in use *)
bFlowOk := FALSE;
fFlow := 0.0;
IF ipHeaderFlow <> NULL THEN               // IEC AND does not short-circuit: test NULL on its own
  IF ipHeaderFlow.bIsFitted AND ipHeaderFlow.bHasValue AND ipHeaderFlow.bIsGood THEN
    fFlow := ipHeaderFlow.fActValue;
    bFlowOk := fFlow = fFlow AND ABS(fFlow) <= 3.4E38;
  END_IF;
END_IF;
IF nDutyPumpsRunning > 0 THEN fRunD := INT_TO_REAL(nDutyPumpsRunning); ELSE fRunD := INT_TO_REAL(MAX(0, 1 + nExtraPumps)); END_IF;
eCrit := refData.set.eStageRule;
bCfgWarn := FALSE;
refData.sts.bFlowNotGood := eCrit <> E_StageBy.Pressure AND NOT bFlowOk;
IF refData.sts.bFlowNotGood THEN
  eCrit := E_StageBy.Pressure;       // the meter has failed: stage on pressure
ELSIF (eCrit = E_StageBy.Flow AND fRunD > 0.0 AND NOT (fRunningCapacity > 0.0))
      OR (eCrit = E_StageBy.PerPump AND NOT (refData.set.fAddAboveFlowPerPump > refData.set.fDropBelowFlowPerPump)) THEN
  eCrit := E_StageBy.Pressure;
  bCfgWarn := TRUE;
ELSIF bPvForced THEN
  eCrit := E_StageBy.Pressure;
END_IF;

(* the staging conditions *)
bWired := fShortOfSetpoint < 1.0E37;
bShort := bWired AND fShortOfSetpoint > refData.set.fAddWhenShortBy;
IF refData.set.bPumpsOnVsd THEN
  bPvAdd := fSpeedSetpointPct >= refData.set.fAddPumpAtSpeedPct AND (bShort OR NOT bWired);
  bPvDrop := fSpeedSetpointPct <= refData.set.fDropPumpAtSpeedPct AND NOT bShort;
ELSE
  bPvAdd := bWired AND fShortOfSetpoint > refData.set.fFixedAddWhenShortBy;
  bPvDrop := bWired AND fShortOfSetpoint < -refData.set.fFixedDropWhenPastBy;
  bCfgWarn := bCfgWarn OR NOT bWired;
END_IF;
IF fRunD > 0.0 THEN fPerPump := fFlow / fRunD; ELSE fPerPump := 0.0; END_IF;
bJk := nExtraPumps < 0;
bAdd := FALSE;
bDrop := FALSE;
bHandback := FALSE;
bFlowAdd := TRUE;
IF bLoopRunning AND bOk AND eLoopPhase = E_LoopPhase.Control THEN
  IF bJk THEN
    IF fJockeyCapacity > 0.0 AND bFlowOk THEN
      bFlowAdd := fFlow > refData.set.fAddAboveCapacityPct / 100.0 * fJockeyCapacity;
      bAdd := bFlowAdd OR bPvAdd;
    ELSE
      bAdd := bPvAdd;
    END_IF;
  ELSE
    bHandback := nExtraPumps = 0 AND bJockeyReady AND NOT bJSkip;
    CASE eCrit OF
      E_StageBy.Flow:
        bFlowAdd := fFlow > refData.set.fAddAboveCapacityPct / 100.0 * fRunningCapacity;
        bAdd := bFlowAdd OR bPvAdd;
        IF fRunD > 0.0 THEN
          bDrop := nExtraPumps > 0 AND fFlow < refData.set.fDropBelowCapacityPct / 100.0 * (fRunningCapacity - fRunningCapacity / fRunD);
        END_IF;
      E_StageBy.PerPump:
        IF fRunD > 0.0 THEN
          bFlowAdd := fPerPump > refData.set.fAddAboveFlowPerPump AND fFlow / (fRunD + 1.0) > refData.set.fDropBelowFlowPerPump;
          bAdd := bFlowAdd OR bPvAdd;
          bDrop := nExtraPumps > 0 AND fPerPump < refData.set.fDropBelowFlowPerPump
                   AND (fRunD <= 1.0 OR fFlow / MAX(fRunD - 1.0, 1.0) < refData.set.fAddAboveFlowPerPump);
        END_IF;
    ELSE
      bAdd := bPvAdd;
      bDrop := nExtraPumps > 0 AND bPvDrop;
    END_CASE;
    IF bHandback THEN
      IF fJockeyCapacity > 0.0 AND bFlowOk THEN
        bDrop := fFlow < refData.set.fDropBelowCapacityPct / 100.0 * fJockeyCapacity;
      ELSE
        bDrop := bPvDrop;
      END_IF;
    END_IF;
  END_IF;
END_IF;
IF NOT bAdd OR nExtraPumps >= nDutyPumps - 1 THEN tAddSince := tNow; END_IF;
IF NOT bDrop THEN tDropSince := tNow; END_IF;

(* the stage *)
refData.sts.tAddOrDropTimeLeft := T#0s;
IF NOT bLoopRunning OR NOT bOk THEN
  nExtraPumps := 0;
ELSE
  IF NOT bRunPrev THEN
    (* from none: the jockey first (not for a pipe fill) *)
    bJSkip := FALSE;
    bPvForced := FALSE;
    tAddSince := tNow;
    tDropSince := tNow;
    IF bJockeyReady AND eLoopPhase <> E_LoopPhase.Filling THEN nExtraPumps := -1; ELSE nExtraPumps := 0; END_IF;
  END_IF;
  IF nExtraPumps < 0 AND (NOT bJockeyReady OR eLoopPhase = E_LoopPhase.Filling) THEN
    nExtraPumps := 0;                     // the jockey cannot, or a pipe fill: a duty pump
  END_IF;
  bSettled := nDutyPumpsRunning < 0 OR nDutyPumpsRunning >= MAX(0, 1 + nExtraPumps);
  IF eLoopPhase <> E_LoopPhase.Control THEN
    ;                                // manual speed, filling, ...: none added or dropped
  ELSIF bAdd AND nExtraPumps < nDutyPumps - 1 AND bSettled AND bPermissive AND tNow - tAddSince >= refData.set.tAddPumpDelay THEN
    IF nExtraPumps < 0 THEN
      nExtraPumps := 0;                   // hand over to a duty pump
      IF NOT bFlowAdd THEN bJSkip := TRUE; END_IF;   // short of pressure below its capacity
    ELSE
      nExtraPumps := nExtraPumps + 1;
      IF NOT bFlowAdd THEN bPvForced := TRUE; END_IF;   // the flow rule left the pressure short
    END_IF;
    tAddSince := tNow;
    tDropSince := tNow;
  ELSIF bDrop AND bSettled AND tNow - tDropSince >= refData.set.tDropPumpDelay THEN
    IF nExtraPumps > 0 THEN
      nExtraPumps := nExtraPumps - 1;
    ELSIF bHandback THEN
      nExtraPumps := -1;                  // hand back to the jockey
    END_IF;
    tDropSince := tNow;
    tAddSince := tNow;
  ELSIF bAdd AND nExtraPumps < nDutyPumps - 1 THEN
    refData.sts.tAddOrDropTimeLeft := MAX(T#0s, refData.set.tAddPumpDelay - (tNow - tAddSince));   (* 0: waiting to settle *)
  ELSIF bDrop THEN
    refData.sts.tAddOrDropTimeLeft := MAX(T#0s, refData.set.tDropPumpDelay - (tNow - tDropSince));
  END_IF;
  nExtraPumps := LIMIT(-1, nExtraPumps, MAX(0, nDutyPumps - 1));
END_IF;
bRunPrev := bLoopRunning AND bOk;
refData.sts.nExtraPumps := nExtraPumps;
refData.sts.eStageRuleInUse := eCrit;
refData.sts.bJockeyAlone := nExtraPumps < 0;
refData.sts.bPressureRuleFallback := bPvForced;
IF bFlowOk THEN refData.sts.fFlowPerPump := fPerPump; ELSE refData.sts.fFlowPerPump := 0.0; END_IF;
bError := NOT bOk;
bWarning := NOT bError AND (refData.sts.bSettingRefused OR bCfgWarn OR refData.sts.bFlowNotGood OR bPvForced);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSIF refData.sts.bFlowNotGood THEN
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
ELSIF NOT bLoopRunning THEN
  eState := E_State.Idle;
ELSE
  eState := E_State.Running;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK