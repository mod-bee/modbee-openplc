(* F_CheckInt — checks a whole-number setting: within nLowestAllowed..nHighestAllowed (BelowMin / AboveMax,
LimitsBad when the limits are the wrong way round). Returns None when it is good. *)

FUNCTION F_CheckInt : E_UtError
  VAR_INPUT
    nValue : DINT; (* the value to check *)
    nLowestAllowed : DINT; (* lowest value allowed *)
    nHighestAllowed : DINT; (* highest value allowed *)
  END_VAR

IF nLowestAllowed > nHighestAllowed THEN
  F_CheckInt := E_UtError.LimitsBad;
ELSIF nValue < nLowestAllowed THEN
  F_CheckInt := E_UtError.BelowMin;
ELSIF nValue > nHighestAllowed THEN
  F_CheckInt := E_UtError.AboveMax;
ELSE
  F_CheckInt := E_UtError.None;
END_IF;

END_FUNCTION