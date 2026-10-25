(* Read-only status, the base of the others *)

INTERFACE UT_I_STATUS


METHOD StatusCode : UT_STATUS
END_METHOD
METHOD FaultId : UT_FAULT        // the fault / warning shown
END_METHOD
METHOD StopReason : UT_STOP      // why it last stopped (UT_STOP_NONE: blocks that do not run)
END_METHOD
METHOD HasFault : BOOL           // a trip or config fault is on
END_METHOD
METHOD HasWarning : BOOL
END_METHOD
METHOD IsLocked : BOOL           // needs a reset
END_METHOD
METHOD IsFitted : BOOL           // the thing is on this site (FALSE: skip what depends on it, no fault)
END_METHOD
METHOD Ne107 : UT_NE107          // NAMUR NE107 category
END_METHOD

END_INTERFACE