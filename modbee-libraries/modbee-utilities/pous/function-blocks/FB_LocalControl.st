(* FB_LocalControl — the panel-door controls of one piece of equipment: an Off / Hand / Auto selector and the
push-buttons of a motor or a valve.

The mode (set.eModeSource):
  Hmi     the selector is not used: the owner's own mode (its record, the HMI)
  Switch  the selector sets the owner's mode: bSelectorHand = Hand, bSelectorAuto = Auto, neither = Off (the panel cannot
          change it while it is fitted)
  Remote  the selector's Off and Hand act here; its Auto hands the mode to the operator's choice set.eHmiModeInAuto
          (written by the block from the owner's mode while the selector is in Auto, so the HMI's choice comes
          back when the selector returns to Auto)
Both selector contacts made: Off, a warning (SelectorFault). With set.eSelectorAtPowerUp Off a selector found out of Off
at power-up is held Off until it is moved (Remote: a selector found in Hand; the operator's choice goes to Off).
The buttons (rising edges; bStopButton is TRUE = pressed, an NC button inverted with NOT at the pin; a stop wins):
  bStartButton          Hand start (a valve: open), as the record's bCmdStart
  bStopButton           stops the owner in Hand, and in Auto too with set.bStopButtonInAuto (off until the owner's request
                  drops)
  bOpenButton / bCloseButton  a valve in Hand: open / close (bOpenButton as bStartButton; bCloseButton acts in Hand only)
  bHaltButton           a motorised valve in Hand: stop where it is
  bPosition1Button..bPosition3Button    a three-position valve in Hand: go to that position
  bLowSpeedButton / bHighSpeedButton    a two-speed motor in Hand: that speed (and start)
  bReverseButton            a reversing motor in Hand: reverse (and start); bStartButton starts in the last direction
bHaltButton .. bReverseButton go to the owner's I_LocalChoice (FB_ValveMotor, FB_Valve3Pos, FB_Motor2Speed, FB_MotorRev); an
owner without that choice ignores the button. Only the owner starts anything.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back.
bModeChanged / bChangedToOff are TRUE for one scan when the owner's mode changes (to Off). *)

FUNCTION_BLOCK FB_LocalControl EXTENDS FB_Object
  VAR_INPUT
    bSelectorHand : BOOL := FALSE; (* the selector's Hand contact (both FALSE = Off) *)
    bSelectorAuto : BOOL; (* the selector's Auto contact *)
    bStartButton : BOOL R_EDGE; (* rising edge: start (Hand) *)
    bStopButton : BOOL; (* the stop button (held stops) *)
    bOpenButton : BOOL R_EDGE; (* a valve: open (Hand) *)
    bCloseButton : BOOL R_EDGE; (* a valve: close (Hand) *)
    bHaltButton : BOOL R_EDGE; (* a motorised valve: stop where it is (Hand) *)
    bPosition1Button : BOOL R_EDGE; (* a three-position valve: go to 1 (Hand) *)
    bPosition2Button : BOOL R_EDGE; (* a three-position valve: go to 2 (Hand), rising edge *)
    bPosition3Button : BOOL R_EDGE; (* a three-position valve: go to 3 (Hand), rising edge *)
    bLowSpeedButton : BOOL R_EDGE; (* a two-speed motor: low (Hand) *)
    bHighSpeedButton : BOOL R_EDGE; (* a two-speed motor: high (Hand) *)
    bReverseButton : BOOL R_EDGE; (* a reversing motor: reverse (Hand) *)
    ipEquipment : I_Equipment; (* the equipment it drives (a motor, pump, valve or FB_Group) *)
    refData : REFERENCE TO ST_LocalControlData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bModeChanged : BOOL; (* one scan: the owner's mode changed *)
    bChangedToOff : BOOL; (* one scan: ... to Off *)
  END_VAR
  VAR RETAIN
    stKept : ST_LocalControlSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
    eModeWas : E_Mode;
    bStopPrev : BOOL;
    eSelWas : E_Mode;
    bHeld : BOOL;
    bRemoteWas : BOOL;
    ipChoice : I_LocalChoice;
  END_VAR
  VAR_TEMP
    bOk : BOOL;
    eSel : E_Mode;
    eUse : E_Mode;
    bUseSel : BOOL;
    bRemoteNow : BOOL;
    eChoice : E_LocalChoice;
    bHas : BOOL;
  END_VAR


METHOD PRIVATE SetWhy : E_UtError
  VAR_INPUT
    stS : REFERENCE TO ST_LocalControlSet;
  END_VAR
  SetWhy := E_UtError.None;
  IF NOT (stS.eModeSource = E_ModeSource.Hmi OR stS.eModeSource = E_ModeSource.Switch
          OR stS.eModeSource = E_ModeSource.Remote) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eSelectorAtPowerUp = E_PowerUp.Last OR stS.eSelectorAtPowerUp = E_PowerUp.Off) THEN
    SetWhy := E_UtError.ChoiceBad;
  ELSIF NOT (stS.eHmiModeInAuto = E_Mode.Off OR stS.eHmiModeInAuto = E_Mode.Hand OR stS.eHmiModeInAuto = E_Mode.Auto) THEN
    SetWhy := E_UtError.ChoiceBad;
  END_IF;
END_METHOD

METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_LocalControlSet;
  END_VAR
  SetOk := SetWhy(stS := stS) = E_UtError.None;
END_METHOD

(* the owner to this mode *)
METHOD PRIVATE ModeTo : BOOL
  VAR_INPUT
    eM : E_Mode;
  END_VAR
  CASE eM OF
    E_Mode.Hand: ipEquipment.Command(eCommand := E_EquipCmd.ModeHand);
    E_Mode.Auto: ipEquipment.Command(eCommand := E_EquipCmd.ModeAuto);
  ELSE
    ipEquipment.Command(eCommand := E_EquipCmd.ModeOff);
  END_CASE;
  ModeTo := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipEquipment = NULL THEN
  bError := TRUE;
  IF ipEquipment = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
  eState := E_State.Fault;
  RETURN;
END_IF;

(* kept settings *)
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
  refData.sts.eSettingRefusedErrorId := SetWhy(stS := refData.set);
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

(* the selector *)
refData.sts.bSelectorFault := bSelectorHand AND bSelectorAuto;
IF refData.sts.bSelectorFault OR (NOT bSelectorHand AND NOT bSelectorAuto) THEN
  eSel := E_Mode.Off;
ELSIF bSelectorHand THEN
  eSel := E_Mode.Hand;
ELSE
  eSel := E_Mode.Auto;
END_IF;
IF bFirstScan THEN
  (* power-up Off: a selector found out of Off waits to be moved; Remote: the operator's choice goes Off *)
  bHeld := refData.set.eSelectorAtPowerUp = E_PowerUp.Off AND eSel <> E_Mode.Off;
  IF refData.set.eSelectorAtPowerUp = E_PowerUp.Off AND refData.set.eModeSource = E_ModeSource.Remote THEN
    refData.set.eHmiModeInAuto := E_Mode.Off;
    stKept.eHmiModeInAuto := E_Mode.Off;
  END_IF;
  eSelWas := eSel;
ELSIF eSel <> eSelWas THEN
  bHeld := FALSE;
  eSelWas := eSel;
END_IF;

(* the mode in use: the selector, or its Auto handing over to the operator's choice *)
bUseSel := FALSE;
bRemoteNow := FALSE;
eUse := eSel;
IF bOk THEN
  CASE refData.set.eModeSource OF
    E_ModeSource.Switch:
      bUseSel := TRUE;
      IF bHeld THEN
        eUse := E_Mode.Off;
      END_IF;
    E_ModeSource.Remote:
      bUseSel := TRUE;
      IF eSel = E_Mode.Auto THEN
        bRemoteNow := TRUE;
        eUse := refData.set.eHmiModeInAuto;
      ELSIF bHeld AND eSel = E_Mode.Hand THEN
        eUse := E_Mode.Off;
      END_IF;
  ELSE
    ;
  END_CASE;
END_IF;
IF bRemoteNow AND NOT bRemoteWas THEN
  ModeTo(eM := eUse);             (* handed over: the operator's choice comes back *)
ELSIF bRemoteNow THEN
  (* the HMI writes the owner's mode: follow it, so it comes back after a local spell *)
  IF (ipEquipment.eActMode = E_Mode.Off OR ipEquipment.eActMode = E_Mode.Hand OR ipEquipment.eActMode = E_Mode.Auto)
     AND refData.set.eHmiModeInAuto <> ipEquipment.eActMode THEN
    refData.set.eHmiModeInAuto := ipEquipment.eActMode;
    stKept.eHmiModeInAuto := ipEquipment.eActMode;
  END_IF;
ELSIF bUseSel THEN
  ModeTo(eM := eUse);
END_IF;
bRemoteWas := bRemoteNow;
refData.sts.bHeldOffAtPowerUp := bHeld AND bUseSel AND eUse = E_Mode.Off AND eSel <> E_Mode.Off;
refData.sts.bModeFromHmi := bRemoteNow OR refData.set.eModeSource = E_ModeSource.Hmi;

(* the buttons: a stop wins *)
eChoice := E_LocalChoice.None;
IF bStopButton AND NOT bStopPrev THEN
  IF ipEquipment.eActMode = E_Mode.Hand OR refData.set.bStopButtonInAuto THEN
    ipEquipment.Command(eCommand := E_EquipCmd.Stop);
  END_IF;
ELSIF NOT bStopButton THEN
  IF bStartButton OR bOpenButton THEN
    ipEquipment.Command(eCommand := E_EquipCmd.Start);
  ELSIF bCloseButton THEN
    IF ipEquipment.eActMode = E_Mode.Hand THEN
      ipEquipment.Command(eCommand := E_EquipCmd.Stop);
    END_IF;
  ELSIF bHaltButton THEN
    eChoice := E_LocalChoice.Halt;
  ELSIF bPosition1Button THEN
    eChoice := E_LocalChoice.Pos1;
  ELSIF bPosition2Button THEN
    eChoice := E_LocalChoice.Pos2;
  ELSIF bPosition3Button THEN
    eChoice := E_LocalChoice.Pos3;
  ELSIF bLowSpeedButton THEN
    eChoice := E_LocalChoice.Low;
  ELSIF bHighSpeedButton THEN
    eChoice := E_LocalChoice.High;
  ELSIF bReverseButton THEN
    eChoice := E_LocalChoice.Reverse;
  END_IF;
END_IF;
bStopPrev := bStopButton;
IF eChoice <> E_LocalChoice.None THEN
  IF __QUERYINTERFACE(ipEquipment, ipChoice) THEN
    bHas := ipChoice.Choose(eLocalChoice := eChoice);
  END_IF;
END_IF;

(* errors *)
bError := NOT bOk;
bWarning := NOT bError AND ((refData.sts.bSelectorFault AND bUseSel) OR refData.sts.bSettingRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.sts.bSelectorFault AND bUseSel THEN
  eErrorId := E_UtError.SelectorFault;
ELSIF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
bModeChanged := NOT bFirstScan AND ipEquipment.eActMode <> eModeWas;
bChangedToOff := bModeChanged AND ipEquipment.eActMode = E_Mode.Off;
eModeWas := ipEquipment.eActMode;
IF bError THEN
  eState := E_State.Fault;
ELSIF refData.sts.bHeldOffAtPowerUp THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK