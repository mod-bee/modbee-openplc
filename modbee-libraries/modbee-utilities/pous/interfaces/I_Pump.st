(* A pump: its role in a station and its capacity (DESIGN-0.2.md section 2). *)

INTERFACE I_Pump EXTENDS I_Motor


PROPERTY eActRole : E_PumpRole
  GET
  END_GET
END_PROPERTY
PROPERTY fActCapacity : REAL     // flow at full speed (0 = not known)
  GET
  END_GET
END_PROPERTY

END_INTERFACE