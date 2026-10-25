(* UT_FILTER — smoothing filter.

Mode  UT_FILTER_LOWPASS    first order low-pass: after a step, Out has moved
63 % of the way after Tc, 95 % after 3 x Tc
UT_FILTER_AVERAGE    moving average of the last Tc, updated every scan:
the window being filled plus the share of the
last whole window still inside Tc (two sums,
no history)
UT_FILTER_BLOCK_AVG  average of each Tc window, updated once at the
end of each window

The first scan, Reset, and Tc = 0 (or less than 1 ms) pass In straight
through. Changing Mode or Tc carries on from the present Out without a jump.

Time is measured from TIME() differences in whole milliseconds; the part of a
millisecond left over is carried to the next scan, so nothing drifts and the
result is the same at any task interval.

A value that is not a number (NaN, infinity), or InGood FALSE, is ignored:
Out holds, BadInput is set (a number only), and the time it lasted does not
count. Good: a value has been taken and the input is usable now. Filtering carries
on from the held value when the input is good again. *)

FUNCTION_BLOCK UT_FILTER
  VAR_INPUT
    In : REAL; (* noisy value *)
    InGood : BOOL := TRUE; (* FALSE: Out held, the time not counted *)
    Tc : TIME := T#1s; (* time constant (low-pass) or window length (averages) *)
    Mode : UT_FILTER_MODE; (* UT_FILTER_LOWPASS, UT_FILTER_AVERAGE, UT_FILTER_BLOCK_AVG *)
    Reset : BOOL; (* Out jumps straight to In *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* InGood, a value taken, In a number *)
    Out : REAL;
    BadInput : BOOL; (* In is NaN or infinite: Out is held *)
  END_VAR
  VAR
    started : BOOL; (* the first good value has been taken *)
    tPrev : TIME; (* time counted up to *)
    y : LREAL; (* the filtered value *)
    tcPrev : LREAL; (* Tc in ms last scan *)
    modePrev : UT_FILTER_MODE;
    prevAvg : LREAL; (* AVERAGE: the average of the last whole window *)
    acc : LREAL; (* value x ms in the slice or window being filled *)
    filled : LREAL; (* ms in the slice or window being filled *)
    x : LREAL;
    tcMs : LREAL;
    dMs : LINT;
    dtMs : LREAL;
    rest : LREAL;
    skip : BOOL; (* this scan's reading is not used *)
  END_VAR


BadInput := NOT (In = In) OR In > 3.4E38 OR In < -3.4E38;
skip := BadInput OR NOT InGood;
x := REAL_TO_LREAL(In);
tcMs := TIME_TO_LREAL(Tc);       (* milliseconds *)

IF NOT started OR Reset THEN
  IF NOT skip THEN
    y := x;                      (* first scan and Reset: straight through *)
    started := TRUE;
  END_IF;
  tPrev := TIME();
  acc := 0.0;
  filled := 0.0;
  prevAvg := y;
ELSIF Mode <> modePrev OR tcMs <> tcPrev THEN
  acc := 0.0;                    (* restart from the present value, no jump *)
  filled := 0.0;
  prevAvg := y;
END_IF;
modePrev := Mode;
tcPrev := tcMs;

IF skip THEN
  tPrev := TIME();               (* bad time does not count *)
ELSIF started THEN
  dMs := TIME_TO_LINT(TIME() - tPrev);         (* whole ms elapsed *)
  IF dMs > 0 THEN
    tPrev := tPrev + LINT_TO_TIME(dMs);        (* the part of a ms left over carries on *)
    dtMs := LINT_TO_LREAL(dMs);
    IF tcMs <= 0.0 THEN
      y := x;
    ELSIF Mode = UT_FILTER_AVERAGE THEN
      IF dtMs >= tcMs - filled THEN
        prevAvg := (acc + x * (tcMs - filled)) / tcMs;   (* a window has ended *)
        rest := dtMs - (tcMs - filled);
        IF rest >= tcMs THEN
          prevAvg := x;          (* whole windows passed in one scan *)
          rest := 0.0;
        END_IF;
        acc := x * rest;
        filled := rest;
      ELSE
        acc := acc + x * dtMs;
        filled := filled + dtMs;
      END_IF;
      (* the window being filled, and the last whole window's share of Tc *)
      y := (acc + prevAvg * (tcMs - filled)) / tcMs;
    ELSIF Mode = UT_FILTER_BLOCK_AVG THEN
      IF dtMs >= tcMs - filled THEN
        y := (acc + x * (tcMs - filled)) / tcMs;    (* a window has ended *)
        rest := dtMs - (tcMs - filled);
        IF rest >= tcMs THEN
          y := x;                (* whole windows passed in one scan *)
          rest := 0.0;
        END_IF;
        acc := x * rest;
        filled := rest;
      ELSE
        acc := acc + x * dtMs;
        filled := filled + dtMs;
      END_IF;
    ELSE
      y := y + (x - y) * (1.0 - EXP(-dtMs / tcMs));
    END_IF;
  END_IF;
END_IF;
Out := LREAL_TO_REAL(y);
Good := started AND NOT skip;

END_FUNCTION_BLOCK