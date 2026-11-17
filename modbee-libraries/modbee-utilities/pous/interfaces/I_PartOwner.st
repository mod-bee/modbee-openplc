(* Anything parts can be added to: equipment and process blocks. *)

INTERFACE I_PartOwner


METHOD AddPart
  VAR_INPUT
    ipPart : I_Part;
  END_VAR
END_METHOD

END_INTERFACE