FUNCTION F_CheckTime : E_UtError
  VAR_INPUT
    tValue : TIME;
    tMin : TIME;
    tMax : TIME;
  END_VAR

IF tMin > tMax THEN
  F_CheckTime := E_UtError.LimitsBad;
ELSIF tValue < tMin THEN
  F_CheckTime := E_UtError.BelowMin;
ELSIF tValue > tMax THEN
  F_CheckTime := E_UtError.AboveMax;
ELSE
  F_CheckTime := E_UtError.None;
END_IF;

END_FUNCTION