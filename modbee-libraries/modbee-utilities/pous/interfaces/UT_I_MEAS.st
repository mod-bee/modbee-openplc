(* Any measurement *)

INTERFACE UT_I_MEAS EXTENDS UT_I_STATUS


METHOD GetValue : REAL              // engineering value; NaN when none (switches) or not Good
END_METHOD
METHOD GoodNow : BOOL               // usable now
END_METHOD
METHOD HasValue : BOOL           // a continuous value exists
END_METHOD
METHOD HasBand : BOOL            // that band (switch) is set up
  VAR_INPUT
    Band : UT_LEVEL_ID;
  END_VAR
END_METHOD
METHOD IsHiHiNow : BOOL
END_METHOD
METHOD IsHiNow : BOOL               // also at HH
END_METHOD
METHOD IsLoNow : BOOL               // also at LL
END_METHOD
METHOD IsLoLoNow : BOOL
END_METHOD
METHOD Unit : UT_UNIT
END_METHOD

END_INTERFACE