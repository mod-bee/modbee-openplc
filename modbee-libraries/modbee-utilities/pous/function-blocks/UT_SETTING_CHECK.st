(* UT_SETTING_CHECK — write gate for one project value that belongs to no
block: the HMI / SCADA writes its own variable (New); each time New
changes, or on Written, New is checked (a number, MinValue..MaxValue, above
Above and below Below for related settings, e.g. H above L). Passed: Value
:= New, Accepted for one scan. Failed: Value keeps its old value, Refused
for one scan, RefusedWhy says why (UT_F_VALUE_BAD, UT_F_LIMITS,
UT_F_BELOW_MIN, UT_F_ABOVE_MAX, UT_F_NOT_ABOVE, UT_F_NOT_BELOW). Bad /
BadWhy: Value itself fails the checks now (written past this block, or a
limit moved). Unwired limits are open. Nothing is checked on the first
scan: a master variable that comes back 0 never overwrites a kept value
(Value is the project's RETAIN variable). *)

FUNCTION_BLOCK UT_SETTING_CHECK
  VAR_INPUT
    New : REAL; (* the value the master wrote *)
    Written : BOOL R_EDGE; (* check New now, even if unchanged *)
    MinValue : REAL := -3.4E38;
    MaxValue : REAL := 3.4E38;
    Above : REAL := -3.4E38; (* must be above this related setting *)
    Below : REAL := 3.4E38; (* must be below this related setting *)
  END_VAR
  VAR_OUTPUT
    Accepted : BOOL; (* one scan *)
    Refused : BOOL; (* one scan *)
    Bad : BOOL;
    RefusedWhy : UT_FAULT; (* the last refused write (UT_F_NONE after an accepted one) *)
    BadWhy : UT_FAULT;
  END_VAR
  VAR_IN_OUT
    Value : REAL; (* the value in use (a project RETAIN variable) *)
  END_VAR
  VAR
    started : BOOL;
    newPrev : REAL;
    check : BOOL;
    why : UT_FAULT;
    limitsOk : BOOL;
  END_VAR


Accepted := FALSE;
Refused := FALSE;
IF NOT started THEN
  started := TRUE;
  newPrev := New;
  check := FALSE;
ELSE
  (* NaN never equals itself: NaN to NaN is no change *)
  check := NOT (New = newPrev OR (NOT (New = New) AND NOT (newPrev = newPrev))) OR Written;
END_IF;
newPrev := New;
limitsOk := MinValue = MinValue AND MaxValue = MaxValue AND Above = Above AND Below = Below
            AND MinValue >= -3.4E38 AND MaxValue <= 3.4E38 AND Above >= -3.4E38 AND Below <= 3.4E38;
IF check THEN
  IF NOT limitsOk THEN
    why := UT_F_LIMITS;
  ELSE
    why := UT_CHECK_REAL(Value := New, MinValue := MinValue, MaxValue := MaxValue, UseAbove := Above > -3.4E38,
                         Above := Above, UseBelow := Below < 3.4E38, Below := Below);
  END_IF;
  IF why = UT_F_NONE THEN
    Value := New;
    Accepted := TRUE;
  ELSE
    Refused := TRUE;
  END_IF;
  RefusedWhy := why;
END_IF;
IF NOT limitsOk THEN
  BadWhy := UT_F_LIMITS;
ELSE
  BadWhy := UT_CHECK_REAL(Value := Value, MinValue := MinValue, MaxValue := MaxValue, UseAbove := Above > -3.4E38,
                          Above := Above, UseBelow := Below < 3.4E38, Below := Below);
END_IF;
Bad := BadWhy <> UT_F_NONE;

END_FUNCTION_BLOCK