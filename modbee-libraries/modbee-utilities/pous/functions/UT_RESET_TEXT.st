(* UT_RESET_TEXT — how a tripped protection will clear, as the tail of a fault
text (function), for a simple display. The blocks do not call it. Gives
these words:

MANUAL                          ', reset needed'
RETRY, retries used up          ', retries used up, reset needed'
RETRY                           ', retrying 2 of 3 in 25 s'
AUTO                            ', auto reset in 25 s'

' in ...' (UT_TIME_TEXT) is added while TimeLeft is above 0, that is while
the recover / retry wait runs. While the cause is still there TimeLeft is 0
and the text stops at ', auto reset' / ', retrying 2 of 3'.

txt := CONCAT('Overload', UT_RESET_TEXT(M1.overload.reset,
M1.overload.retries, M1.overload.maxRetries, M1.overload.timeLeft));   // txt : STRING(64) *)

FUNCTION UT_RESET_TEXT : STRING(48)
  VAR_INPUT
    Mode : UT_RESET_MODE; (* the protection's reset mode *)
    Retries : INT; (* its retries (attempts used) *)
    MaxRetries : INT; (* its maxRetries *)
    TimeLeft : TIME; (* its timeLeft *)
  END_VAR
  VAR
    txt : STRING(48);
  END_VAR


CASE Mode OF
  UT_RST_MANUAL:
    UT_RESET_TEXT := ', reset needed';
    RETURN;
  UT_RST_AUTO:
    txt := ', auto reset';
ELSE
  (* RETRY, and a garbage mode, which acts as RETRY (decision 10) *)
  IF Retries > MaxRetries THEN
    UT_RESET_TEXT := ', retries used up, reset needed';
    RETURN;
  END_IF;
  txt := CONCAT(CONCAT(', retrying ', INT_TO_STRING(Retries)), CONCAT(' of ', INT_TO_STRING(MaxRetries)));
END_CASE;
IF TimeLeft > T#0s THEN
  txt := CONCAT(CONCAT(txt, ' in '), UT_TIME_TEXT(TimeLeft));
END_IF;
UT_RESET_TEXT := txt;

END_FUNCTION