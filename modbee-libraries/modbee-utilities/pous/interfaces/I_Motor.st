(* A motor: equipment with a speed (FB_Motor and its variants; FB_Pump drives one, FB_MotorJog jogs one). *)

INTERFACE I_Motor EXTENDS I_Equipment


PROPERTY fActSpeedPct : REAL    // the speed now, % (0 when stopped)
  GET
  END_GET
END_PROPERTY

END_INTERFACE