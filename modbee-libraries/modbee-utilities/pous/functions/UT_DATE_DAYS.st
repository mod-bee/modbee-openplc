(* Days from 1970-01-01 to a date (Gregorian calendar). A month outside
1..12 rolls into the year before or after (month 13 = January next year) *)

FUNCTION UT_DATE_DAYS : DINT
  VAR_INPUT
    Year : INT := 1970;
    Month : INT := 1; (* 1..12 *)
    Day : INT := 1; (* 1..31 *)
  END_VAR
  VAR
    y : DINT;
    m : DINT;
    era : DINT;
    yoe : DINT; (* year of the 400-year era *)
    doy : DINT; (* day of the year, from 1 March *)
  END_VAR


y := INT_TO_DINT(Year);
m := INT_TO_DINT(Month) - 1;     (* 0..11 *)
IF m < 0 THEN
  y := y - 1 + (m + 1) / 12;
  m := m MOD 12;
  IF m < 0 THEN
    m := m + 12;
  END_IF;
ELSE
  y := y + m / 12;
  m := m MOD 12;
END_IF;
(* a year from March: January and February belong to the year before *)
IF m < 2 THEN
  y := y - 1;
  m := m + 10;
ELSE
  m := m - 2;
END_IF;
IF y >= 0 THEN
  era := y / 400;
ELSE
  era := (y - 399) / 400;
END_IF;
yoe := y - era * 400;
doy := (153 * m + 2) / 5 + INT_TO_DINT(Day) - 1;
UT_DATE_DAYS := era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;

END_FUNCTION