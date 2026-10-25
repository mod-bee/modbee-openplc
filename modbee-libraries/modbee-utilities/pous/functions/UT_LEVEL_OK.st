FUNCTION UT_LEVEL_OK : BOOL
  VAR_IN_OUT
    L : UT_LEVEL;
  END_VAR

UT_LEVEL_OK := (L.response = UT_RESP_OFF OR L.response = UT_RESP_WARN OR L.response = UT_RESP_TRIP
                OR L.response = UT_RESP_SIGNAL)
               AND (L.reset = UT_RST_AUTO OR L.reset = UT_RST_RETRY OR L.reset = UT_RST_MANUAL)
               AND L.delay >= T#0s AND L.recover >= T#0s AND L.maxRetries >= 0
               AND ABS(L.sp) <= 3.4E38 AND L.deadband >= 0.0 AND L.deadband <= 3.4E38;

END_FUNCTION