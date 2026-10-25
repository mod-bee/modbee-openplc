FUNCTION UT_ZONE_CHECK : BOOL
  VAR_IN_OUT
    S : UT_ZONE_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR


Id := UT_F_NONE;
IF NOT (S.endBy = UT_ZE_AUTO OR S.endBy = UT_ZE_TIME OR S.endBy = UT_ZE_VOLUME OR S.endBy = UT_ZE_FIRST
        OR S.endBy = UT_ZE_UNTIL_STOP) OR S.runTime < T#0s OR NOT (S.volume >= 0.0 AND S.volume <= 1.0E15)
   OR S.cycles < 1 OR S.cycles > 100 OR S.soakTime < T#0s THEN
  Id := UT_F_ZONE_SETTING;
ELSIF NOT (S.sp >= 0.0 AND S.sp <= 3.4E38 AND S.minFlow >= 0.0 AND S.maxFlow >= 0.0 AND S.maxFlow <= 3.4E38)
      OR (S.maxFlow > 0.0 AND S.maxFlow <= S.minFlow) OR NOT UT_PROT_OK(P := S.flowCheck) THEN
  Id := UT_F_ZONE_SETTING;
END_IF;
UT_ZONE_CHECK := Id = UT_F_NONE;

END_FUNCTION