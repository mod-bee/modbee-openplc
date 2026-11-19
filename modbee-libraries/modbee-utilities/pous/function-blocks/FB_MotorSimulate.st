(* FB_MotorSimulate — test equipment without the plant. Put it between the field feedback and the block's feedback
pin: bFeedback := bFieldFeedback normally; while the record's
bSimulateFeedback is on, bFeedback follows bOutput (the block's own output, one scan later), as if the contactor / valve
answered. bSimulateFeedback is not kept: it is off after a power cut, and a reset of the system clears it. While it is
on: a warning (Simulated), so a simulated machine is never mistaken for a real one.
Pins: bOutput (the block's output), bFieldFeedback (the field contact), refData -> bFeedback, plus FB_Object's outputs. *)

FUNCTION_BLOCK FB_MotorSimulate EXTENDS FB_Object
  VAR_INPUT
    bOutput : BOOL := FALSE; (* the block's output (motor bOutput, valve bOutput ...) *)
    bFieldFeedback : BOOL; (* the field feedback contact *)
    refData : REFERENCE TO ST_MotorSimulateData; (* the block's record *)
  END_VAR
  VAR_OUTPUT
    bFeedback : BOOL; (* -> the block's feedback pin *)
  END_VAR
  VAR
    bQWas : BOOL; (* the output one scan back *)
  END_VAR


IF NOT __ISVALIDREF(refData) THEN
  bFeedback := bFieldFeedback;     (* no record: the real feedback, never a simulated one *)
  bError := TRUE;
  eErrorId := E_UtError.NoRecord;
  eState := E_State.Fault;
  RETURN;
END_IF;
IF SystemReset() THEN
  refData.bSimulateFeedback := FALSE;
END_IF;
IF refData.bSimulateFeedback THEN
  bFeedback := bQWas;
ELSE
  bFeedback := bFieldFeedback;
END_IF;
bQWas := bOutput;
bError := FALSE;
bWarning := refData.bSimulateFeedback;
IF refData.bSimulateFeedback THEN
  eErrorId := E_UtError.Simulated;
  eState := E_State.Running;
ELSE
  eErrorId := E_UtError.None;
  eState := E_State.Idle;
END_IF;
bFirstScan := FALSE;

END_FUNCTION_BLOCK