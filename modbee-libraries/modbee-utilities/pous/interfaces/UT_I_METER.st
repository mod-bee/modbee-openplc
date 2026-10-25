(* A meter with a total; Value = rate *)

INTERFACE UT_I_METER EXTENDS UT_I_MEAS


METHOD GetTotal : LREAL             // lifetime running total; NaN = none
END_METHOD
METHOD TotalUnit : UT_UNIT       // L / M3 / ML / GAL / NONE
END_METHOD

END_INTERFACE