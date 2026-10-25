FUNCTION UT_ZONE_SEQ_CHECK : BOOL
  VAR_IN_OUT
    S : UT_ZONE_SEQ_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR


Fault := UT_F_NONE;
Warn := UT_F_NONE;
IF S.valveOverlap < T#0s OR S.pumpStartDelay < T#0s OR S.valveCloseDelay < T#0s OR S.masterCloseDelay < T#0s
   OR S.valveLostDelay < T#0s THEN
  Fault := UT_F_VALVE_PUMP_TIME;
ELSIF NOT (S.defaultSp >= 0.0 AND S.defaultSp <= 3.4E38) THEN
  Fault := UT_F_DEFAULT_SP;
END_IF;
IF NOT (S.mode = UT_MODE_OFF OR S.mode = UT_MODE_AUTO) OR S.repeats < 1 OR S.repeats > 100
   OR NOT (S.rainAction = UT_RAIN_PAUSE OR S.rainAction = UT_RAIN_SKIP OR S.rainAction = UT_RAIN_CANCEL
           OR S.rainAction = UT_RAIN_IGNORE) OR S.maxPumpWait < T#0s OR S.flushTime < T#0s
   OR S.core.maxTime < T#0s OR S.core.defaultCap < T#0s OR S.core.maxPause < T#0s OR S.core.meterFailTime < T#0s
   OR S.core.progressSave < T#0s THEN
  Warn := UT_F_SETTING;
ELSIF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
           OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)
           OR (S.run.style = UT_RS_PULSE_TIMER AND S.run.pulseTime > T#0s)) THEN
  Warn := UT_F_RUN_STYLE;
END_IF;
UT_ZONE_SEQ_CHECK := Fault = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION