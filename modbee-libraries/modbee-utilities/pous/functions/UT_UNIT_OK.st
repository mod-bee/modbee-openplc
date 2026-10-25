(* TRUE when UT_UNIT_CONV can convert FromUnit to ToUnit: both units are of the same
kind and neither is NONE *)

FUNCTION UT_UNIT_OK : BOOL
  VAR_INPUT
    FromUnit : UT_UNIT;
    ToUnit : UT_UNIT;
  END_VAR
  VAR
    kindFrom : USINT;
  END_VAR


kindFrom := UT_UNIT_KIND(Unit := FromUnit);
UT_UNIT_OK := kindFrom <> 0 AND kindFrom = UT_UNIT_KIND(Unit := ToUnit);

END_FUNCTION