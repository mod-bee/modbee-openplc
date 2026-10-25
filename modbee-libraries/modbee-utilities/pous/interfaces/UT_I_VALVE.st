(* Any valve *)

INTERFACE UT_I_VALVE EXTENDS UT_I_STATUS


METHOD Request : BOOL            // the owner's command each scan, acts only in Auto. FALSE = refused
  VAR_INPUT
    ReqOpen : BOOL;              // FALSE = rest position
    ReqPos : REAL;               // 3POS 1..3, FLOAT / MOD %; NaN = the valve's own Auto choice / full open
    Owner : STRING(12);          // the owner's tag
  END_VAR
END_METHOD
METHOD IsOpenNow : BOOL             // by switch / feedback, or after its open time; never at the command
END_METHOD
METHOD IsClosedNow : BOOL
END_METHOD
METHOD IsConfirmed : BOOL        // position from a switch / feedback, not from time
END_METHOD
METHOD GetPosition : REAL           // % open; -1 unknown / moving
END_METHOD
METHOD AtPosition : BOOL         // 3POS: at N; others: 0 = closed, 1 = open
  VAR_INPUT
    N : INT;
  END_VAR
END_METHOD
METHOD IsMoving : BOOL
END_METHOD
METHOD TimeToOpen : TIME         // time left of the move
END_METHOD
METHOD IsReady : BOOL            // Auto, no trip, interlock / permissive made, actuator in Remote
END_METHOD
METHOD IsAuto : BOOL
END_METHOD

END_INTERFACE