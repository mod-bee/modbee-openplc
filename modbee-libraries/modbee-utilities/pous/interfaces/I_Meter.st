(* A meter: a measurement (its rate) plus a total (pulse meter, level meter ...). As a measurement: fActValue is
the rate (per hour, as fActRate), eUnit the rate's unit (its total's unit per hour, None when not set), no
bands; so a level check or a speed loop can take a meter's flow. *)

INTERFACE I_Meter EXTENDS I_Measurement


PROPERTY fActTotal : LREAL        // the lifetime total in its unit
  GET
  END_GET
END_PROPERTY
PROPERTY fActRate : REAL          // per hour
  GET
  END_GET
END_PROPERTY

END_INTERFACE