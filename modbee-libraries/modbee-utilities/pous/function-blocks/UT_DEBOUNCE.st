(* UT_DEBOUNCE — on/off delay filter.

Q switches on once In has been TRUE for OnDelay without a break, and off
once In has been FALSE for OffDelay without a break. Anything shorter is
ignored. Rising / Falling are on for one scan when Q switches.

A delay of 0 (or less) passes In straight through, in the same scan.
Q starts off; an input already on at start switches Q on after OnDelay.

While In differs from Q, ET is how long In has held its new state and
Remaining the delay still to run before Q follows (as a TON's ET and
PT - ET). Once Q follows, or with In back as Q, both are 0. *)

FUNCTION_BLOCK UT_DEBOUNCE
  VAR_INPUT
    In : BOOL; (* noisy signal *)
    OnDelay : TIME := T#100ms; (* must be TRUE this long to switch on *)
    OffDelay : TIME := T#100ms; (* must be FALSE this long to switch off *)
  END_VAR
  VAR_OUTPUT
    Q : BOOL; (* clean signal *)
    Rising : BOOL; (* one scan: Q switched on *)
    Falling : BOOL; (* one scan: Q switched off *)
    ET : TIME; (* In has held its new state this long (0 when Q agrees with In) *)
    Remaining : TIME; (* delay left before Q follows In (0 when Q agrees with In) *)
  END_VAR
  VAR
    tCur : TIME;
    inPrev : BOOL;
    since : TIME; (* when In last changed *)
    dly : TIME; (* the delay that applies now *)
  END_VAR


tCur := TIME();
Rising := FALSE;
Falling := FALSE;

IF In <> inPrev THEN
  since := tCur;
END_IF;
inPrev := In;

IF In AND NOT Q THEN
  IF tCur - since >= OnDelay THEN
    Q := TRUE;
    Rising := TRUE;
  END_IF;
ELSIF NOT In AND Q THEN
  IF tCur - since >= OffDelay THEN
    Q := FALSE;
    Falling := TRUE;
  END_IF;
END_IF;

(* the delay counting: elapsed and left *)
IF In <> Q THEN
  IF In THEN
    dly := OnDelay;
  ELSE
    dly := OffDelay;
  END_IF;
  IF dly < T#0s THEN
    dly := T#0s;
  END_IF;
  ET := tCur - since;
  IF ET > dly THEN
    ET := dly;
  END_IF;
  Remaining := dly - ET;
ELSE
  ET := T#0s;
  Remaining := T#0s;
END_IF;

END_FUNCTION_BLOCK