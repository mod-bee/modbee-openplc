(* FB_MotorSimulate — test equipment without the plant (src-v2 UT_MOTOR's simulate; DESIGN-0.2.md 5.1). Put it
between the field feedback and the block's feedback pin: bFeedback := bRealFeedback normally; while the record's
bSimulate is on, bFeedback follows bQ (the block's own output, one scan later), as if the contactor / valve
answered. bSimulate is not kept: it is off after a power cut, and a reset of the system clears it. While it is
on: a warning (Simulated), so a simulated machine is never mistaken for a real one.
Pins: bQ (the block's output), bRealFeedback (the field contact), refData -> bFeedback, plus FB_Object's outputs. *)

FUNCTION_BLOCK FB_MotorSimulate EXTENDS FB_Object
  VAR_INPUT
    bQ : BOOL := FALSE; (* the block's output (motor bQ, valve bOut ...) *)
    bRealFeedback : BOOL; (* the field feedback contact *)
    refData : REFERENCE TO ST_MotorSimulateData;
  END_VAR
  VAR_OUTPUT
    bFeedback : BOOL; (* -> the block's feedback pin *)
  END_VAR
  VAR
    bQWas : BOOL; (* the output one scan back *)
  END_VAR


IF NOT __ISVALIDREF(refData) THEN
  bFeedback := bRealFeedback;     (* no record: the real feedback, never a simulated one *)
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF SystemReset() THEN
  refData.bSimulate := FALSE;
END_IF;
IF refData.bSimulate THEN
  bFeedback := bQWas;
ELSE
  bFeedback := bRealFeedback;
END_IF;
bQWas := bQ;
bError := FALSE;
bWarning := refData.bSimulate;
IF refData.bSimulate THEN
  eErrorId := E_UtError.Simulated;
  eState := E_State.Running;
ELSE
  eErrorId := E_UtError.None;
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK