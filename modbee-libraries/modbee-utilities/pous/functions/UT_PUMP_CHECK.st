(* The pump's settings: the first that refuses running (Fault) or warns (Warn) *)

FUNCTION UT_PUMP_CHECK : BOOL
  VAR_IN_OUT
    S : UT_PUMP_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR
  VAR
    primeOn : BOOL;
  END_VAR


Fault := UT_F_NONE;
Warn := UT_F_NONE;
primeOn := S.prime.enable;
IF NOT (S.modeSource = UT_SRC_HMI OR S.modeSource = UT_SRC_SWITCH OR S.modeSource = UT_SRC_REMOTE) THEN
  Fault := UT_F_MODE_SOURCE;
ELSIF NOT (S.prime.doneBy = UT_PRIME_PRESSURE OR S.prime.doneBy = UT_PRIME_FLOW OR S.prime.doneBy = UT_PRIME_INPUT
           OR S.prime.doneBy = UT_PRIME_TIME) THEN
  Fault := UT_F_PRIME_DONEBY;
ELSIF S.prime.doneBy = UT_PRIME_TIME AND S.prime.runTime <= T#0s THEN
  Fault := UT_F_PRIME_TIME;
ELSIF NOT UT_MEAS_OK(OrderCheck := TRUE, M := S.pressure) THEN
  Fault := UT_F_PRESSURE_SENSOR;
ELSIF NOT UT_MEAS_OK(OrderCheck := TRUE, M := S.flow) THEN
  Fault := UT_F_FLOW_SENSOR;
ELSIF NOT UT_MEAS_OK(OrderCheck := TRUE, M := S.suction) THEN
  Fault := UT_F_SUCTION_SENSOR;
ELSIF NOT (S.role = UT_ROLE_DUTY OR S.role = UT_ROLE_JOCKEY OR S.role = UT_ROLE_BOOSTER) THEN
  Fault := UT_F_PUMP_ROLE;
ELSIF NOT (S.starts.maxPerHour >= 0 AND S.starts.maxPerHour <= 30 AND S.starts.window > T#0s
           AND S.starts.minBetween >= T#0s AND S.starts.failWait >= T#0s) THEN
  Fault := UT_F_STARTS_LIMIT;
END_IF;
IF S.startDelay < T#0s OR S.stopDelay < T#0s OR S.minRunTime < T#0s OR S.minOffTime < T#0s OR S.startMask < T#0s
   OR S.exerciseInterval < T#0s OR S.exerciseTime < T#0s OR S.prime.timeout < T#0s OR S.prime.holdTime < T#0s
   OR S.retryWindow < T#0s OR NOT (S.capacity >= 0.0 AND S.capacity <= 3.4E38) THEN
  Warn := UT_F_SETTING;
ELSIF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
           OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)
           OR (S.run.style = UT_RS_PULSE_TIMER AND S.run.pulseTime > T#0s)) THEN
  Warn := UT_F_RUN_STYLE;
ELSIF NOT (UT_PROT_OK(P := S.sealLeak) AND UT_PROT_OK(P := S.extFault) AND UT_PROT_OK(P := S.primeTimeout)
           AND UT_PROT_OK(P := S.maxRun) AND UT_PROT_OK(P := S.startFail) AND UT_PROT_OK(P := S.dropped)) THEN
  Warn := UT_F_SETTING;
END_IF;
UT_PUMP_CHECK := Fault = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION