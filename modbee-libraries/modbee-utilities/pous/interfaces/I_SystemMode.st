(* The system mode block, read by every block that takes ipSystem. *)

INTERFACE I_SystemMode


PROPERTY bSystemAuto : BOOL    // the plant is in Auto
  GET
  END_GET
END_PROPERTY
PROPERTY bSystemOff : BOOL    // the plant is Off
  GET
  END_GET
END_PROPERTY
PROPERTY bSystemHold : BOOL    // the power-up hold is on: automatic starts wait
  GET
  END_GET
END_PROPERTY
PROPERTY bSystemReset : BOOL    // the plant reset this scan
  GET
  END_GET
END_PROPERTY

END_INTERFACE