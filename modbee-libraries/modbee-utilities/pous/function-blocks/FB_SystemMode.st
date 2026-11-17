(* FB_SystemMode — the plant's own mode: Off / Manual / Auto, the auto type (1..nAutoTypes), a manual run, the
power-on delay and the plant-wide reset (DESIGN-0.2.md section 5.5; src-v2 UT_SYSTEM_MODE).

Pins: bRun (the manual run request, held), bReset (the plant reset button: every block wired to this one
through ipSystem resets on its rising edge) -> bIsAuto, bIsManual, bNotOff, bAuto1..bAuto4 (Auto with that
type), bManualRun, bPowerUpHold (TRUE for set.tPowerOnDelay after power-up: automatic starts wait), plus
FB_Object's bError / bWarning / eErrorId / eState. refData: its record.
The mode and the auto type are the record's set.eMode / set.nAutoType (kept over a power cut; set.ePowerUp
Off forces Off at power-up); a bad write is put back and reported. Manual run: on while Manual and bRun is
held (or bCmdStart latched until bCmdStop), after the power-on delay, for at most set.tManualMaxRun. A Run held
at power-up, over a mode change or past the maximum must be released and given again before it runs.
Other blocks read it through I_SystemMode (their ipSystem pin).
The mode in use (set.eModeSource): Hmi = the record's choice; Switch = the selector bSwManual / bSwAuto (neither:
Off; both: Off and a SelectorFault warning); Remote = the selector's Off and Manual act here, its Auto hands over
to the record's choice. With set.ePowerUp Off a selector found out of Off at power-up is held Off until moved.
bForceOff holds the plant Off (the choice is kept). sts.eMode is the mode in use (src-v2 selector, ForceOff). *)

FUNCTION_BLOCK FB_SystemMode EXTENDS FB_Object IMPLEMENTS I_SystemMode
  VAR_INPUT
    bRun : BOOL; (* manual run request (held) *)
    bReset : BOOL R_EDGE; (* the plant reset *)
    bSwManual : BOOL; (* the selector in Manual (set.eModeSource Switch / Remote) *)
    bSwAuto : BOOL; (* the selector in Auto *)
    bForceOff : BOOL; (* holds the plant Off (the choice is kept) *)
    refData : REFERENCE TO ST_SystemModeData;
  END_VAR
  VAR_OUTPUT
    bIsAuto : BOOL;
    bIsManual : BOOL;
    bNotOff : BOOL;
    bAuto1 : BOOL;
    bAuto2 : BOOL;
    bAuto3 : BOOL;
    bAuto4 : BOOL;
    bManualRun : BOOL;
    bPowerUpHold : BOOL;
  END_VAR
  VAR RETAIN
    stKept : ST_SystemModeSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
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


PROPERTY PUBLIC bSystemAuto : BOOL
  GET
    bSystemAuto := bIsAuto;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bSystemOff : BOOL
  GET
    bSystemOff := NOT bNotOff;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bSystemHold : BOOL
  GET
    bSystemHold := bPowerUpHold;
  END_GET
END_PROPERTY
PROPERTY PUBLIC bSystemReset : BOOL
  GET
    bSystemReset := bResetNow;
  END_GET
END_PROPERTY

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_SystemModeSet;
  END_VAR
  SetOk := stS.nAutoTypes >= 1 AND stS.nAutoTypes <= 8 AND stS.nAutoType >= 1 AND stS.nAutoType <= stS.nAutoTypes
           AND stS.tManualMaxRun >= T#0s AND stS.tPowerOnDelay >= T#0s
           AND (stS.eMode = E_SysMode.Off OR stS.eMode = E_SysMode.Manual OR stS.eMode = E_SysMode.Auto)
           AND (stS.eModeSource = E_ModeSource.Hmi OR stS.eModeSource = E_ModeSource.Switch
                OR stS.eModeSource = E_ModeSource.Remote);
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
  IF refData.set.ePowerUp = E_PowerUp.Off THEN
    refData.set.eMode := E_SysMode.Off;
  END_IF;
  eModeWas := refData.set.eMode;
END_IF;
bOk := SetOk(stS := refData.set);
IF bOk THEN
  stKept := refData.set;
ELSIF SetOk(stS := stKept) THEN
  refData.set := stKept;          // a bad write is put back
  refData.sts.bRefused := TRUE;
  bOk := TRUE;
END_IF;

(* the plant reset *)
bResetNow := bReset OR refData.bCmdReset;
IF refData.bCmdReset THEN
  refData.bCmdReset := FALSE;
  refData.sts.bRefused := FALSE;
END_IF;

(* the mode in use: the HMI choice, the selector, or the selector's Auto handing over to the HMI; forced Off *)
bSelFault := bSwManual AND bSwAuto;
IF bSwManual AND NOT bSelFault THEN
  eSel := E_SysMode.Manual;
ELSIF bSwAuto AND NOT bSelFault THEN
  eSel := E_SysMode.Auto;
ELSE
  eSel := E_SysMode.Off;
END_IF;
IF bFirstScan THEN
  bSelHeld := refData.set.ePowerUp = E_PowerUp.Off AND eSel <> E_SysMode.Off;   // moved before it counts
  eSelWas := eSel;
ELSIF eSel <> eSelWas THEN
  bSelHeld := FALSE;
  eSelWas := eSel;
END_IF;
CASE refData.set.eModeSource OF
  E_ModeSource.Switch:
    eNow := eSel;
  E_ModeSource.Remote:
    IF eSel = E_SysMode.Auto THEN eNow := refData.set.eMode; ELSE eNow := eSel; END_IF;
ELSE
  eNow := refData.set.eMode;
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
  refData.det.tPowerUpLeft := refData.set.tPowerOnDelay - (tNow - tStartAt);
ELSE
  refData.det.tPowerUpLeft := T#0s;
END_IF;

(* the manual run *)
IF refData.bCmdStart THEN
  IF eNow = E_SysMode.Manual THEN bLatch := TRUE; END_IF;
  refData.bCmdStart := FALSE;
END_IF;
IF refData.bCmdStop THEN
  bLatch := FALSE;
  refData.bCmdStop := FALSE;
END_IF;
IF NOT bRun THEN
  bBlocked := FALSE;
  IF NOT bLatch THEN bMaxHit := FALSE; END_IF;
END_IF;
bManualRun := eNow = E_SysMode.Manual AND bOk AND NOT bPowerUpHold AND NOT bMaxHit
              AND ((bRun AND NOT bBlocked) OR bLatch);
IF bManualRun AND NOT bRunPrev THEN
  tRunAt := tNow;
END_IF;
IF bManualRun AND refData.set.tManualMaxRun > T#0s AND tNow - tRunAt >= refData.set.tManualMaxRun THEN
  bManualRun := FALSE;
  bMaxHit := TRUE;                // the request must be released and given again
  bLatch := FALSE;
  refData.sts.eStopReason := E_StopReason.MaxRun;
ELSIF bRunPrev AND NOT bManualRun AND NOT bMaxHit THEN
  IF eNow <> E_SysMode.Manual THEN
    refData.sts.eStopReason := E_StopReason.Off;
  ELSE
    refData.sts.eStopReason := E_StopReason.Request;
  END_IF;
END_IF;
IF bManualRun THEN
  refData.det.tRunTime := tNow - tRunAt;
  IF refData.set.tManualMaxRun > T#0s THEN
    refData.det.tTimeLeft := refData.set.tManualMaxRun - (tNow - tRunAt);
  ELSE
    refData.det.tTimeLeft := T#0s;
  END_IF;
ELSE
  refData.det.tTimeLeft := T#0s;
END_IF;
bRunPrev := bManualRun;

(* outputs *)
IF bOk THEN nType := refData.set.nAutoType; ELSE nType := 0; END_IF;
bIsAuto := bOk AND eNow = E_SysMode.Auto;
bIsManual := bOk AND eNow = E_SysMode.Manual;
bNotOff := bIsAuto OR bIsManual;
bAuto1 := bIsAuto AND nType = 1;
bAuto2 := bIsAuto AND nType = 2;
bAuto3 := bIsAuto AND nType = 3;
bAuto4 := bIsAuto AND nType = 4;
bError := NOT bOk;
bWarning := bMaxHit OR refData.sts.bRefused OR (bSelFault AND refData.set.eModeSource <> E_ModeSource.Hmi);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
  eState := E_State.Fault;
ELSIF bSelFault AND refData.set.eModeSource <> E_ModeSource.Hmi THEN
  eErrorId := E_UtError.SelectorFault;
ELSIF refData.sts.bRefused THEN
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
refData.sts.eMode := eNow;
refData.sts.nAutoType := nType;
refData.sts.bManualRun := bManualRun;
refData.sts.bPowerUpHold := bPowerUpHold;
refData.sts.bSelectorFault := bSelFault;
refData.sts.bForcedOff := bForceOff;
bFirstScan := FALSE;

END_FUNCTION_BLOCK