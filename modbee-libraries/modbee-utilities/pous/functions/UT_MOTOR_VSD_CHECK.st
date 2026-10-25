(* The drive's settings: the first that refuses every run, refuses Hand, or warns *)

FUNCTION UT_MOTOR_VSD_CHECK : BOOL
  VAR_INPUT
    HandWired : BOOL; (* the HandSpeed pin is wired *)
  END_VAR
  VAR_IN_OUT
    S : UT_MOTOR_VSD_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Hand : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR


Fault := UT_F_NONE;
Hand := UT_F_NONE;
Warn := UT_F_NONE;
IF NOT (S.minSpeed >= 0.0 AND S.maxSpeed <= 100.0 AND S.minSpeed <= S.maxSpeed) THEN
  Fault := UT_F_MIN_MAX_SPEED;
ELSIF NOT (S.accelRate >= 0.0 AND S.accelRate <= 3.4E38 AND S.decelRate >= 0.0 AND S.decelRate <= 3.4E38) THEN
  Fault := UT_F_ACCEL_RATE;
ELSIF NOT (S.rateUnit = UT_PER_SEC OR S.rateUnit = UT_PER_MIN OR S.rateUnit = UT_PER_HOUR OR S.rateUnit = UT_PER_DAY) THEN
  Fault := UT_F_RATE_UNIT;
ELSIF NOT (S.skipLow <= S.skipHigh AND ABS(S.skipLow) <= 3.4E38 AND ABS(S.skipHigh) <= 3.4E38)
      OR (S.skipHigh > S.skipLow AND S.skipLow <= S.minSpeed AND S.skipHigh >= S.maxSpeed) THEN
  Fault := UT_F_SKIP_BAND;
ELSIF NOT (S.rawMin >= 0.0 AND S.rawMin <= 65535.0 AND S.rawMax >= 0.0 AND S.rawMax <= 65535.0 AND S.rawMin <> S.rawMax) THEN
  Fault := UT_F_RAW_MIN_MAX;
ELSIF NOT (S.resetPulse > T#0s AND S.resetPulse <= T#5s) THEN
  Fault := UT_F_RESET_PULSE;
END_IF;
IF NOT HandWired AND NOT (S.handSpeed >= 0.0 AND S.handSpeed <= 100.0) THEN
  Hand := UT_F_HAND_SPEED;
ELSIF NOT (S.jogSpeed >= 0.0 AND S.jogSpeed <= 100.0) THEN
  Hand := UT_F_HAND_SPEED;
END_IF;
IF S.driveRamp < T#0s THEN
  Warn := UT_F_DRIVE_RAMP;
ELSIF NOT (S.ratedHz >= 0.0 AND S.ratedHz <= 3.4E38 AND S.ratedRpm >= 0.0 AND S.ratedRpm <= 3.4E38) THEN
  Warn := UT_F_RATED_HZ_RPM;
ELSIF NOT UT_PROT_OK(P := S.driveNotReady) THEN
  Warn := UT_F_DRIVE_NOT_READY;
ELSIF NOT UT_LEVEL_OK(L := S.speedDev) THEN
  Warn := UT_F_SPEED_DEV;
END_IF;
UT_MOTOR_VSD_CHECK := Fault = UT_F_NONE AND Hand = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION