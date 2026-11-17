(* A meter: a total and a rate (pulse meter, level meter ...). *)

INTERFACE I_Meter


PROPERTY fActTotal : LREAL        // the lifetime total in its unit
  GET
  END_GET
END_PROPERTY
PROPERTY fActRate : REAL          // per hour
  GET
  END_GET
END_PROPERTY
PROPERTY bIsGood : BOOL
  GET
  END_GET
END_PROPERTY

END_INTERFACE