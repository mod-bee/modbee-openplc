FUNCTION UT_MIXER_CHECK : BOOL
  VAR_IN_OUT
    S : UT_MIXER_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR


Id := UT_F_NONE;
IF S.cycle AND (S.onTime <= T#0s OR S.offTime <= T#0s) THEN
  Id := UT_F_TIMED_ON_OFF;
ELSIF S.preRunTime < T#0s OR S.postRunTime < T#0s THEN
  Id := UT_F_PRE_POST_RUN;
ELSIF NOT (ABS(S.minLevel) <= 3.4E38 AND S.minDeadband >= 0.0 AND S.minDeadband <= 3.4E38)
      OR NOT UT_PROT_OK(P := S.lowLevel) THEN
  Id := UT_F_SETTING;
END_IF;
UT_MIXER_CHECK := Id = UT_F_NONE;

END_FUNCTION