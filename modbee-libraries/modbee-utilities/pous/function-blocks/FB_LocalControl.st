(* FB_LocalControl — the panel-door controls of one piece of equipment: an Off / Hand / Auto selector and the
push-buttons (the src-v2 motor's and valve's selector and local buttons, UT_HOA, UT_MODE_SELECT's source).

The mode (set.eModeSource):
  Hmi     the selector is not used: the owner's own mode (its record, the HMI)
  Switch  the selector sets the owner's mode: bSwHand = Hand, bSwAuto = Auto, neither = Off (the panel cannot
          change it while it is fitted)
  Remote  the selector's Off and Hand act here; its Auto hands the mode to the operator's choice set.eHmiMode
          (written by the block from the owner's mode while the selector is in Auto, so the HMI's choice comes
          back when the selector returns to Auto)
Both selector contacts made: Off, a warning (SelectorFault). With set.ePowerUp Off a selector found out of Off
at power-up is held Off until it is moved (Remote: a selector found in Hand; the operator's choice goes to Off).
The buttons (rising edges; bStop is TRUE = pressed, an NC button inverted with NOT at the pin; a stop wins):
  bStart          Hand start (a valve: open), as the record's bCmdStart
  bStop           stops the owner in Hand, and in Auto too with set.bStopInAuto (off until the owner's request
                  drops)
  bOpen / bClose  a valve in Hand: open / close (bOpen as bStart; bClose acts in Hand only)
  bHalt           a motorised valve in Hand: stop where it is
  bPos1..bPos3    a three-position valve in Hand: go to that position
  bLow / bHigh    a two-speed motor in Hand: that speed (and start)
  bRev            a reversing motor in Hand: reverse (and start); bStart starts in the last direction
bHalt .. bRev go to the owner's I_LocalChoice (FB_ValveMotor, FB_Valve3Pos, FB_Motor2Speed, FB_MotorRev); an
owner without that choice ignores the button. Only the owner starts anything.
Settings are kept by the block (a retained last-good copy): restored at power-up, a bad write put back. *)

FUNCTION_BLOCK FB_LocalControl EXTENDS FB_Object
  VAR_INPUT
    bSwHand : BOOL := FALSE;
    bSwAuto : BOOL;
    bStart : BOOL R_EDGE;
    bStop : BOOL;
    ipOwner : I_Equipment;
    refData : REFERENCE TO ST_LocalControlData;
    bOpen : BOOL R_EDGE; (* a valve: open (Hand) *)
    bClose : BOOL R_EDGE; (* a valve: close (Hand) *)
    bHalt : BOOL R_EDGE; (* a motorised valve: stop where it is (Hand) *)
    bPos1 : BOOL R_EDGE; (* a three-position valve: go to 1 (Hand) *)
    bPos2 : BOOL R_EDGE;
    bPos3 : BOOL R_EDGE;
    bLow : BOOL R_EDGE; (* a two-speed motor: low (Hand) *)
    bHigh : BOOL R_EDGE; (* a two-speed motor: high (Hand) *)
    bRev : BOOL R_EDGE; (* a reversing motor: reverse (Hand) *)
  END_VAR
  VAR RETAIN
    stKept : ST_LocalControlSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 2;
  END_VAR
  VAR
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


METHOD PRIVATE SetOk : BOOL
  VAR_INPUT
    stS : REFERENCE TO ST_LocalControlSet;
  END_VAR
  SetOk := (stS.eModeSource = E_ModeSource.Hmi OR stS.eModeSource = E_ModeSource.Switch
            OR stS.eModeSource = E_ModeSource.Remote)
           AND (stS.ePowerUp = E_PowerUp.Last OR stS.ePowerUp = E_PowerUp.Off)
           AND (stS.eHmiMode = E_Mode.Off OR stS.eHmiMode = E_Mode.Hand OR stS.eHmiMode = E_Mode.Auto);
END_METHOD

(* the owner to this mode *)
METHOD PRIVATE ModeTo : BOOL
  VAR_INPUT
    eM : E_Mode;
  END_VAR
  CASE eM OF
    E_Mode.Hand: ipOwner.Command(eCmd := E_EquipCmd.ModeHand);
    E_Mode.Auto: ipOwner.Command(eCmd := E_EquipCmd.ModeAuto);
  ELSE
    ipOwner.Command(eCmd := E_EquipCmd.ModeOff);
  END_CASE;
  ModeTo := TRUE;
END_METHOD

IF NOT __ISVALIDREF(refData) OR ipOwner = NULL THEN
  bError := TRUE;
  IF ipOwner = NULL THEN eErrorId := E_UtError.NoMotor; ELSE eErrorId := E_UtError.NoRecord; END_IF;
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
  refData.set := stKept;
  refData.bRefused := TRUE;
  bOk := TRUE;
END_IF;
IF SystemReset() THEN
  refData.bRefused := FALSE;
END_IF;

(* the selector *)
refData.bSelectorFault := bSwHand AND bSwAuto;
IF refData.bSelectorFault OR (NOT bSwHand AND NOT bSwAuto) THEN
  eSel := E_Mode.Off;
ELSIF bSwHand THEN
  eSel := E_Mode.Hand;
ELSE
  eSel := E_Mode.Auto;
END_IF;
IF bFirstScan THEN
  (* power-up Off: a selector found out of Off waits to be moved; Remote: the operator's choice goes Off *)
  bHeld := refData.set.ePowerUp = E_PowerUp.Off AND eSel <> E_Mode.Off;
  IF refData.set.ePowerUp = E_PowerUp.Off AND refData.set.eModeSource = E_ModeSource.Remote THEN
    refData.set.eHmiMode := E_Mode.Off;
    stKept.eHmiMode := E_Mode.Off;
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
        eUse := refData.set.eHmiMode;
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
  IF (ipOwner.eActMode = E_Mode.Off OR ipOwner.eActMode = E_Mode.Hand OR ipOwner.eActMode = E_Mode.Auto)
     AND refData.set.eHmiMode <> ipOwner.eActMode THEN
    refData.set.eHmiMode := ipOwner.eActMode;
    stKept.eHmiMode := ipOwner.eActMode;
  END_IF;
ELSIF bUseSel THEN
  ModeTo(eM := eUse);
END_IF;
bRemoteWas := bRemoteNow;
refData.bHeldOff := bHeld AND bUseSel AND eUse = E_Mode.Off AND eSel <> E_Mode.Off;
refData.bRemote := bRemoteNow OR refData.set.eModeSource = E_ModeSource.Hmi;

(* the buttons: a stop wins *)
eChoice := E_LocalChoice.None;
IF bStop AND NOT bStopPrev THEN
  IF ipOwner.eActMode = E_Mode.Hand OR refData.set.bStopInAuto THEN
    ipOwner.Command(eCmd := E_EquipCmd.Stop);
  END_IF;
ELSIF NOT bStop THEN
  IF bStart OR bOpen THEN
    ipOwner.Command(eCmd := E_EquipCmd.Start);
  ELSIF bClose THEN
    IF ipOwner.eActMode = E_Mode.Hand THEN
      ipOwner.Command(eCmd := E_EquipCmd.Stop);
    END_IF;
  ELSIF bHalt THEN
    eChoice := E_LocalChoice.Halt;
  ELSIF bPos1 THEN
    eChoice := E_LocalChoice.Pos1;
  ELSIF bPos2 THEN
    eChoice := E_LocalChoice.Pos2;
  ELSIF bPos3 THEN
    eChoice := E_LocalChoice.Pos3;
  ELSIF bLow THEN
    eChoice := E_LocalChoice.Low;
  ELSIF bHigh THEN
    eChoice := E_LocalChoice.High;
  ELSIF bRev THEN
    eChoice := E_LocalChoice.Reverse;
  END_IF;
END_IF;
bStopPrev := bStop;
IF eChoice <> E_LocalChoice.None THEN
  IF __QUERYINTERFACE(ipOwner, ipChoice) THEN
    bHas := ipChoice.Choose(eChoice := eChoice);
  END_IF;
END_IF;

(* errors *)
bError := NOT bOk;
bWarning := NOT bError AND ((refData.bSelectorFault AND bUseSel) OR refData.bRefused);
IF NOT bOk THEN
  eErrorId := E_UtError.BadSetting;
ELSIF refData.bSelectorFault AND bUseSel THEN
  eErrorId := E_UtError.SelectorFault;
ELSIF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bError THEN
  eState := E_State.Fault;
ELSIF refData.bHeldOff THEN
  eState := E_State.Held;
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK