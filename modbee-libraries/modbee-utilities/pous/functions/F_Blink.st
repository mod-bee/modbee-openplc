(* A flashing lamp from the PLC clock: TRUE for tOnTime, FALSE for tOffTime; all lamps using it flash in step. No memory. *)

FUNCTION F_Blink : BOOL
  VAR_INPUT
    tOnTime : TIME := T#500ms;
    tOffTime : TIME := T#500ms;
  END_VAR
  VAR
    nPeriod : LINT;
    nOnMs : LINT;
  END_VAR


nOnMs := TIME_TO_LINT(tOnTime);
nPeriod := nOnMs + TIME_TO_LINT(tOffTime);
IF nOnMs <= 0 THEN
  F_Blink := FALSE;
ELSIF nPeriod <= nOnMs THEN
  F_Blink := TRUE;
ELSE
  F_Blink := (TIME_TO_LINT(TIME()) MOD nPeriod) < nOnMs;
END_IF;

END_FUNCTION