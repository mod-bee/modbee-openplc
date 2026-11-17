(* A vessel: a measurement (its level) plus what it holds. *)

INTERFACE I_Vessel EXTENDS I_Measurement


PROPERTY fActVolume : REAL
  GET
  END_GET
END_PROPERTY
PROPERTY fActPercent : REAL       // of the full volume
  GET
  END_GET
END_PROPERTY
PROPERTY fFullVolume : REAL
  GET
  END_GET
END_PROPERTY

END_INTERFACE