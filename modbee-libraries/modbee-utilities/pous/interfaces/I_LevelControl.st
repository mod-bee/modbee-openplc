(* A level control: what its parts read. *)

INTERFACE I_LevelControl EXTENDS I_PartOwner


PROPERTY fActHighHighLevel : REAL    // the high-high level in use
  GET
  END_GET
END_PROPERTY

END_INTERFACE