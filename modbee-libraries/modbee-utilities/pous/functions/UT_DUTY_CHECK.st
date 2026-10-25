(* The duty group's settings for N units: TRUE when usable; Id = the first that is not *)

FUNCTION UT_DUTY_CHECK : BOOL
  VAR_INPUT
    N : INT;
  END_VAR
  VAR_IN_OUT
    S : UT_DUTY_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR


IF NOT UT_GROUP_CHECK(N := N, Set := S.group, Id => Id) THEN
  ;
ELSIF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
           OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)
           OR (S.run.style = UT_RS_PULSE_TIMER AND S.run.pulseTime > T#0s)) THEN
  Id := UT_F_RUN_STYLE;
END_IF;
UT_DUTY_CHECK := Id = UT_F_NONE;

END_FUNCTION