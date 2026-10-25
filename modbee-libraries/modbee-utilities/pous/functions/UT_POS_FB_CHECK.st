(* The pos settings: TRUE when usable; Id = the first that is not *)

FUNCTION UT_POS_FB_CHECK : BOOL
  VAR_IN_OUT
    S : UT_VALVE_POS_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR


Id := UT_F_NONE;
IF NOT (S.deadband >= 0.0 AND S.deadband <= 50.0) THEN
  Id := UT_F_DEADBAND;
ELSIF NOT (S.closedThreshold >= 0.0 AND S.openThreshold <= 100.0 AND S.closedThreshold < S.openThreshold) THEN
  Id := UT_F_OPEN_THRESHOLD;
ELSIF NOT UT_LEVEL_OK(L := S.deviation) THEN
  Id := UT_F_POS_DEVIATION;
ELSIF NOT UT_PROT_OK(P := S.posFeedback) THEN
  Id := UT_F_POS_FEEDBACK;
END_IF;
UT_POS_FB_CHECK := Id = UT_F_NONE;

END_FUNCTION