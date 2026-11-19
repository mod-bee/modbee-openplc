(* FB_SystemMode — the plant's own mode: Off / Manual / Auto, the auto type (1..nAutoModesOffered), a manual run, the
power-on delay and the plant-wide reset.

Pins: bManualRunRequest (the manual run request, held), bPlantReset (the plant reset button: every block wired to this one
through ipSystem resets on its rising edge) -> bIsAuto, bIsManual, bNotOff, bAutoMode1..bAutoMode4 (Auto with that
type), bManualRun, bPowerUpHold (TRUE for set.tPowerOnDelay after power-up: automatic starts wait), plus
FB_Object's bError / bWarning / eErrorId / eState. refData: its record.
The mode and the auto type are the record's set.eSystemMode / set.nAutoModeChosen (kept over a power cut; set.eModeAtPowerUp
Off forces Off at power-up; the record's command nCmdSystemMode 0 Off / 1 Manual / 2 Auto writes set.eSystemMode once, for SMS
and SCADA); a bad write is put back and reported. Manual run: on while Manual and bManualRunRequest is
held (or bCmdStartManualRun latched until bCmdStopManualRun), after the power-on delay, for at most set.tMaxManualRunTime. A Run held
at power-up, over a mode change or past the maximum must be released and given again before it runs.
Other blocks read it through I_SystemMode (their ipSystem pin).
The mode in use (set.eModeSource): Hmi = the record's choice; Switch = the selector bSelectorManual / bSelectorAuto (neither:
Off; both: Off and a SelectorFault warning); Remote = the selector's Off and Manual act here, its Auto hands over
to the record's choice. With set.eModeAtPowerUp Off a selector found out of Off at power-up is held Off until moved.
bForceOff holds the plant Off (the choice is kept). sts.eSystemModeInUse is the mode in use.
set.bManualOffered FALSE: the plant is Off / Auto only (Off / On): Manual is refused as a bad write (set.eSystemMode,
nCmdSystemMode 1), a selector's Manual contact acts as Off, and there is no manual run.
bModeChanged is TRUE for one scan when the mode changes. *)

FUNCTION_BLOCK FB_SystemMode EXTENDS FB_Object IMPLEMENTS I_SystemMode
  VAR_INPUT
    bManualRunRequest : BOOL; (* manual run request (held) *)
    bPlantReset : BOOL R_EDGE; (* the plant reset *)
    bSelectorManual : BOOL; (* the selector in Manual (set.eModeSource Switch / Remote) *)
    bSelectorAuto : BOOL; (* the selector in Auto *)
    bForceOff : BOOL; (* holds the plant Off (the choice is kept) *)
    refData : REFERENCE TO ST_SystemModeData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bIsAuto : BOOL; (* the plant is in Auto *)
    bIsManual : BOOL; (* the plant is in Manual *)
    bNotOff : BOOL; (* the plant is not Off *)
    bAutoMode1 : BOOL; (* Auto with type 1 *)
    bAutoMode2 : BOOL; (* Auto with type 2 *)
    bAutoMode3 : BOOL; (* Auto with type 3 *)
    bAutoMode4 : BOOL; (* Auto with type 4 *)
    bManualRun : BOOL; (* the manual run is on *)
    bModeChanged : BOOL; (* one scan: the mode changed *)
    bPowerUpHold : BOOL; (* TRUE for tPowerOnDelay after power-up: automatic starts wait *)
  END_VAR
  VAR RETAIN
    stKept : ST_SystemModeSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    tStartAt : TIME;
    bBlocked : BOOL; (* a held Run must be released first *)
    bLatch : BOOL;
    bMaxHit : BOOL;
    bRunPrev : BOOL;
    tRunAt : TIME;
    eModeWas : E_SysMode;
    bResetNow : BOOL;
    eNow : E_SysMode; (* the mode in use *)
    eSelWas : E_SysMode;
    bSelHeld : BOOL; (* power-up Off: the selector must be moved first *)
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    nType : INT;
    eSel : E_SysMode;
    bSelFault : BOOL;
  END_VAR


PROPERTY PUBLIC bSystemAuto : BOOL    // the plant is in Auto
  GET
    bSystemAuto := bIsAuto;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bSystemOff : BOOL    // the plant is Off
  GET
    bSystemOff := NOT bNotOff;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bSystemHold : BOOL    // the power-up hold is on: automatic starts wait
  GET
    bSystemHold := bPowerUpHold;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bSystemReset : BOOL    // the plant reset this scan
  GET
    bSystemReset := bResetNow;
  END_GET
END_PROPERTY

METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_SystemModeSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.nAutoModesOffered >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nAutoModesOffered <= 8) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.nAutoModeChosen >= 1) THEN
    SetWhy := E_UtError.BelowMin;
  ELSIF NOT (stS.nAutoModeChosen <= stS.nAutoModesOffered) THEN
    SetWhy := E_UtError.AboveMax;
  ELSIF NOT (stS.tMaxManualRunTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.tPowerOnDelay >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  ELSIF NOT (stS.eSystemMode = E_SysMode.Off OR stS.eSystemMode = E_SysMode.Manual OR stS.eSystemMode = E_SysMode.Auto) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF stS.eSystemMode = E_SysMode.Manual AND NOT stS.bManualOffered THEN
    SetWhy := E_UtError.ChoiceBad;  // Manual is not offered
  ELSIF NOT (stS.eModeSource = E_ModeSource.Hmi OR stS.eModeSource = E_ModeSource.Switch
             OR stS.eModeSource = E_ModeSource.Remote) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SystemModeSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

IF NOT __ISVALIDREF(refData) THEN
  bIsAuto := FALSE;
  bIsManual := FALSE;
  bNotOff := FALSE;
  bManualRun := FALSE;
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
tNow := TIME();

(* kept settings, power-up *)
IF bFirstScan THEN
  tStartAt := tNow;
  bBlocked := TRUE;               // a Run held at power-up must be released first
  IF nKeptLayout = cLayout THEN
    refData.set := stKept;
  ELSE
    stKept := refData.set;
    nKeptLayout := cLayout;
  END_IF;
  IF refData.set.eModeAtPowerUp = E_PowerUp.Off THEN
    refData.set.eSystemMode := E_SysMode.Off;
  END_IF;
  eModeWas := refData.set.eSystemMode;
END_IF;
(* the mode command (SMS, SCADA): the record's choice, once *)
IF refData.nCmdSystemMode >= 0 THEN
  CASE refData.nCmdSystemMode OF
    0: refData.set.eSystemMode := E_SysMode.Off;
    1: refData.set.eSystemMode := E_SysMode.Manual;
    2: refData.set.eSystemMode := E_SysMode.Auto;
  ELSE
    refData.sts.bSettingRefused := TRUE;
    refData.sts.eSettingRefusedErrorId := E_UtError.ChoiceBad;
  END_CASE;
  refData.nCmdSystemMode := -1;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;          // a bad write is put back
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;

(* the plant reset *)
bResetNow := bPlantReset OR refData.bCmdResetFaults;
IF refData.bCmdResetFaults THEN
  refData.bCmdResetFaults := FALSE;
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the mode in use: the HMI choice, the selector, or the selector's Auto handing over to the HMI; forced Off *)
bSelFault := bSelectorManual AND bSelectorAuto;
IF bSelectorManual AND NOT bSelFault AND refData.set.bManualOffered THEN
  eSel := E_SysMode.Manual;
ELSIF bSelectorAuto AND NOT bSelFault THEN
  eSel := E_SysMode.Auto;
ELSE
  eSel := E_SysMode.Off;
END_IF;
IF bFirstScan THEN
  bSelHeld := refData.set.eModeAtPowerUp = E_PowerUp.Off AND eSel <> E_SysMode.Off;   // moved before it counts
  eSelWas := eSel;
ELSIF eSel <> eSelWas THEN
  bSelHeld := FALSE;
  eSelWas := eSel;
END_IF;
CASE refData.set.eModeSource OF
  E_ModeSource.Switch:
    eNow := eSel;
  E_ModeSource.Remote:
    IF eSel = E_SysMode.Auto THEN eNow := refData.set.eSystemMode; ELSE eNow := eSel; END_IF;
ELSE
  eNow := refData.set.eSystemMode;
END_CASE;
IF refData.set.eModeSource <> E_ModeSource.Hmi AND bSelHeld THEN
  eNow := E_SysMode.Off;
END_IF;
IF bForceOff THEN
  eNow := E_SysMode.Off;          (* the choice is kept *)
END_IF;

IF eNow <> eModeWas THEN
  bBlocked := TRUE;               // a mode change: a held Run must be released
  bLatch := FALSE;
  eModeWas := eNow;
END_IF;

(* the power-on delay *)
bPowerUpHold := tNow - tStartAt < refData.set.tPowerOnDelay;
IF bPowerUpHold THEN
  refData.det.tPowerUpHoldLeft := refData.set.tPowerOnDelay - (tNow - tStartAt);
ELSE
  refData.det.tPowerUpHoldLeft := T#0s;
END_IF;

(* the manual run *)
IF refData.bCmdStartManualRun THEN
  IF eNow = E_SysMode.Manual THEN bLatch := TRUE; END_IF;
  refData.bCmdStartManualRun := FALSE;
END_IF;
IF refData.bCmdStopManualRun THEN
  bLatch := FALSE;
  refData.bCmdStopManualRun := FALSE;
END_IF;
IF NOT bManualRunRequest THEN
  bBlocked := FALSE;
  IF NOT bLatch THEN bMaxHit := FALSE; END_IF;
END_IF;
bManualRun := eNow = E_SysMode.Manual AND bOk AND NOT bPowerUpHold AND NOT bMaxHit
              AND ((bManualRunRequest AND NOT bBlocked) OR bLatch);
IF bManualRun AND NOT bRunPrev THEN
  tRunAt := tNow;
END_IF;
IF bManualRun AND refData.set.tMaxManualRunTime > T#0s AND tNow - tRunAt >= refData.set.tMaxManualRunTime THEN
  bManualRun := FALSE;
  bMaxHit := TRUE;                // the request must be released and given again
  bLatch := FALSE;
  refData.sts.eManualRunStopReason := E_StopReason.MaxRun;
ELSIF bRunPrev AND NOT bManualRun AND NOT bMaxHit THEN
  IF eNow <> E_SysMode.Manual THEN
    refData.sts.eManualRunStopReason := E_StopReason.Off;
  ELSE
    refData.sts.eManualRunStopReason := E_StopReason.Request;
  END_IF;
END_IF;
IF bManualRun THEN
  refData.det.tManualRunTime := tNow - tRunAt;
  IF refData.set.tMaxManualRunTime > T#0s THEN
    refData.det.tTimeLeft := refData.set.tMaxManualRunTime - (tNow - tRunAt);
  ELSE
    refData.det.tTimeLeft := T#0s;
  END_IF;
ELSE
  refData.det.tTimeLeft := T#0s;
END_IF;
bRunPrev := bManualRun;

(* outputs *)
IF bOk THEN nType := refData.set.nAutoModeChosen; ELSE nType := 0; END_IF;
bIsAuto := bOk AND eNow = E_SysMode.Auto;
bIsManual := bOk AND eNow = E_SysMode.Manual;
bNotOff := bIsAuto OR bIsManual;
bAutoMode1 := bIsAuto AND nType = 1;
bAutoMode2 := bIsAuto AND nType = 2;
bAutoMode3 := bIsAuto AND nType = 3;
bAutoMode4 := bIsAuto AND nType = 4;
bError := NOT bOk;
bWarning := bMaxHit OR refData.sts.bSettingRefused OR (bSelFault AND refData.set.eModeSource <> E_ModeSource.Hmi);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
  eState := E_State.Fault;
ELSIF bSelFault AND refData.set.eModeSource <> E_ModeSource.Hmi THEN
  eErrorId := E_UtError.SelectorFault;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bOk THEN
  IF NOT bNotOff THEN
    eState := E_State.Off;
  ELSIF bPowerUpHold THEN
    eState := E_State.Waiting;
  ELSIF bIsAuto OR bManualRun THEN
    eState := E_State.Running;
  ELSE
    eState := E_State.Idle;
  END_IF;
END_IF;
bModeChanged := NOT bFirstScan AND eNow <> refData.sts.eSystemModeInUse;
refData.sts.eSystemModeInUse := eNow;
refData.sts.nAutoModeInUse := nType;
refData.sts.bManualRun := bManualRun;
refData.sts.bPowerUpHold := bPowerUpHold;
refData.sts.bSelectorFault := bSelFault;
refData.sts.bForcedOffByInput := bForceOff;
bFirstScan := FALSE;

END_FUNCTION_BLOCK