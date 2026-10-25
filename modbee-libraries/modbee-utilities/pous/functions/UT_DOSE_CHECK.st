FUNCTION UT_DOSE_CHECK : BOOL
  VAR_IN_OUT
    S : UT_DOSE_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR


Fault := UT_F_NONE;
Warn := UT_F_NONE;
IF NOT (S.doseMode = UT_DOSE_BATCH OR S.doseMode = UT_DOSE_FLOW OR S.doseMode = UT_DOSE_TIMED) THEN
  Fault := UT_F_DOSE_MODE;
ELSIF S.onTime < T#0s OR S.offTime < T#0s THEN
  Fault := UT_F_TIMED_ON_OFF;
END_IF;
IF NOT (S.mode = UT_MODE_OFF OR S.mode = UT_MODE_HAND OR S.mode = UT_MODE_AUTO OR S.mode = UT_MODE_OOS)
   OR NOT (S.preact >= 0.0 AND S.preact <= 3.4E38) OR NOT (S.slowAt >= 0.0 AND S.slowAt <= 3.4E38)
   OR NOT (S.tolerance >= 0.0 AND S.tolerance <= 3.4E38) OR S.settleTime < T#0s
   OR NOT (S.target >= 0.0 AND S.target <= 3.4E38) OR NOT (S.ratio >= 0.0 AND S.ratio <= 3.4E38)
   OR NOT (S.pumpCapacity >= 0.0 AND S.pumpCapacity <= 3.4E38)
   OR NOT (S.pulseVolume >= 0.0 AND S.pulseVolume <= 3.4E38) OR S.pulseWidth < T#0s
   OR NOT (S.minFlow >= 0.0 AND S.minFlow <= 3.4E38) OR NOT (S.maxRate >= 0.0 AND S.maxRate <= 100.0)
   OR NOT (S.flowPer = UT_PER_SEC OR S.flowPer = UT_PER_MIN OR S.flowPer = UT_PER_HOUR OR S.flowPer = UT_PER_DAY)
   OR S.carrierProven < T#0s OR NOT (S.handRate >= 0.0 AND S.handRate <= 100.0) OR S.handMax < T#0s
   OR NOT (S.maxQuantity >= 0.0 AND S.maxQuantity <= 1.0E15) OR S.retryWindow < T#0s
   OR NOT (UT_PROT_OK(P := S.noFlow) AND UT_PROT_OK(P := S.maxTime) AND UT_PROT_OK(P := S.overCapacity)
           AND UT_PROT_OK(P := S.outOfTolerance) AND UT_PROT_OK(P := S.stockLow)) THEN
  Warn := UT_F_SETTING;
ELSIF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
           OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)
           OR (S.run.style = UT_RS_PULSE_TIMER AND S.run.pulseTime > T#0s)) THEN
  Warn := UT_F_RUN_STYLE;
END_IF;
UT_DOSE_CHECK := Fault = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION