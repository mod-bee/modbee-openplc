(* FB_TimeSplit — a TIME split into days, hours, minutes, seconds and
milliseconds, plus the total in hours and a text for HMIs.

nHours are 0-23, minutes and seconds 0-59, milliseconds 0-999; whatever is
left over is in nDays. sText is 'HH:MM:SS' under a day and 'Nd HH:MM:SS' from
a day up, zero padded, e.g. '1d 02:03:04'.

sShort is F_TimeText's form ('2 d 3 h', '1 h 20 m', '42 m 10 s',
'35 s', rounded up to the smaller unit), the one every status text uses.

A negative TIME is split by its size: the parts are the same as for the
positive time, fTotalHours is negative and sText and sShort start with '-'.
Anything below a millisecond is dropped. *)

FUNCTION_BLOCK FB_TimeSplit
  VAR_INPUT
    tIn : TIME; (* any duration *)
  END_VAR
  VAR_OUTPUT
    nDays : UDINT;
    nHours : UDINT; (* 0-23 *)
    nMinutes : UDINT; (* 0-59 *)
    nSeconds : UDINT; (* 0-59 *)
    nMillis : UDINT; (* 0-999 *)
    fTotalHours : REAL; (* the whole duration in hours *)
    sText : STRING(20); (* e.g. '1d 02:03:04' *)
    sShort : STRING(16); (* the two largest units, as status texts use: '1 h 20 m', '42 m 10 s', '35 s' *)
  END_VAR
  VAR
    nMs : LINT; (* the size of tIn, in milliseconds *)
    bNeg : BOOL;
    nRest : LINT;
    sPart : STRING(20);
  END_VAR


nMs := TIME_TO_LINT(tIn);
bNeg := nMs < 0;
IF bNeg THEN
  nMs := -nMs;
END_IF;

nMillis := LINT_TO_UDINT(nMs MOD 1000);
nRest := nMs / 1000;
nSeconds := LINT_TO_UDINT(nRest MOD 60);
nRest := nRest / 60;
nMinutes := LINT_TO_UDINT(nRest MOD 60);
nRest := nRest / 60;
nHours := LINT_TO_UDINT(nRest MOD 24);
nDays := LINT_TO_UDINT(nRest / 24);

fTotalHours := LINT_TO_REAL(nMs) / 3600000.0;
IF bNeg THEN
  fTotalHours := -fTotalHours;
END_IF;

(* text *)
IF bNeg THEN
  sText := '-';
ELSE
  sText := '';
END_IF;
IF nDays > 0 THEN
  sText := CONCAT(sText, CONCAT(UDINT_TO_STRING(nDays), 'd '));
END_IF;
sPart := UDINT_TO_STRING(nHours);
IF nHours < 10 THEN
  sPart := CONCAT('0', sPart);
END_IF;
sText := CONCAT(sText, CONCAT(sPart, ':'));
sPart := UDINT_TO_STRING(nMinutes);
IF nMinutes < 10 THEN
  sPart := CONCAT('0', sPart);
END_IF;
sText := CONCAT(sText, CONCAT(sPart, ':'));
sPart := UDINT_TO_STRING(nSeconds);
IF nSeconds < 10 THEN
  sPart := CONCAT('0', sPart);
END_IF;
sText := CONCAT(sText, sPart);

IF bNeg THEN
  sShort := CONCAT('-', F_TimeText(LINT_TO_TIME(nMs)));
ELSE
  sShort := F_TimeText(tIn);
END_IF;

END_FUNCTION_BLOCK