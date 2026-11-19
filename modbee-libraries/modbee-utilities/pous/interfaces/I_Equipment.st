(* __SYSTEM.IQueryInterface: __QUERYINTERFACE reaches I_LocalChoice through it (CODESYS needs both to derive from it) *)

INTERFACE I_Equipment EXTENDS I_PartOwner, __SYSTEM


.IQueryInterface
  METHOD Request : E_UtError
    VAR_INPUT
      bRun : BOOL;                 // run (open) wanted
      bHoldOff : BOOL;                // held off, still linked
      fSpeedSetpointPct : REAL := -1.0;       // speed / position wanted, < 0 = the device's own
      bOverflowUrgent : BOOL;              // an overflow call: a part's start hold (starts limit ...) does not hold it
    END_VAR
  END_METHOD
  METHOD Command
    VAR_INPUT
      eCommand : E_EquipCmd;           // as the record's commands: applied in the block's next cycle
    END_VAR
  END_METHOD
  PROPERTY eActMode : E_Mode    // the mode it is in now
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsRunning : BOOL    // running now
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsReady : BOOL    // could start now if asked
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsAvailable : BOOL    // in Auto, not tripped, not interlocked
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsAuto : BOOL    // in Auto now
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsFaulted : BOOL    // a trip or setting fault is active
    GET
    END_GET
  END_PROPERTY
  PROPERTY eActError : E_UtError    // the error shown now
    GET
    END_GET
  END_PROPERTY
  PROPERTY eActStopReason : E_StopReason    // why it last stopped
    GET
    END_GET
  END_PROPERTY
  PROPERTY fActRunHours : REAL     // run hours (0 where not counted): rotation by hours
    GET
    END_GET
  END_PROPERTY

END_INTERFACE