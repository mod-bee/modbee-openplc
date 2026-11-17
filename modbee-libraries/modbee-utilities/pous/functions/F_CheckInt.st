FUNCTION F_CheckInt : E_UtError
  VAR_INPUT
    nValue : DINT;
    nMin : DINT;
    nMax : DINT;
  END_VAR

IF nMin > nMax THEN
  F_CheckInt := E_UtError.LimitsBad;
ELSIF nValue < nMin THEN
  F_CheckInt := E_UtError.BelowMin;
ELSIF nValue > nMax THEN
  F_CheckInt := E_UtError.AboveMax;
ELSE
  F_CheckInt := E_UtError.None;
END_IF;

END_FUNCTION