(* A REAL setting: a number inside MinValue..MaxValue, and (when UseAbove /
UseBelow) strictly above Above / below Below. *)

FUNCTION UT_CHECK_REAL : UT_FAULT
  VAR_INPUT
    Value : REAL;
    MinValue : REAL;
    MaxValue : REAL;
    UseAbove : BOOL;
    Above : REAL;
    UseBelow : BOOL;
    Below : REAL;
  END_VAR

IF NOT (Value = Value) OR Value > 3.4E38 OR Value < -3.4E38 THEN
  UT_CHECK_REAL := UT_F_VALUE_BAD;
ELSIF MinValue > MaxValue THEN
  UT_CHECK_REAL := UT_F_LIMITS;
ELSIF Value < MinValue THEN
  UT_CHECK_REAL := UT_F_BELOW_MIN;
ELSIF Value > MaxValue THEN
  UT_CHECK_REAL := UT_F_ABOVE_MAX;
ELSIF UseAbove AND NOT (Value > Above) THEN
  UT_CHECK_REAL := UT_F_NOT_ABOVE;
ELSIF UseBelow AND NOT (Value < Below) THEN
  UT_CHECK_REAL := UT_F_NOT_BELOW;
ELSE
  UT_CHECK_REAL := UT_F_NONE;
END_IF;

END_FUNCTION