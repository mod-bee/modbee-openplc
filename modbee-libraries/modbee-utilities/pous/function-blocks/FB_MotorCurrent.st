(* FB_MotorCurrent — a motor's current from a CT, as a part of its motor. Off until set.fFullLoad (the motor's
full-load current, in the CT's unit) is set.
- fPercent: the current as % of full load. bProvesRun: at or above set.fRunPercent; wire it to the motor's
  bFeedback when the CT, not an auxiliary contact, proves the motor runs.
- stHigh (overload by current, default Off) and stLow (dry run / broken belt, default Off): % of full load with
  a deadband, checked once the motor runs (bIsRunning) and set.tStartMask has passed (sts.tMaskLeft: the time
  left of the mask).
- stStartTooLong (a locked rotor, default Off): the current still at or above its % while the motor's run
  command is on, for its delay.
- stBad (default a warning): the current is not good while monitoring is wanted; high / low / start checks
  then wait (they never act on a bad reading).
Pins: ipCurrent (the CT, I_Measurement), ipOwner (the motor, I_Equipment, required), refData -> fPercent,
bProvesRun, plus FB_Object's outputs. It adds itself to its motor on its first call; the motor evaluates it
in its own cycle and stops on a trip. A check that is acting when this rung stops being called raises PartLost.
Settings are kept (a retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_MotorCurrent EXTENDS FB_Object IMPLEMENTS I_Part
  VAR_INPUT
    ipCurrent : I_Measurement; (* the CT *)
    ipOwner : I_Equipment; (* the motor (required) *)
    refData : REFERENCE TO ST_MotorCurrentData;
  END_VAR
  VAR_OUTPUT
    fPercent : REAL; (* of full load (0 while not monitoring or not good) *)
    bProvesRun : BOOL; (* at or above set.fRunPercent: wire to the motor's bFeedback for run by current *)
  END_VAR
  VAR RETAIN
    stKept : ST_MotorCurrentSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    ipNext : I_Part;
    bAdded : BOOL;
    bCalled : BOOL; (* the rung ran since the owner's last Evaluate *)
    bGoodNow : BOOL; (* this scan's reading is good *)
    bMon : BOOL; (* monitoring is set up *)
    bHighNow : BOOL; (* past the level, with its deadband *)
    bLowNow : BOOL;
    bRunWas : BOOL;
    tRunSince : TIME;
    stWHigh : ST_ProtectionWork;
    stWLow : ST_ProtectionWork;
    stWStart : ST_ProtectionWork;
    stWBad : ST_ProtectionWork;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    fA : REAL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_MotorCurrentSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.fFullLoad >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fFullLoad <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.fRunPercent >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fRunPercent <= 1000.0) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tStartMask >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.stHigh.fPercent >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stHigh.fDeadband >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stLow.fPercent >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stLow.fDeadband >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  ELSIF NOT (stS.stStartTooLong.fPercent >= 0.0) THEN
    SetWhy := E_UtError.ProtectionBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MotorCurrentSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

METHOD PUBLIC Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;
    bResetWanted : BOOL;
    bMasked : BOOL;
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;
  END_VAR
  VAR
    bReset : BOOL;
    bAnyLevel : BOOL;
    bRunOk : BOOL;
    tN : TIME;
    bTrip : BOOL;
  END_VAR
  IF NOT __ISVALIDREF(refData) THEN
    eErrorId := E_UtError.NoRecord;
    Evaluate := E_PartAction.Warn;
    RETURN;
  END_IF;
  IF NOT bCalled AND (stWHigh.bActive OR stWLow.bActive OR stWStart.bActive OR stWBad.bActive) THEN
    eErrorId := E_UtError.PartLost;           // its rung stopped while it was acting: never a silent clear
    Evaluate := E_PartAction.Trip;
    RETURN;
  END_IF;
  bCalled := FALSE;
  tN := TIME();
  bReset := bResetWanted OR refData.bCmdReset;
  refData.bCmdReset := FALSE;
  (* how long it has run (the motor's own running, confirmed) *)
  bRunOk := ipOwner.bIsRunning;
  IF bRunOk AND NOT bRunWas THEN
    tRunSince := tN;
  END_IF;
  bRunWas := bRunOk;
  IF bRunOk AND tN - tRunSince < refData.set.tStartMask THEN
    refData.sts.tMaskLeft := refData.set.tStartMask - (tN - tRunSince);
  ELSE
    refData.sts.tMaskLeft := T#0s;
  END_IF;
  bAnyLevel := refData.set.stHigh.eResponse <> E_Response.Off OR refData.set.stLow.eResponse <> E_Response.Off
               OR refData.set.stStartTooLong.eResponse <> E_Response.Off;
  bTrip := F_Protect(tNow := tN, bCause := bMon AND bAnyLevel AND NOT bGoodNow, bResetReq := bReset,
                     tRetryWindow := T#1h, stSet := refData.set.stBad, stSts := refData.sts.stBad, stWork := stWBad);
  bTrip := F_Protect(tNow := tN, bCause := bMon AND bGoodNow AND bRunOk AND tN - tRunSince >= refData.set.tStartMask
                                           AND bHighNow AND NOT bMasked,
                     bResetReq := bReset, tRetryWindow := T#1h, stSet := refData.set.stHigh,
                     stSts := refData.sts.stHigh, stWork := stWHigh);
  bTrip := F_Protect(tNow := tN, bCause := bMon AND bGoodNow AND bRunOk AND tN - tRunSince >= refData.set.tStartMask
                                           AND bLowNow AND NOT bMasked,
                     bResetReq := bReset, tRetryWindow := T#1h, stSet := refData.set.stLow,
                     stSts := refData.sts.stLow, stWork := stWLow);
  bTrip := F_Protect(tNow := tN, bCause := bMon AND bGoodNow AND bRunning
                                           AND fPercent >= refData.set.stStartTooLong.fPercent,
                     bResetReq := bReset, tRetryWindow := T#1h, stSet := refData.set.stStartTooLong,
                     stSts := refData.sts.stStartTooLong, stWork := stWStart);
  IF stWStart.bTrip THEN
    eErrorId := E_UtError.StartTooLong;
    Evaluate := E_PartAction.Trip;
  ELSIF stWHigh.bTrip THEN
    eErrorId := E_UtError.CurrentHigh;
    Evaluate := E_PartAction.Trip;
  ELSIF stWLow.bTrip THEN
    eErrorId := E_UtError.CurrentLow;
    Evaluate := E_PartAction.Trip;
  ELSIF stWBad.bTrip THEN
    eErrorId := E_UtError.CurrentBad;
    Evaluate := E_PartAction.Trip;
  ELSIF stWStart.bSignal OR stWHigh.bSignal OR stWLow.bSignal OR stWBad.bSignal THEN
    eErrorId := E_UtError.None;
    Evaluate := E_PartAction.Stop;
  ELSIF stWStart.bWarn OR stWHigh.bWarn OR stWLow.bWarn OR stWBad.bWarn THEN
    IF stWStart.bWarn THEN eErrorId := E_UtError.StartTooLong;
    ELSIF stWHigh.bWarn THEN eErrorId := E_UtError.CurrentHigh;
    ELSIF stWLow.bWarn THEN eErrorId := E_UtError.CurrentLow;
    ELSE eErrorId := E_UtError.CurrentBad;
    END_IF;
    Evaluate := E_PartAction.Warn;
  ELSIF stWStart.bBadSetting OR stWHigh.bBadSetting OR stWLow.bBadSetting OR stWBad.bBadSetting THEN
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

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  fPercent := 0.0;
  bProvesRun := FALSE;
  bError := TRUE;
  IF ipOwner = NULL THEN
    eErrorId := E_UtError.NoMotor;            // a part without an owner protects nothing
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
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eRefusedWhy := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bRefused := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bRefused := FALSE;
  refData.sts.eRefusedWhy := E_UtError.None;
END_IF;
IF NOT bAdded THEN
  ipOwner.AddPart(ipPart := THIS^);
  bAdded := TRUE;
END_IF;
bCalled := TRUE;

(* the reading *)
fA := 0.0;
bGoodNow := FALSE;
IF ipCurrent <> NULL THEN
  IF ipCurrent.bIsFitted THEN
    fA := ipCurrent.fActValue;
    bGoodNow := ipCurrent.bIsGood AND ABS(fA) <= REAL#3.4E38;
  END_IF;
END_IF;
bMon := ipCurrent <> NULL AND refData.set.fFullLoad > 0.0 AND refData.set.fFullLoad <= REAL#3.4E38;
IF bMon AND bGoodNow THEN
  fPercent := fA / refData.set.fFullLoad * 100.0;
ELSE
  fPercent := 0.0;
END_IF;
bProvesRun := bMon AND bGoodNow AND fPercent >= refData.set.fRunPercent;
(* the levels, with their deadbands *)
IF fPercent >= refData.set.stHigh.fPercent THEN
  bHighNow := TRUE;
ELSIF fPercent < refData.set.stHigh.fPercent - refData.set.stHigh.fDeadband THEN
  bHighNow := FALSE;
END_IF;
IF fPercent <= refData.set.stLow.fPercent THEN
  bLowNow := TRUE;
ELSIF fPercent > refData.set.stLow.fPercent + refData.set.stLow.fDeadband THEN
  bLowNow := FALSE;
END_IF;
refData.sts.fCurrent := fA;
refData.sts.fPercent := fPercent;
refData.sts.bProvesRun := bProvesRun;

bError := stWHigh.bTrip OR stWLow.bTrip OR stWStart.bTrip OR stWBad.bTrip;
bWarning := NOT bError AND (stWHigh.bWarn OR stWLow.bWarn OR stWStart.bWarn OR stWBad.bWarn OR refData.sts.bRefused);
IF stWStart.bTrip OR stWStart.bWarn THEN
  eErrorId := E_UtError.StartTooLong;
ELSIF stWHigh.bTrip OR stWHigh.bWarn THEN
  eErrorId := E_UtError.CurrentHigh;
ELSIF stWLow.bTrip OR stWLow.bWarn THEN
  eErrorId := E_UtError.CurrentLow;
ELSIF stWBad.bTrip OR stWBad.bWarn THEN
  eErrorId := E_UtError.CurrentBad;
ELSIF refData.sts.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bMon THEN
  eState := E_State.Off;
ELSIF bProvesRun THEN
  eState := E_State.Running;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK