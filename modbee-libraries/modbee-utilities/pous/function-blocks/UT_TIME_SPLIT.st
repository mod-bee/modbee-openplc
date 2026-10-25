(* UT_TIME_SPLIT — a TIME split into days, hours, minutes, seconds and
milliseconds, plus the total in hours and a text for HMIs.

Hours are 0-23, minutes and seconds 0-59, milliseconds 0-999; whatever is
left over is in Days. Text is 'HH:MM:SS' under a day and 'Nd HH:MM:SS' from
a day up, zero padded, e.g. '1d 02:03:04'.

Short is UT_TIME_TEXT's form ('2 d 3 h', '1 h 20 m', '42 m 10 s',
'35 s', rounded up to the smaller unit), the one every status text uses.

A negative TIME is split by its size: the parts are the same as for the
positive time, TotalHours is negative and Text and Short start with '-'.
Anything below a millisecond is dropped. *)

FUNCTION_BLOCK UT_TIME_SPLIT
  VAR_INPUT
    In : TIME; (* any duration *)
  END_VAR
  VAR_OUTPUT
    Days : UDINT;
    Hours : UDINT; (* 0-23 *)
    Minutes : UDINT; (* 0-59 *)
    Seconds : UDINT; (* 0-59 *)
    Millis : UDINT; (* 0-999 *)
    TotalHours : REAL; (* the whole duration in hours *)
    Text : STRING(20); (* e.g. '1d 02:03:04' *)
    Short : STRING(16); (* the two largest units, as status texts use: '1 h 20 m', '42 m 10 s', '35 s' *)
  END_VAR
  VAR
    ms : LINT; (* the size of In, in milliseconds *)
    neg : BOOL;
    rest : LINT;
    part : STRING(20);
  END_VAR


ms := TIME_TO_LINT(In);
neg := ms < 0;
IF neg THEN
  ms := -ms;
END_IF;

Millis := LINT_TO_UDINT(ms MOD 1000);
rest := ms / 1000;
Seconds := LINT_TO_UDINT(rest MOD 60);
rest := rest / 60;
Minutes := LINT_TO_UDINT(rest MOD 60);
rest := rest / 60;
Hours := LINT_TO_UDINT(rest MOD 24);
Days := LINT_TO_UDINT(rest / 24);

TotalHours := LINT_TO_REAL(ms) / 3600000.0;
IF neg THEN
  TotalHours := -TotalHours;
END_IF;

(* text *)
IF neg THEN
  Text := '-';
ELSE
  Text := '';
END_IF;
IF Days > 0 THEN
  Text := CONCAT(Text, CONCAT(UDINT_TO_STRING(Days), 'd '));
END_IF;
part := UDINT_TO_STRING(Hours);
IF Hours < 10 THEN
  part := CONCAT('0', part);
END_IF;
Text := CONCAT(Text, CONCAT(part, ':'));
part := UDINT_TO_STRING(Minutes);
IF Minutes < 10 THEN
  part := CONCAT('0', part);
END_IF;
Text := CONCAT(Text, CONCAT(part, ':'));
part := UDINT_TO_STRING(Seconds);
IF Seconds < 10 THEN
  part := CONCAT('0', part);
END_IF;
Text := CONCAT(Text, part);

IF neg THEN
  Short := CONCAT('-', UT_TIME_TEXT(LINT_TO_TIME(ms)));
ELSE
  Short := UT_TIME_TEXT(In);
END_IF;

END_FUNCTION_BLOCK