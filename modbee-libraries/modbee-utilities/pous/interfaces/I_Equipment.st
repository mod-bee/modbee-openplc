(* __SYSTEM.IQueryInterface: __QUERYINTERFACE reaches I_LocalChoice through it (CODESYS needs both to derive from it) *)

INTERFACE I_Equipment EXTENDS I_PartOwner, __SYSTEM


.IQueryInterface
  METHOD Request : E_UtError
    VAR_INPUT
      bRun : BOOL;                 // run (open) wanted
      bHold : BOOL;                // held off, still linked
      fSpeed : REAL := -1.0;       // speed / position wanted, < 0 = the device's own
      bUrgent : BOOL;              // an overflow call: a part's start hold (starts limit ...) does not hold it
    END_VAR
  END_METHOD
  METHOD Command
    VAR_INPUT
      eCmd : E_EquipCmd;           // as the record's commands: applied in the block's next cycle
    END_VAR
  END_METHOD
  PROPERTY eActMode : E_Mode
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsRunning : BOOL
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsReady : BOOL
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsAvailable : BOOL
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsAuto : BOOL
    GET
    END_GET
  END_PROPERTY
  PROPERTY bIsFaulted : BOOL
    GET
    END_GET
  END_PROPERTY
  PROPERTY eActError : E_UtError
    GET
    END_GET
  END_PROPERTY
  PROPERTY eActStopReason : E_StopReason
    GET
    END_GET
  END_PROPERTY
  PROPERTY fActRunHours : REAL     // run hours (0 where not counted): rotation by hours
    GET
    END_GET
  END_PROPERTY

END_INTERFACE