(* FB_Mixer — a stirrer / agitator: when it runs, and the pump's hold for the pre-run.
The stirrer is ipStirrerMotor (I_Equipment: Request(bStirrerRunCommand), bIsReady, bIsAvailable, bIsRunning) or, without one, the
bStirrerReady / bStirrerRunning wires and the bStirrerRunCommand output.
bStirrerRunCommand is on (while the level is OK) for any of:
  pre-run    bPumpCalled came on: bStirrerRunCommand on, bHoldPumpStart holds the pump until the stirrer has run set.tPreRunTime (time
             already run counts); bPumpCalled going before the pump starts ends it.
  with pump  while bPumpRunning (set.bRunWithPump).
  post-run   set.tPostRunTime after the pump stops, counted only while the level is OK (held while it is low, like the
             cycle; it ends when the pump runs again).
  start now  while bStartNow.
  cycle      off for set.tOffTime, on for set.tOnTime, over and over (off first); any other run restarts the off time.
The pump is never held for a stirrer that cannot run: bHoldPumpStart drops at once with bStartNow, a low level or a
stirrer not available (not in Auto, tripped, held off; one in its restart wait can run, the pre-run waits for it),
and after set.tPreRunTime + 1 min if it still has not run (warning NoPreRun until bPumpCalled ends).
Level OK = bLevelAboveMinimum AND ipLevel: its value at / above set.fMinLevelToMix (back on at fMinLevelToMix + fMinLevelDeadband), or not in
its Low band; a bad level counts as low (never stir blind). Wanted but held by the level for stLowLevelFault's delay:
its protection (warning LevelLow by default).
Pins: bEnable, bCycleAllowed, bPumpCalled, bPumpRunning, bStartNow, bLevelAboveMinimum, ipLevel, ipStirrerMotor, bStirrerReady, bStirrerRunning,
refData -> bStirrerRunCommand, bHoldPumpStart, plus FB_Object's outputs. sts.eActivity says what it does. Settings are kept (a
retained last-good copy, a bad write put back). *)

FUNCTION_BLOCK FB_Mixer EXTENDS FB_Object
  VAR_INPUT
    bEnable : BOOL; (* FALSE: no run, the pump never held *)
    bCycleAllowed : BOOL := TRUE; (* the periodic cycle may run *)
    bPumpCalled : BOOL; (* the pump is called: pre-run first *)
    bPumpRunning : BOOL; (* the pump is running (with bRunWithPump) *)
    bStartNow : BOOL; (* run now, no pre-run, never hold the pump *)
    bLevelAboveMinimum : BOOL := TRUE; (* level at / above the minimum (AND-ed with ipLevel) *)
    ipLevel : I_Measurement; (* optional: the tank level *)
    ipStirrerMotor : I_Equipment; (* optional: the stirrer motor (else the wires below) *)
    bStirrerReady : BOOL := TRUE; (* only without ipStirrerMotor *)
    bStirrerRunning : BOOL; (* only without ipStirrerMotor *)
    refData : REFERENCE TO ST_MixerData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bStirrerRunCommand : BOOL; (* run the stirrer (also sent to ipStirrerMotor) *)
    bHoldPumpStart : BOOL; (* the pump must wait: pre-run *)
  END_VAR
  VAR RETAIN
    stKept : ST_MixerSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    stWLow : ST_ProtectionWork;
    tPrev : TIME;
    bLvlHigh : BOOL; (* the value part (with its deadband) *)
    bRunPrev : BOOL;
    tRunSince : TIME;
    bCallPrev : BOOL;
    tCallSince : TIME;
    bLet : BOOL; (* the pump is let go for this call *)
    bNoPre : BOOL; (* let go without a pre-run *)
    bPumpPrev : BOOL;
    bPost : BOOL;
    tPostEl : TIME; (* the post-run so far (counts only while the level is OK) *)
    bCycOn : BOOL;
    tCycEl : TIME;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    tStep : TIME;
    tPre : TIME;
    tPost : TIME;
    bCycOk : BOOL;
    bReady : BOOL;
    bAvail : BOOL; (* the stirrer can run: ready, or only in its restart wait *)
    bRunning : BOOL;
    bLvlOk : BOOL;
    tRanFor : TIME;
    bWantPre : BOOL;
    bOtherRun : BOOL;
    bWant : BOOL;
    bLowTrip : BOOL;
    eReqErr : E_UtError;
    bResetReq : BOOL; (* the system reset (a Manual low-level trip clears with it) *)
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_MixerSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF stS.bCycleOn AND (stS.tOnTime <= T#0s OR stS.tOffTime <= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tPreRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tPostRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (ABS(stS.fMinLevelToMix) <= REAL#3.4E38) THEN
    SetWhy := E_UtError.ValueBad;
  ELSIF NOT (stS.fMinLevelDeadband >= 0.0) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.fMinLevelDeadband <= REAL#3.4E38) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tRetryCountWindow >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_MixerSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bStirrerRunCommand := FALSE;
  bHoldPumpStart := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();
IF bFirstScan THEN
  tStep := T#0s;
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
ELSE
  tStep := tNow - tPrev;
  IF tStep < T#0s THEN
    tStep := T#0s;                (* a clock step back counts nothing *)
  END_IF;
END_IF;
tPrev := tNow;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
bResetReq := SystemReset();
IF bResetReq THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

tPre := T#0s;
IF refData.set.bPreRunOn AND refData.set.tPreRunTime > T#0s THEN
  tPre := refData.set.tPreRunTime;
END_IF;
tPost := T#0s;
IF refData.set.bPostRunOn AND refData.set.tPostRunTime > T#0s THEN
  tPost := refData.set.tPostRunTime;
END_IF;
bCycOk := refData.set.bCycleOn AND refData.set.tOnTime > T#0s AND refData.set.tOffTime > T#0s AND bCycleAllowed;

(* the stirrer and the level *)
IF ipStirrerMotor <> NULL THEN
  bReady := ipStirrerMotor.bIsReady;
  bAvail := ipStirrerMotor.bIsAvailable;
  bRunning := ipStirrerMotor.bIsRunning;
ELSE
  bReady := bStirrerReady;
  bAvail := bStirrerReady;
  bRunning := bStirrerRunning;
END_IF;
bLvlOk := bLevelAboveMinimum;
IF ipLevel <> NULL THEN
  IF NOT ipLevel.bIsFitted THEN
    ;
  ELSIF NOT ipLevel.bIsGood THEN
    bLvlOk := FALSE;              (* bad = low: never stir blind *)
  ELSIF ipLevel.bHasValue THEN
    IF ipLevel.fActValue >= refData.set.fMinLevelToMix + refData.set.fMinLevelDeadband THEN
      bLvlHigh := TRUE;
    ELSIF ipLevel.fActValue < refData.set.fMinLevelToMix THEN
      bLvlHigh := FALSE;
    END_IF;
    bLvlOk := bLvlOk AND bLvlHigh;
  ELSE
    bLvlOk := bLvlOk AND NOT ipLevel.Band(eBand := E_Band.Low);
  END_IF;
END_IF;

(* how long the stirrer has been running *)
IF bRunning AND NOT bRunPrev THEN
  tRunSince := tNow;
END_IF;
bRunPrev := bRunning;
IF bRunning THEN
  tRanFor := tNow - tRunSince;
ELSE
  tRanFor := T#0s;
END_IF;

(* pre-run: hold the pump until the stirrer has run tPre *)
IF bPumpCalled AND NOT bCallPrev THEN
  tCallSince := tNow;
  bLet := FALSE;
  bNoPre := FALSE;
END_IF;
bCallPrev := bPumpCalled;
bWantPre := FALSE;
IF NOT bEnable OR NOT bOk OR NOT bPumpCalled THEN
  bLet := FALSE;
  bNoPre := FALSE;
ELSIF NOT bLet THEN
  IF tPre = T#0s OR bStartNow OR NOT bLvlOk OR bPumpRunning OR tRanFor >= tPre THEN
    bLet := TRUE;                 (* no pre-run wanted, or it is done *)
  ELSIF NOT bAvail OR tNow - tCallSince >= tPre + T#1m THEN
    bLet := TRUE;                 (* never hold the pump for a stirrer that cannot run *)
    bNoPre := TRUE;
  ELSE
    bWantPre := TRUE;
  END_IF;
END_IF;
bHoldPumpStart := bWantPre;

(* post-run *)
IF bEnable AND bOk AND bPumpPrev AND NOT bPumpRunning AND tPost > T#0s THEN
  bPost := TRUE;
  tPostEl := T#0s;
END_IF;
bPumpPrev := bPumpRunning;
IF bPost AND bLvlOk THEN
  tPostEl := tPostEl + tStep;     (* a stirrer held by the level is not stirring: its post-run waits *)
END_IF;
IF bPost AND (NOT bEnable OR NOT bOk OR bPumpRunning OR tPostEl >= tPost) THEN
  bPost := FALSE;
END_IF;
bOtherRun := bEnable AND bOk
             AND (bWantPre OR (bPumpCalled AND bLet AND NOT bNoPre AND tPre > T#0s)
                  OR (refData.set.bRunWithPump AND bPumpRunning) OR bPost OR bStartNow);

(* the cycle: off first; held while the level is low; restarted by other runs *)
IF NOT bEnable OR NOT bOk OR NOT bCycOk OR bOtherRun THEN
  bCycOn := FALSE;
  tCycEl := T#0s;
ELSIF bLvlOk THEN
  tCycEl := tCycEl + tStep;
  IF bCycOn THEN
    IF tCycEl >= refData.set.tOnTime THEN
      bCycOn := FALSE;
      tCycEl := tCycEl - refData.set.tOnTime;
      IF tCycEl >= refData.set.tOffTime THEN tCycEl := T#0s; END_IF;
    END_IF;
  ELSIF tCycEl >= refData.set.tOffTime THEN
    bCycOn := TRUE;
    tCycEl := tCycEl - refData.set.tOffTime;
    IF tCycEl >= refData.set.tOnTime THEN tCycEl := T#0s; END_IF;
  END_IF;
END_IF;
bWant := bOtherRun OR (bEnable AND bOk AND bCycOn);
bStirrerRunCommand := bWant AND bLvlOk;
IF ipStirrerMotor <> NULL THEN
  eReqErr := ipStirrerMotor.Request(bRun := bStirrerRunCommand, bHoldOff := FALSE);
END_IF;
bLowTrip := F_Protect(tNow := tNow, bConditionPresent := bWant AND NOT bLvlOk, bResetRequest := bResetReq, tRetryCountWindow := refData.set.tRetryCountWindow,
                      stSettings := refData.set.stLowLevelFault, stStatus := refData.sts.stLowLevelFault, stWorking := stWLow);

(* time left *)
IF bWantPre THEN
  refData.det.tTimeLeft := tPre - tRanFor;
ELSIF bPost AND NOT (refData.set.bRunWithPump AND bPumpRunning) AND NOT bStartNow THEN
  refData.det.tTimeLeft := tPost - tPostEl;
ELSIF bEnable AND bOk AND bCycOk AND NOT bOtherRun THEN
  IF bCycOn THEN
    refData.det.tTimeLeft := refData.set.tOnTime - tCycEl;
  ELSE
    refData.det.tTimeLeft := refData.set.tOffTime - tCycEl;
  END_IF;
ELSE
  refData.det.tTimeLeft := T#0s;
END_IF;

(* what it does *)
IF NOT bEnable OR NOT bOk THEN
  refData.sts.eActivity := E_MixerActivity.Off;
ELSIF bWant AND NOT bLvlOk THEN
  refData.sts.eActivity := E_MixerActivity.LevelLow;
ELSIF bWant AND NOT bReady THEN
  refData.sts.eActivity := E_MixerActivity.NotReady;
ELSIF bWantPre THEN
  refData.sts.eActivity := E_MixerActivity.PreRun;
ELSIF refData.set.bRunWithPump AND bPumpRunning THEN
  refData.sts.eActivity := E_MixerActivity.WithPump;
ELSIF bStartNow THEN
  refData.sts.eActivity := E_MixerActivity.StartNow;
ELSIF bPost THEN
  refData.sts.eActivity := E_MixerActivity.PostRun;
ELSIF bOtherRun THEN
  refData.sts.eActivity := E_MixerActivity.WithPump;   (* the pre-run is done: running on for the pump's call *)
ELSIF bCycOk AND NOT bLvlOk THEN
  refData.sts.eActivity := E_MixerActivity.LevelLow;   (* the cycle clock is held by the level, not resting *)
ELSIF bCycOn THEN
  refData.sts.eActivity := E_MixerActivity.Timed;
ELSIF bCycOk THEN
  refData.sts.eActivity := E_MixerActivity.Rest;
ELSE
  refData.sts.eActivity := E_MixerActivity.Idle;
END_IF;
refData.sts.bStirrerRunCommand := bWant;
refData.sts.bLevelAboveMinimum := bLvlOk;

bError := NOT bOk OR bLowTrip;
bWarning := NOT bError AND (bNoPre OR stWLow.bWarning OR stWLow.bSettingBad OR refData.sts.bSettingRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF bLowTrip OR stWLow.bWarning THEN
  eErrorId := E_UtError.LevelLow;
ELSIF bNoPre THEN
  eErrorId := E_UtError.NoPreRun;
ELSIF stWLow.bSettingBad THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF NOT bEnable THEN
  eState := E_State.Off;
ELSIF bStirrerRunCommand THEN
  eState := E_State.Running;
ELSIF bWant THEN
  eState := E_State.Waiting;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK