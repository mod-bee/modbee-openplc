FUNCTION F_CheckLreal : E_UtError
  VAR_INPUT
    fValue : LREAL;
    fMin : LREAL;
    fMax : LREAL;
  END_VAR

IF NOT (fValue = fValue) OR fValue > LREAL#1.7E308 OR fValue < LREAL#-1.7E308 THEN
  F_CheckLreal := E_UtError.ValueBad;
ELSIF fMin > fMax THEN
  F_CheckLreal := E_UtError.LimitsBad;
ELSIF fValue < fMin THEN
  F_CheckLreal := E_UtError.BelowMin;
ELSIF fValue > fMax THEN
  F_CheckLreal := E_UtError.AboveMax;
ELSE
  F_CheckLreal := E_UtError.None;
END_IF;

END_FUNCTION