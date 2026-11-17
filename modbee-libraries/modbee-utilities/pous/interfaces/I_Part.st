(* A part (a protection, an add-on) that its owner calls every scan. *)

INTERFACE I_Part


METHOD Evaluate : E_PartAction
  VAR_INPUT
    bRunning : BOOL;             // the owner is running (its run command)
    bResetWanted : BOOL;         // the owner's reset request this scan
    bMasked : BOOL;              // the owner's start mask is on (checks set to mask at start ignore their cause)
  END_VAR
  VAR_OUTPUT
    eErrorId : E_UtError;        // the error this part stands for (when it warns or trips)
  END_VAR
END_METHOD
METHOD SetNext
  VAR_INPUT
    ipNext : I_Part;
  END_VAR
END_METHOD
METHOD GetNext : I_Part
END_METHOD

END_INTERFACE