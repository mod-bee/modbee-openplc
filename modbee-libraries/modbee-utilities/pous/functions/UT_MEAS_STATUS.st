FUNCTION UT_MEAS_STATUS : UT_STATUS
  VAR_INPUT
    Inhibit : BOOL;
    Fitted : BOOL := TRUE;
  END_VAR
  VAR_IN_OUT
    Meas : UT_MEAS;
    Sts : UT_MEAS_STS;
    St : UT_MEAS_ST;
  END_VAR
  VAR_OUTPUT
    FaultId : UT_FAULT;
    TimeLeft : TIME;
  END_VAR
  VAR
    code : UT_STATUS;
  END_VAR


FaultId := UT_F_NONE;
TimeLeft := T#0s;
IF St.hh.trip THEN
  code := UT_PROT_STATUS(Reset := Meas.hiHi.reset, Sts := Sts.hiHi); FaultId := UT_F_HIGH_HIGH; TimeLeft := Sts.hiHi.timeLeft;
ELSIF St.ll.trip THEN
  code := UT_PROT_STATUS(Reset := Meas.loLo.reset, Sts := Sts.loLo); FaultId := UT_F_LOW_LOW; TimeLeft := Sts.loLo.timeLeft;
ELSIF St.h.trip THEN
  code := UT_PROT_STATUS(Reset := Meas.hi.reset, Sts := Sts.hi); FaultId := UT_F_HIGH; TimeLeft := Sts.hi.timeLeft;
ELSIF St.l.trip THEN
  code := UT_PROT_STATUS(Reset := Meas.lo.reset, Sts := Sts.lo); FaultId := UT_F_LOW; TimeLeft := Sts.lo.timeLeft;
ELSIF St.sb.trip THEN
  code := UT_PROT_STATUS(Reset := Meas.sensorBad.reset, Sts := Sts.sensorBad); FaultId := UT_F_SENSOR_BAD;
  TimeLeft := Sts.sensorBad.timeLeft;
ELSIF Inhibit THEN
  code := UT_ST_INHIBITED;
ELSIF NOT Meas.installed OR (NOT Fitted AND Meas.sensor <> UT_SENSOR_SWITCH AND Meas.sensor <> UT_SENSOR_BOTH) THEN
  code := UT_ST_NOT_FITTED;      (* a plug not fitted: only its switches, if any, are checked *)
ELSIF St.hh.warn THEN
  code := UT_ST_WARNING; FaultId := UT_F_HIGH_HIGH;
ELSIF St.ll.warn THEN
  code := UT_ST_WARNING; FaultId := UT_F_LOW_LOW;
ELSIF St.h.warn THEN
  code := UT_ST_WARNING; FaultId := UT_F_HIGH;
ELSIF St.l.warn THEN
  code := UT_ST_WARNING; FaultId := UT_F_LOW;
ELSIF St.sb.warn OR St.goodHeld THEN
  code := UT_ST_WARNING; FaultId := UT_F_SENSOR_BAD; TimeLeft := Sts.sensorBad.timeLeft;
ELSIF St.badOrder THEN
  code := UT_ST_CONFIG; FaultId := UT_F_SP_ORDER;
ELSIF St.badSetting THEN
  code := UT_ST_WARN_SETTING; FaultId := UT_F_LEVEL_SETTING;
ELSE
  code := UT_ST_OK;                (* a level's delay counting: named, with its time *)
  IF Sts.hiHi.timeLeft > T#0s THEN
    FaultId := UT_F_HIGH_HIGH; TimeLeft := Sts.hiHi.timeLeft;
  ELSIF Sts.loLo.timeLeft > T#0s THEN
    FaultId := UT_F_LOW_LOW; TimeLeft := Sts.loLo.timeLeft;
  ELSIF Sts.hi.timeLeft > T#0s THEN
    FaultId := UT_F_HIGH; TimeLeft := Sts.hi.timeLeft;
  ELSIF Sts.lo.timeLeft > T#0s THEN
    FaultId := UT_F_LOW; TimeLeft := Sts.lo.timeLeft;
  END_IF;
END_IF;
IF TimeLeft < T#0s THEN
  TimeLeft := T#0s;
END_IF;
UT_MEAS_STATUS := code;

END_FUNCTION