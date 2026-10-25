FUNCTION UT_PROT_EXT_CLEAR : BOOL
  VAR_IN_OUT
    Sum : UT_PROT_EXT_SUM;
  END_VAR

Sum.trip := 0;
Sum.warn := 0;
Sum.tripped := 0;
Sum.cfgId := UT_F_NONE;
Sum.resetDone := FALSE;
Sum.tripId := UT_F_NONE;
Sum.tripStatus := UT_ST_IDLE;
Sum.tripTime := T#0s;
Sum.warnId := UT_F_NONE;
Sum.locked := FALSE;
UT_PROT_EXT_CLEAR := TRUE;

END_FUNCTION