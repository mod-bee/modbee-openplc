(* NE107 priority: FAILURE > CHECK_FUNCTION > OUT_OF_SPEC > MAINTENANCE > GOOD *)

FUNCTION UT_NE107_RUN : UT_NE107
  VAR_INPUT
    Fault : BOOL; (* a trip / failure holds the device *)
    Check : BOOL; (* Hand, jog, forced, simulated, out of service *)
    OutOfSpec : BOOL; (* a warning, out of range, a setting warning *)
    Maint : BOOL; (* service due, starts used up *)
  END_VAR

IF Fault THEN
  UT_NE107_RUN := UT_NE_FAILURE;
ELSIF Check THEN
  UT_NE107_RUN := UT_NE_CHECK_FUNCTION;
ELSIF OutOfSpec THEN
  UT_NE107_RUN := UT_NE_OUT_OF_SPEC;
ELSIF Maint THEN
  UT_NE107_RUN := UT_NE_MAINTENANCE;
ELSE
  UT_NE107_RUN := UT_NE_GOOD;
END_IF;

END_FUNCTION