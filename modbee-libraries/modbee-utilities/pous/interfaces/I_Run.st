(* A run: what its parts read. *)

INTERFACE I_Run EXTENDS I_PartOwner


PROPERTY bIsBusy : BOOL    // a run is active now
  GET
  END_GET
END_PROPERTY
PROPERTY tActElapsed : TIME    // run time counted in this run
  GET
  END_GET
END_PROPERTY
PROPERTY eActStopReason : E_StopReason   // why the last run ended (None while one runs)
  GET
  END_GET
END_PROPERTY
PROPERTY nActRunId : UDINT        // the run's number: it changes at every start, a restart too (a new run)
  GET
  END_GET
END_PROPERTY

END_INTERFACE