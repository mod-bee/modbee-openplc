(* The system mode block, read by every block that takes ipSystem. *)

INTERFACE I_SystemMode


PROPERTY bSystemAuto : BOOL
  GET
  END_GET
END_PROPERTY
PROPERTY bSystemOff : BOOL
  GET
  END_GET
END_PROPERTY
PROPERTY bSystemHold : BOOL
  GET
  END_GET
END_PROPERTY
PROPERTY bSystemReset : BOOL
  GET
  END_GET
END_PROPERTY

END_INTERFACE