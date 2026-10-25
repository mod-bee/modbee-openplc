FUNCTION UT_VALVE_FLOAT_CHECK : BOOL
  VAR_IN_OUT
    S : UT_VALVE_FLOAT_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR


Fault := UT_F_NONE;
Warn := UT_F_NONE;
IF S.strokeTime <= T#0s OR S.overTravel < T#0s THEN
  Fault := UT_F_STROKE_TIME;
ELSIF S.minPulse < T#0s OR S.minPulse >= S.strokeTime THEN
  Fault := UT_F_MIN_PULSE;
END_IF;
IF NOT (S.safePosition <= 100.0 AND S.safePosition >= -3.4E38) THEN
  Warn := UT_F_FAIL_POSITION;
ELSIF NOT (S.restPos >= 0.0 AND S.restPos <= 100.0 AND S.handPos >= 0.0 AND S.handPos <= 100.0) THEN
  Warn := UT_F_SETTING;
ELSIF NOT UT_POS_FB_CHECK(S := S.pos, Id => Warn) THEN
  ;
END_IF;
UT_VALVE_FLOAT_CHECK := Fault = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION