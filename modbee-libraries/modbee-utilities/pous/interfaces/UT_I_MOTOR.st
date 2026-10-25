(* Anything with a motor *)

INTERFACE UT_I_MOTOR EXTENDS UT_I_STATUS


METHOD Request : BOOL            // the owner's command, once every scan; acts only in Auto. FALSE = refused
  VAR_INPUT
    ReqRun : BOOL;               // run wanted
    Hold : BOOL;                 // stop now (the owner's trip)
    ReqSpeed : REAL;             // % (NaN = the motor's own Auto choice)
    Owner : STRING(12);          // the owner's tag (By is an IEC keyword)
  END_VAR
END_METHOD
METHOD IsRunning : BOOL          // run confirmed
END_METHOD
METHOD IsReady : BOOL            // Auto, would start now
END_METHOD
METHOD IsAvailable : BOOL        // as IsReady, may still be in its restart wait
END_METHOD
METHOD RestartIn : TIME          // time until it may start (0 = now)
END_METHOD
METHOD IsAuto : BOOL
END_METHOD
METHOD IsHand : BOOL
END_METHOD
METHOD IsVsd : BOOL              // speed can be requested
END_METHOD
METHOD GetSpeed : REAL              // actual speed %
END_METHOD
METHOD GetCurrent : REAL            // A; NaN = not measured
END_METHOD
METHOD RunHours : LREAL          // lifetime run hours (kept)
END_METHOD

END_INTERFACE