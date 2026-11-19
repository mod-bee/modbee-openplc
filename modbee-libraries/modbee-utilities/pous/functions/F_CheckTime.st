(* F_CheckTime — checks a TIME setting: within tLowestAllowed..tHighestAllowed (BelowMin / AboveMax, LimitsBad when
the limits are the wrong way round). Returns None when it is good. *)

FUNCTION F_CheckTime : E_UtError
  VAR_INPUT
    tValue : TIME; (* the value to check *)
    tLowestAllowed : TIME; (* lowest value allowed *)
    tHighestAllowed : TIME; (* highest value allowed *)
  END_VAR

IF tLowestAllowed > tHighestAllowed THEN
  F_CheckTime := E_UtError.LimitsBad;
ELSIF tValue < tLowestAllowed THEN
  F_CheckTime := E_UtError.BelowMin;
ELSIF tValue > tHighestAllowed THEN
  F_CheckTime := E_UtError.AboveMax;
ELSE
  F_CheckTime := E_UtError.None;
END_IF;

END_FUNCTION