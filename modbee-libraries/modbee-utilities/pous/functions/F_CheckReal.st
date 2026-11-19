(* F_CheckReal — checks a REAL setting before it is used: a number (not NaN or infinite), within
fLowestAllowed..fHighestAllowed and, when asked, above fMustBeAbove / below fMustBeBelow (a related setting).
Returns the first problem as an E_UtError (ValueBad, LimitsBad, BelowMin, AboveMax, NotAbove, NotBelow), None when
it is good. *)

FUNCTION F_CheckReal : E_UtError
  VAR_INPUT
    fValue : REAL; (* the value to check *)
    fLowestAllowed : REAL := REAL#-3.4E38; (* lowest value allowed *)
    fHighestAllowed : REAL := REAL#3.4E38; (* highest value allowed *)
    bCheckAbove : BOOL; (* also check it is above fMustBeAbove *)
    fMustBeAbove : REAL; (* must be above this related setting (bCheckAbove) *)
    bCheckBelow : BOOL; (* also check it is below fMustBeBelow *)
    fMustBeBelow : REAL; (* must be below this related setting (bCheckBelow) *)
  END_VAR

IF NOT (fValue = fValue) OR fValue > REAL#3.4E38 OR fValue < REAL#-3.4E38 THEN
  F_CheckReal := E_UtError.ValueBad;
ELSIF fLowestAllowed > fHighestAllowed THEN
  F_CheckReal := E_UtError.LimitsBad;
ELSIF fValue < fLowestAllowed THEN
  F_CheckReal := E_UtError.BelowMin;
ELSIF fValue > fHighestAllowed THEN
  F_CheckReal := E_UtError.AboveMax;
ELSIF bCheckAbove AND NOT (fValue > fMustBeAbove) THEN
  F_CheckReal := E_UtError.NotAbove;
ELSIF bCheckBelow AND NOT (fValue < fMustBeBelow) THEN
  F_CheckReal := E_UtError.NotBelow;
ELSE
  F_CheckReal := E_UtError.None;
END_IF;

END_FUNCTION