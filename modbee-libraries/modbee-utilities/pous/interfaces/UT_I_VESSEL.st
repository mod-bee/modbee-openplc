(* A vessel; Value = level *)

INTERFACE UT_I_VESSEL EXTENDS UT_I_MEAS


METHOD GetVolume : REAL             // in the vessel's volume unit
END_METHOD
METHOD GetArea : REAL               // water surface at the current level, m2
END_METHOD
METHOD GetPercent : REAL            // % of the total volume
END_METHOD

END_INTERFACE