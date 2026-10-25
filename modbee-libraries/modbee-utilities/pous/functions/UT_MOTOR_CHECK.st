(* The motor's settings: the first that refuses every run (Fault), refuses Hand
(Hand), or only warns (Warn). TRUE when all are usable. *)

FUNCTION UT_MOTOR_CHECK : BOOL
  VAR_IN_OUT
    S : UT_MOTOR_SET;
  END_VAR
  VAR_OUTPUT
    Fault : UT_FAULT;
    Hand : UT_FAULT;
    Warn : UT_FAULT;
  END_VAR
  VAR
    curOpt : BOOL;
  END_VAR


Fault := UT_F_NONE;
Hand := UT_F_NONE;
Warn := UT_F_NONE;
curOpt := S.currentHigh.response <> UT_RESP_OFF OR S.currentLow.response <> UT_RESP_OFF OR S.runByCurrent
          OR (S.startTooLong.response <> UT_RESP_OFF AND NOT S.useTopOfRamp);
IF NOT (S.modeSource = UT_SRC_HMI OR S.modeSource = UT_SRC_SWITCH OR S.modeSource = UT_SRC_REMOTE) THEN
  Fault := UT_F_MODE_SOURCE;
ELSIF NOT (S.fullLoadCurrent >= 0.0 AND S.fullLoadCurrent <= 3.4E38) THEN
  Fault := UT_F_FLC;
ELSIF curOpt AND S.fullLoadCurrent = 0.0 THEN
  Fault := UT_F_CURRENT_NEEDS_FLC;
ELSIF curOpt AND S.currentStartMask < T#0s THEN
  Fault := UT_F_START_MASK;
ELSIF S.runByCurrent AND NOT (S.runCurrentPct > 0.0 AND S.runCurrentPct <= 100.0) THEN
  Fault := UT_F_RUN_CURRENT;
ELSIF S.restartDelay < T#0s THEN
  Fault := UT_F_RESTART_DELAY;
ELSIF S.stopTime < T#0s THEN
  Fault := UT_F_STOP_TIME;
ELSIF S.startTooLong.response <> UT_RESP_OFF AND NOT S.useTopOfRamp AND NOT (S.startTooLong.sp > 0.0 AND S.startTooLong.sp <= 3.4E38) THEN
  Fault := UT_F_START_TOO_LONG;
ELSIF (S.currentHigh.response <> UT_RESP_OFF AND NOT (S.currentHigh.sp > 0.0 AND S.currentHigh.sp <= 3.4E38))
      OR NOT (S.currentHigh.deadband >= 0.0 AND S.currentHigh.deadband <= 3.4E38) THEN
  Fault := UT_F_CURRENT_HIGH;
ELSIF (S.currentLow.response <> UT_RESP_OFF AND NOT (S.currentLow.sp > 0.0 AND S.currentLow.sp <= 3.4E38))
      OR NOT (S.currentLow.deadband >= 0.0 AND S.currentLow.deadband <= 3.4E38) THEN
  Fault := UT_F_CURRENT_LOW;
ELSIF S.currentHigh.response <> UT_RESP_OFF AND S.currentLow.response <> UT_RESP_OFF
      AND NOT (S.currentHigh.sp > S.currentLow.sp) THEN
  Fault := UT_F_SP_ORDER;
END_IF;
IF S.handMaxRun < T#0s OR S.jogMax < T#0s THEN
  Hand := UT_F_HAND_MAX_RUN;
END_IF;
IF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
        OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)) THEN
  Warn := UT_F_RUN_STYLE;        (* refuses Auto (not linked): the run input reports it too *)
ELSIF S.currentStartMask < T#0s THEN
  Warn := UT_F_START_MASK;
ELSIF S.retryWindow < T#0s THEN
  Warn := UT_F_RETRY_WINDOW;
ELSIF NOT (S.extReason = UT_F_EXTERNAL OR S.extReason = UT_F_SUPPLY OR S.extReason = UT_F_SEAL_LEAK
           OR S.extReason = UT_F_MOTOR_HOT OR S.extReason = UT_F_DRIVE) THEN
  Warn := UT_F_EXT_REASON;
ELSIF NOT (S.mode = UT_MODE_OFF OR S.mode = UT_MODE_HAND OR S.mode = UT_MODE_AUTO OR S.mode = UT_MODE_OOS) THEN
  Warn := UT_F_MODE_CHOICE;
ELSIF NOT (S.powerUp = UT_PU_LAST OR S.powerUp = UT_PU_OFF) THEN
  Warn := UT_F_POWERUP;
ELSIF NOT UT_PROT_OK(P := S.overload) THEN Warn := UT_F_OVERLOAD;
ELSIF NOT UT_PROT_OK(P := S.thermistor) THEN Warn := UT_F_MOTOR_HOT;
ELSIF NOT UT_PROT_OK(P := S.noFeedback) THEN Warn := UT_F_NO_FEEDBACK;
ELSIF NOT UT_PROT_OK(P := S.feedbackLost) THEN Warn := UT_F_FEEDBACK_LOST;
ELSIF NOT UT_PROT_OK(P := S.stuck) THEN Warn := UT_F_WELDED;
ELSIF NOT UT_PROT_OK(P := S.drive) THEN Warn := UT_F_DRIVE;
ELSIF NOT UT_PROT_OK(P := S.extFault) THEN Warn := UT_F_EXTERNAL;
ELSIF NOT UT_PROT_OK(P := S.currentBad) THEN Warn := UT_F_CURRENT_BAD;
ELSIF NOT UT_LEVEL_OK(L := S.currentHigh) THEN Warn := UT_F_CURRENT_HIGH;
ELSIF NOT UT_LEVEL_OK(L := S.currentLow) THEN Warn := UT_F_CURRENT_LOW;
ELSIF NOT UT_LEVEL_OK(L := S.startTooLong) THEN Warn := UT_F_START_TOO_LONG;
END_IF;
UT_MOTOR_CHECK := Fault = UT_F_NONE AND Hand = UT_F_NONE AND Warn = UT_F_NONE;

END_FUNCTION