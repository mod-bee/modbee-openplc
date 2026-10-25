(* Settings checks: TRUE when a protection / level / measurement record is usable *)

FUNCTION UT_PROT_OK : BOOL
  VAR_IN_OUT
    P : UT_PROTECTION;
  END_VAR

UT_PROT_OK := (P.response = UT_RESP_OFF OR P.response = UT_RESP_WARN OR P.response = UT_RESP_TRIP
               OR P.response = UT_RESP_SIGNAL)
              AND (P.reset = UT_RST_AUTO OR P.reset = UT_RST_RETRY OR P.reset = UT_RST_MANUAL)
              AND P.delay >= T#0s AND P.recover >= T#0s AND P.maxRetries >= 0;

END_FUNCTION