(* FB_LevelFloats — the floats of a sump or wet well, as a part of its FB_LevelControl (EMPTY duty).

Pins: ipFloats (the float switches, an FB_SwitchSet: Band(High) / Band(HighHigh) / Band(Low) / Band(LowLow)),
ipLevel (the transducer, to check it; unwired = floats only), ipOwner (the level control), refData
-> bTransducerFault, bFloatControl, plus FB_Object's bWarning / eErrorId / eState.
- Overflow backup: the high float made asks the level control to run (E_PartAction.Run); it keeps asking for
  set.tHighHold after the float clears.
- Transducer check: the high float made while the level reads below the check level for set.tCheckDelay is a
  transducer fault, latched until a reset (the owner's or the record's) or a power cycle: bTransducerFault,
  a warning on the owner. The check level: set.fCheckLevel; 0 (the default) = the level control's high-high
  (ipOwner.fActHighHigh); no check while that is not used either (3.4E38).
- Float / timer control, with the transducer fault or with no level value (unwired, not fitted, no value or
  not good): run while the high float is made and set.tFloatRunTime after it clears, then set.tLockout before
  the high float can start it again (the high-high float starts it at any time). The low float stops at once
  (E_PartAction.Stop, also the level control's own request).
- Both floats made: high wins, and "floats disagree" (a warning).
- set.bRunAll: while the overflow backup asks, bRunAll is TRUE (wire it to FB_Stages.bRunAll: every pump runs).
- Totals: tot.nHighEvents (high float made) and tot.tHighTime (its made time, added when it clears), kept over a
  power cut; the record's bCmdResetStats zeroes them.
One action per Evaluate: Run > Stop > Warn. The warnings also show on the part's own bWarning / eErrorId.
Its rung stopping while it acts is PartLost on its owner.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_LevelFloats EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipFloats : I_Measurement; (* required *)
    ipLevel : I_Measurement; (* the transducer (optional) *)
    ipOwner : I_LevelControl; (* required: the level control *)
    refData : REFERENCE TO ST_LevelFloatsData;
  END_VAR
  VAR_OUTPUT
    bTransducerFault : BOOL;
    bFloatControl : BOOL;
    bRunAll : BOOL; (* the overflow backup asks every pump (set.bRunAll) *)
  END_VAR
  VAR RETAIN
    stKept : ST_LevelFloatsSet;
    nKeptLayout : UINT;
    stKeptTot : ST_LevelFloatsTot; (* totals, kept at each event end and on a reset *)
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
    cNotUsed : REAL := 3.4E38; (* a level that is not used *)
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bDisagree : BOOL;
    bHighRun : BOOL; (* the overflow backup *)
    tHighAt : TIME;
    bHWas : BOOL;
    tHFrom : TIME;
    bFloatRun : BOOL; (* float control *)
    tRunAt : TIME;
    bLocked : BOOL;
    tLockAt : TIME;
    bStopNow : BOOL;
    bChecking : BOOL;
    tCheckAt : TIME;
  END_VAR
  VAR_TEMP
    bH : BOOL;
    bHH : BOOL;
    bL : BOOL;
    bLvlOk : BOOL;
    fCheck : REAL;
  END_VAR


METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND (bHighRun OR bFloatRun OR bStopNow OR bTransducerFault) THEN
    eErrorId := E_UtError.PartLost;
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  IF bResetWanted THEN
    bTransducerFault := FALSE;
    bChecking := FALSE;
  END_IF;
  IF bTransducerFault THEN
    eErrorId := E_UtError.TransducerFault;
  ELSIF bDisagree THEN
    eErrorId := E_UtError.FloatsDisagree;
  ELSE
    eErrorId := E_UtError.None;
  END_IF;
  IF bHighRun OR bFloatRun THEN
    Evaluate := E_PartAction.Run;
  ELSIF bStopNow THEN
    Evaluate := E_PartAction.Stop;
  ELSIF bTransducerFault OR bDisagree THEN
    Evaluate := E_PartAction.Warn;
  ELSE
    Evaluate := E_PartAction.None;
  END_IF;
END_METHOD

METHOD PUBLIC SetNext
  VAR_INPUT
    ipNext : I_Part;
  END_VAR
  THIS^.ipNext := ipNext;
END_METHOD

METHOD PUBLIC GetNext : I_Part
  GetNext := ipNext;
END_METHOD

METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tHighHold >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tFloatRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tLockout >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.tCheckDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (refData.set.fCheckLevel = refData.set.fCheckLevel) THEN   // NaN
    SetWhy := E_UtError.ValueBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  SetOk := SetWhy() = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL OR ipFloats = NULL THEN
  bError := TRUE;
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
  ELSIF ipOwner = NULL THEN
    eErrorId := E_UtError.NoMotor;
  ELSE
    eErrorId := E_UtError.NoMeasurement;
  END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
    refData.tot := stKeptTot;
  ELSE
    stKept := refData.set;
    stKeptTot := refData.tot;
    nKeptLayout := cLayout;
  END_IF;
ELSIF SetOk() THEN
  stKept := refData.set;
ELSE
  refData.sts.eRefusedWhy := SetWhy();
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
  bTransducerFault := FALSE;
  bChecking := FALSE;
END_IF;

IF refData.bCmdResetStats THEN
  refData.tot.nHighEvents := 0;
  refData.tot.tHighTime := T#0s;
  stKeptTot := refData.tot;
  refData.bCmdResetStats := FALSE;
END_IF;
(* the floats: high wins *)
IF ipFloats.bIsFitted THEN
  bH := ipFloats.Band(eBand := E_Band.High);
  bHH := ipFloats.Band(eBand := E_Band.HighHigh);
  bL := ipFloats.Band(eBand := E_Band.Low);
ELSE
  bH := FALSE;
  bHH := FALSE;
  bL := FALSE;
END_IF;
bDisagree := bH AND bL;
IF bDisagree THEN
  bL := FALSE;
END_IF;

(* the transducer check *)
bLvlOk := FALSE;
IF ipLevel <> NULL THEN
  bLvlOk := ipLevel.bIsFitted AND ipLevel.bHasValue AND ipLevel.bIsGood;
END_IF;
IF refData.set.fCheckLevel > 0.0 THEN
  fCheck := refData.set.fCheckLevel;
ELSE
  fCheck := ipOwner.fActHighHigh;
END_IF;
IF bLvlOk AND bH AND fCheck < cNotUsed AND ipLevel.fActValue < fCheck THEN
  IF NOT bChecking THEN
    bChecking := TRUE;
    tCheckAt := tNow;
  END_IF;
  IF tNow - tCheckAt >= refData.set.tCheckDelay THEN
    bTransducerFault := TRUE;
  END_IF;
ELSE
  bChecking := FALSE;
END_IF;
bFloatControl := bTransducerFault OR NOT bLvlOk;

IF NOT bFloatControl THEN
  (* the overflow backup *)
  bFloatRun := FALSE;
  bLocked := FALSE;
  bStopNow := FALSE;
  IF bH THEN
    bHighRun := TRUE;
    tHighAt := tNow;
  ELSIF bHighRun AND tNow - tHighAt >= refData.set.tHighHold THEN
    bHighRun := FALSE;
  END_IF;
  IF bHighRun AND NOT bH THEN
    refData.sts.tTimeLeft := refData.set.tHighHold - (tNow - tHighAt);
  ELSE
    refData.sts.tTimeLeft := T#0s;
  END_IF;
ELSE
  (* float / timer control *)
  bHighRun := FALSE;
  IF bHH OR (bH AND NOT bLocked) THEN
    bFloatRun := TRUE;
    tRunAt := tNow;
  ELSIF bFloatRun AND (bL OR tNow - tRunAt >= refData.set.tFloatRunTime) THEN
    bFloatRun := FALSE;
    bLocked := TRUE;
    tLockAt := tNow;
  END_IF;
  IF bLocked AND tNow - tLockAt >= refData.set.tLockout THEN
    bLocked := FALSE;
  END_IF;
  bStopNow := bL AND NOT bFloatRun;
  IF bFloatRun AND NOT bH THEN
    refData.sts.tTimeLeft := refData.set.tFloatRunTime - (tNow - tRunAt);
  ELSIF bLocked THEN
    refData.sts.tTimeLeft := refData.set.tLockout - (tNow - tLockAt);
  ELSE
    refData.sts.tTimeLeft := T#0s;
  END_IF;
END_IF;
bCalled := TRUE;

(* status *)
bError := FALSE;
bWarning := bTransducerFault OR bDisagree OR refData.sts.bRefused;
IF bTransducerFault THEN
  eErrorId := E_UtError.TransducerFault;
ELSIF bDisagree THEN
  eErrorId := E_UtError.FloatsDisagree;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bHighRun OR bFloatRun THEN
  eState := E_State.Running;
ELSIF bStopNow THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Idle;
END_IF;
refData.sts.bRun := bHighRun OR bFloatRun;
bRunAll := bHighRun AND refData.set.bRunAll;
(* the high float's events: counted when made, timed and kept when it clears *)
IF bH AND NOT bHWas THEN
  refData.tot.nHighEvents := refData.tot.nHighEvents + 1;
  tHFrom := tNow;
ELSIF bHWas AND NOT bH THEN
  refData.tot.tHighTime := refData.tot.tHighTime + (tNow - tHFrom);
  stKeptTot := refData.tot;
END_IF;
bHWas := bH;
refData.sts.bStop := bStopNow;
refData.sts.bFloatControl := bFloatControl;
refData.sts.bTransducerFault := bTransducerFault;
refData.sts.bDisagree := bDisagree;
refData.sts.bLocked := bLocked;
bFirstScan := FALSE;

END_FUNCTION_BLOCK