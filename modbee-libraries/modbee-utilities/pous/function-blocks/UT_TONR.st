(* UT_TONR — retentive (accumulating) on-delay timer.

Like a TON, but the elapsed time is kept when In goes off, and timing
carries on from there the next time In is on. Q comes on once In has been
on for PT in total. Reset clears the time (and wins while held).

Like Siemens TONR and Rockwell RTO, the time lives only while the PLC is
powered: after a power cycle or a PLC restart ET starts at 0. Nothing is
retained.

ET stops at PT. If PT is lowered below the time already gathered, Q comes
on at once; if PT is raised again, timing carries on from the time
gathered. PT of 0 or less: Q comes on as soon as In is on.

Each scan interval counts if In was on at its start, so the time gathered
is right to within a scan for each on period, at any task interval. *)

FUNCTION_BLOCK UT_TONR
  VAR_INPUT
    In : BOOL; (* gathers time while TRUE *)
    PT : TIME := T#10s; (* preset *)
    Reset : BOOL; (* clears ET (wins) *)
  END_VAR
  VAR_OUTPUT
    Q : BOOL; (* ET has reached PT *)
    ET : TIME; (* time gathered (stops at PT) *)
    RT : TIME; (* time remaining *)
    Timing : BOOL; (* gathering time now *)
  END_VAR
  VAR
    tCur : TIME;
    tPrev : TIME;
    wasOn : BOOL; (* In was on (and no Reset) last scan *)
    acc : TIME; (* time gathered *)
    started : BOOL; (* In has been on since the last Reset *)
    preset : TIME;
  END_VAR


tCur := TIME();
preset := PT;
IF preset < T#0s THEN
  preset := T#0s;
END_IF;

IF Reset THEN
  acc := T#0s;
  started := FALSE;
  wasOn := FALSE;
ELSE
  IF wasOn AND acc < preset THEN
    acc := acc + (tCur - tPrev);
    IF acc > preset THEN
      acc := preset;
    END_IF;
  END_IF;
  IF In THEN
    started := TRUE;
  END_IF;
  wasOn := In;
END_IF;
tPrev := tCur;

Q := started AND acc >= preset;
IF acc < preset THEN
  ET := acc;
ELSE
  ET := preset;
END_IF;
RT := preset - ET;
Timing := In AND NOT Reset AND NOT Q;

END_FUNCTION_BLOCK