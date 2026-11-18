(* FB_Booster — a series booster pump that runs with a station's duty pumps, as a part of the station's
FB_LevelControl (one booster, not in the duty rotation).
While the station runs (its request on and its pumps running): set.eStartBy Delay starts the booster
set.tDelay after the duty pumps run; Pressure starts it while ipPressure is at or below set.fStartAt, until it
is at or above set.fStopAt (with a pressure that is not good: as Delay). At a cycle end the booster stops at
once; give the duty pumps a stop delay (FB_Pump set.tStopDelay = the gap) so they stop that much later.
set.bRequired: wanted and not running for set.stLost's delay -> BoosterLost (a trip stops the station).
bPermit FALSE (default TRUE) keeps the booster off whatever the rule says (it stops at once).
Pins: ipBooster (the booster pump, required), ipPressure (optional), ipOwner (the station's level control,
required), bPermit, refData -> bWanted, plus FB_Object's outputs. It adds itself to the station on its first call; a check
that is acting when its rung stops being called raises PartLost. *)

FUNCTION_BLOCK FB_Booster EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipBooster : I_Equipment; (* the booster pump (required) *)
    ipPressure : I_Measurement; (* Pressure start (optional) *)
    ipOwner : I_PartOwner; (* the station's level control (required) *)
    bPermit : BOOL := TRUE; (* FALSE: the booster does not run now (it stops at once) *)
    refData : REFERENCE TO ST_BoosterData;
  END_VAR
  VAR_OUTPUT
    bWanted : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_BoosterSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL;
    bRunWas : BOOL;
    tRunAt : TIME;
    bPressCall : BOOL; (* the pressure hysteresis *)
    stWLost : ST_ProtectionWork;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_BoosterSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.tDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eStartBy = E_BoostStart.Delay OR stS.eStartBy = E_BoostStart.Pressure) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (ABS(stS.fStartAt) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (ABS(stS.fStopAt) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (stS.eStartBy <> E_BoostStart.Pressure OR stS.fStartAt < stS.fStopAt) THEN
    SetWhy := E_UtError.LimitsBad;
  ELSIF NOT (stS.stLost.tDelay >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stLost.tRecover >= T#0s) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_BoosterSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;               // the station's request on and its pumps running
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  VAR
    tN : TIME;
    bPGood : BOOL;
    bTrip : BOOL;
    bReset : BOOL;
    eReqErr : E_UtError;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  eErrorId := E_UtError.BoosterLost;
  IF NOT bCalled AND (stWLost.bActive OR bWanted) THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    ipBooster.Request(bRun := FALSE, bHold := FALSE);
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  bReset := bResetWanted OR refData.bCmdReset;
  refData.bCmdReset := FALSE;
  IF bRunning AND NOT bRunWas THEN
    tRunAt := tN;
  END_IF;
  bRunWas := bRunning;
  bPGood := FALSE;
  IF ipPressure <> NULL THEN
    bPGood := ipPressure.bIsFitted AND ipPressure.bIsGood;
  END_IF;
  IF NOT bRunning THEN
    bPressCall := FALSE;
    bWanted := FALSE;
  ELSIF refData.set.eStartBy = E_BoostStart.Pressure AND bPGood THEN
    IF ipPressure.fActValue <= refData.set.fStartAt THEN
      bPressCall := TRUE;
    ELSIF ipPressure.fActValue >= refData.set.fStopAt THEN
      bPressCall := FALSE;
    END_IF;
    bWanted := bPressCall;
  ELSE
    bWanted := tN - tRunAt >= refData.set.tDelay;   (* Delay, or a pressure that cannot be trusted *)
  END_IF;
  bWanted := bWanted AND bPermit;
  eReqErr := ipBooster.Request(bRun := bWanted, bHold := FALSE);
  bTrip := F_Protect(tNow := tN, bCause := refData.set.bRequired AND bWanted AND NOT ipBooster.bIsRunning,
                     bResetReq := bReset, tRetryWindow := T#1h, stSet := refData.set.stLost,
                     stSts := refData.stLost, stWork := stWLost);
  IF stWLost.bTrip THEN
    Evaluate := E_PartAction.Trip;
  ELSIF stWLost.bSignal THEN
    Evaluate := E_PartAction.Stop;
  ELSIF stWLost.bWarn THEN
    Evaluate := E_PartAction.Warn;
  ELSIF stWLost.bBadSetting THEN
    eErrorId := E_UtError.BadSetting;
    Evaluate := E_PartAction.Warn;
  ELSE
    eErrorId := E_UtError.None;
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

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL OR ipBooster = NULL THEN
  bWanted := FALSE;
  bError := TRUE;
  IF ipOwner = NULL OR ipBooster = NULL THEN
    eErrorId := E_UtError.NoMotor;
  ELSE
    eErrorId := E_UtError.NoRecord;
  END_IF;
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
ELSIF SetOk(stS := refData.set) THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
IF SystemReset() THEN
  refData.bRefused := FALSE;
  refData.eRefusedWhy := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;
refData.bWanted := bWanted;
bError := stWLost.bTrip;
bWarning := NOT bError AND (stWLost.bWarn OR refData.bRefused);
IF stWLost.bTrip OR stWLost.bWarn THEN
  eErrorId := E_UtError.BoosterLost;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF bWanted THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK