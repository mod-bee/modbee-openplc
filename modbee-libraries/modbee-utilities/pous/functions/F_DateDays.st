(* Days from 1970-01-01 to a date (Gregorian calendar). A month outside
1..12 rolls into the year before or after (month 13 = January next year) *)

FUNCTION F_DateDays : DINT
  VAR_INPUT
    nYear : INT := 1970; (* the year *)
    nMonth : INT := 1; (* 1..12 *)
    nDay : INT := 1; (* 1..31 *)
  END_VAR
  VAR
    nY : DINT;
    nM : DINT;
    nEra : DINT;
    nYoe : DINT; (* year of the 400-year era *)
    nDoy : DINT; (* day of the year, from 1 March *)
  END_VAR


nY := INT_TO_DINT(nYear);
nM := INT_TO_DINT(nMonth) - 1;     (* 0..11 *)
IF nM < 0 THEN
  nY := nY - 1 + (nM + 1) / 12;
  nM := nM MOD 12;
  IF nM < 0 THEN
    nM := nM + 12;
  END_IF;
ELSE
  nY := nY + nM / 12;
  nM := nM MOD 12;
END_IF;
(* a year from March: January and February belong to the year before *)
IF nM < 2 THEN
  nY := nY - 1;
  nM := nM + 10;
ELSE
  nM := nM - 2;
END_IF;
IF nY >= 0 THEN
  nEra := nY / 400;
ELSE
  nEra := (nY - 399) / 400;
END_IF;
nYoe := nY - nEra * 400;
nDoy := (153 * nM + 2) / 5 + INT_TO_DINT(nDay) - 1;
F_DateDays := nEra * 146097 + nYoe * 365 + nYoe / 4 - nYoe / 100 + nDoy - 719468;

END_FUNCTION