(* Anything parts can be added to: equipment and process blocks. *)

INTERFACE I_PartOwner


METHOD AddPart
  VAR_INPUT
    ipPart : I_Part;    // the part to add (a protection, a check)
  END_VAR
END_METHOD

END_INTERFACE