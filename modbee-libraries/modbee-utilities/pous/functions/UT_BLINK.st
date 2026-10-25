(* A flashing lamp from the PLC clock: TRUE for OnTime, FALSE for OffTime, all
lamps using it flash in step. No memory: wire it into a lamp's rung. *)

FUNCTION UT_BLINK : BOOL
  VAR_INPUT
    OnTime : TIME := T#500ms;
    OffTime : TIME := T#500ms;
  END_VAR
  VAR
    period : LINT;
    onMs : LINT;
  END_VAR


onMs := TIME_TO_LINT(OnTime);
period := onMs + TIME_TO_LINT(OffTime);
IF onMs <= 0 THEN
  UT_BLINK := FALSE;
ELSIF period <= onMs THEN
  UT_BLINK := TRUE;
ELSE
  UT_BLINK := (TIME_TO_LINT(TIME()) MOD period) < onMs;
END_IF;

END_FUNCTION