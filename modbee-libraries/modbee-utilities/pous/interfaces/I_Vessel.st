(* A vessel: a measurement (its level) plus what it holds. *)

INTERFACE I_Vessel EXTENDS I_Measurement


PROPERTY fActVolume : REAL    // working volume now
  GET
  END_GET
END_PROPERTY
PROPERTY fActVolumePct : REAL       // of the full volume
  GET
  END_GET
END_PROPERTY
PROPERTY fFullVolume : REAL    // working volume when full
  GET
  END_GET
END_PROPERTY

END_INTERFACE