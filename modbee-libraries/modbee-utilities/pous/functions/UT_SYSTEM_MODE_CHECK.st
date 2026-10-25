FUNCTION UT_SYSTEM_MODE_CHECK : BOOL
  VAR_IN_OUT
    S : UT_SYSTEM_MODE_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR


Id := UT_F_NONE;
IF S.autoTypes < 1 OR S.autoTypes > 8 THEN
  Id := UT_F_AUTO_TYPES;
ELSIF S.autoType < 1 OR S.autoType > S.autoTypes THEN
  Id := UT_F_AUTO_TYPE;
ELSIF NOT (S.mode = UT_MODE_OFF OR S.mode = UT_MODE_HAND OR S.mode = UT_MODE_AUTO)
      OR S.manualMaxRun < T#0s OR S.powerOnDelay < T#0s THEN
  Id := UT_F_SETTING;
ELSIF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
           OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)
           OR (S.run.style = UT_RS_PULSE_TIMER AND S.run.pulseTime > T#0s)) THEN
  Id := UT_F_RUN_STYLE;
END_IF;
UT_SYSTEM_MODE_CHECK := Id = UT_F_NONE;

END_FUNCTION