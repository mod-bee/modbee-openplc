(* FB_MotorJog — a held jog (inch) button for a motor in Hand (src-v2 UT_MOTOR's Jog / jogMax; DESIGN-0.2.md 5.1).
While bJog is held and the motor is in Hand (and not already running from a Hand start), the motor runs: past its
trips, restart delay and permissive, as src-v2 did; only Off and the motor's bInterlock stop it. Releasing bJog
stops it at once. set.tJogMax (0 = none) ends a jog that is held too long; bJog must be released before the next.
A jog is a held button on the panel only: an HMI cannot hold a jog (a lost link would keep it running).
Pins: bJog (held), ipMotor (the motor, required), refData -> bJogging, plus FB_Object's outputs. *)

FUNCTION_BLOCK FB_MotorJog EXTENDS FB_Object
  VAR_INPUT
    bJog : BOOL := FALSE; (* the held jog button *)
    ipMotor : I_Equipment; (* required *)
    refData : REFERENCE TO ST_MotorJogData;
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
    bUsed : BOOL; (* tJogMax reached on this press *)
  END_VAR


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
  bJogWas := bJog;                (* a button held at power-up is not a press *)
  bUsed := bJog;
ELSIF refData.set.tJogMax >= T#0s THEN
  stKept := refData.set;
ELSE
  refData.set := stKept;
  refData.bRefused := TRUE;
END_IF;
IF SystemReset() THEN
  refData.bRefused := FALSE;
END_IF;

IF bJog AND NOT bJogWas THEN
  tJogAt := tNow;
  bUsed := FALSE;
END_IF;
bJogWas := bJog;
IF bJog AND refData.set.tJogMax > T#0s AND tNow - tJogAt >= refData.set.tJogMax THEN
  bUsed := TRUE;
END_IF;
bJogging := bJog AND NOT bUsed AND ipMotor.eActMode = E_Mode.Hand;
IF bJogging THEN
  ipMotor.Command(eCmd := E_EquipCmd.Jog);
END_IF;
refData.bLimited := bJog AND bUsed;

bError := FALSE;
bWarning := refData.bRefused;
IF refData.bRefused THEN
  eErrorId := E_UtError.SettingRefused;
ELSE
  eErrorId := E_UtError.None;
END_IF;
IF bJogging THEN
  eState := E_State.Running;
ELSIF bJog THEN
  eState := E_State.Held;         (* not in Hand, or tJogMax reached *)
ELSE
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK