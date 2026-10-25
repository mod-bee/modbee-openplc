FUNCTION UT_VALVE_MOD_CHECK : BOOL
  VAR_IN_OUT
    S : UT_VALVE_MOD_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR


Fault := UT_F_NONE;
Warn := UT_F_NONE;
IF S.strokeTime < T#0s THEN
  Fault := UT_F_STROKE_TIME;
ELSIF NOT (ABS(S.rawMin) <= 3.4E38 AND ABS(S.rawMax) <= 3.4E38) OR S.rawMin = S.rawMax THEN
  Fault := UT_F_RAW_MIN_MAX;
END_IF;
IF NOT (S.outMin >= 0.0 AND S.outMax <= 100.0 AND S.outMin <= S.outMax) THEN
  Warn := UT_F_OUTPUT_MIN_MAX;
ELSIF NOT (S.rampRate >= 0.0 AND S.rampRate <= 3.4E38)
      OR NOT (S.rateUnit = UT_PER_SEC OR S.rateUnit = UT_PER_MIN OR S.rateUnit = UT_PER_HOUR OR S.rateUnit = UT_PER_DAY) THEN
  Warn := UT_F_RAMP_RATE;
ELSIF NOT (S.tightShutoff >= 0.0 AND S.tightShutoff <= 100.0 AND S.fullOpenAbove >= 0.0 AND S.fullOpenAbove <= 100.0) THEN
  Warn := UT_F_SHUTOFF;
ELSIF NOT (S.safePosition <= 100.0 AND S.safePosition >= -3.4E38) THEN
  Warn := UT_F_FAIL_POSITION;
ELSIF NOT (S.restPos >= 0.0 AND S.restPos <= 100.0 AND S.handPos >= 0.0 AND S.handPos <= 100.0) THEN
  Warn := UT_F_SETTING;
ELSIF NOT UT_POS_FB_CHECK(S := S.pos, Id => Warn) THEN
  ;
END_IF;
UT_VALVE_MOD_CHECK := Fault = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION