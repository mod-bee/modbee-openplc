(* FB_MotorJog — a held jog (inch) button for a motor in Hand.
While bJogButton is held and the motor is in Hand (and not already running from a Hand start), the motor runs: past its
trips, restart delay and permissive; only Off and the motor's bInterlock stop it. Releasing bJogButton
stops it at once. set.tMaxJogTime (0 = none) ends a jog that is held too long; bJogButton must be released before the next.
A jog is a held button on the panel only: an HMI cannot hold a jog (a lost link would keep it running).
Pins: bJogButton (held), bJogReverse (TRUE: jog in reverse, for an FB_MotorRev), ipMotor (the motor, required), refData ->
bJogging, plus FB_Object's outputs. The jog speed is the motor's: FB_MotorVsd set.fJogSpeedPct, FB_Motor2Speed
set.bJogAtHighSpeed. *)

FUNCTION_BLOCK FB_MotorJog EXTENDS FB_Object
  VAR_INPUT
    bJogButton : BOOL := FALSE; (* the held jog button *)
    bJogReverse : BOOL; (* jog in reverse (a reversing motor, FB_MotorRev) *)
    ipMotor : I_Motor; (* required *)
    refData : REFERENCE TO ST_MotorJogData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bJogging : BOOL; (* the jog is being sent *)
  END_VAR
  VAR RETAIN
    stKept : ST_MotorJogSet;
    nKeptLayout : UINT;
  END_VAR
  VAR CONSTANT
    cLayout : UINT := 1;
  END_VAR
  VAR
    bJogWas : BOOL;
    tJogAt : TIME;
    bUsed : BOOL; (* tMaxJogTime reached on this press *)
  END_VAR


(* the first bad setting (None: all good) *)
METHOD PRIVATE SetWhy : E_UtError
  SetWhy := E_UtError.None;
  IF NOT (refData.set.tMaxJogTime >= T#0s) THEN
    SetWhy := E_UtError.TimeBad;
  END_IF;
END_METHOD

IF ipMotor = NULL OR NOT __ISVALIDREF(refData) THEN
  bJogging := FALSE;
  bError := TRUE;
  IF ipMotor = NULL THEN
    eErrorId := E_UtError.NoMotor;
  ELSE
    eErrorId := E_UtError.NoRecord;
  END_IF;
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
  bJogWas := bJogButton;                (* a button held at power-up is not a press *)
  bUsed := bJogButton;
ELSIF SetWhy() = E_UtError.None THEN
  stKept := refData.set;
ELSE
  refData.sts.eSettingRefusedErrorId := SetWhy();
  refData.set := stKept;
  refData.sts.bSettingRefused := TRUE;
END_IF;
IF SystemReset() THEN
  refData.sts.bSettingRefused := FALSE;
  refData.sts.eSettingRefusedErrorId := E_UtError.None;
END_IF;

IF bJogButton AND NOT bJogWas THEN
  tJogAt := tNow;
  bUsed := FALSE;
END_IF;
bJogWas := bJogButton;
IF bJogButton AND refData.set.tMaxJogTime > T#0s AND tNow - tJogAt >= refData.set.tMaxJogTime THEN
  bUsed := TRUE;
END_IF;
bJogging := bJogButton AND NOT bUsed AND ipMotor.eActMode = E_Mode.Hand;
IF bJogging THEN
  IF bJogReverse THEN
    ipMotor.Command(eCommand := E_EquipCmd.JogRev);
  ELSE
    ipMotor.Command(eCommand := E_EquipCmd.Jog);
  END_IF;
END_IF;
refData.sts.bJogTimeUp := bJogButton AND bUsed;

bError := FALSE;
bWarning := refData.sts.bSettingRefused;
IF refData.sts.bSettingRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bJogging THEN
  eState := E_State.Running;
ELSIF bJogButton THEN
  eState := E_State.Held;         (* not in Hand, or tMaxJogTime reached *)
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK