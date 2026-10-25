FUNCTION UT_REPORT_CHECK : BOOL
  VAR_IN_OUT
    S : UT_REPORT_SET;
  END_VAR

UT_REPORT_CHECK := S.deadband >= 0.0 AND S.deadband <= 3.4E38 AND S.span >= 0.0 AND S.span <= 3.4E38
                   AND S.resolution >= 0.0 AND S.resolution <= 3.4E38 AND S.minInterval >= T#0s AND S.heartbeat >= T#0s
                   AND (S.deadbandMode = UT_DB_ABS OR S.deadbandMode = UT_DB_PCT_VALUE
                        OR (S.deadbandMode = UT_DB_PCT_SPAN AND S.span > 0.0));

END_FUNCTION