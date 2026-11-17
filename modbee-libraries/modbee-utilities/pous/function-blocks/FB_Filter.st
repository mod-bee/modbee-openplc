(* FB_Filter — smoothing filter.

eMode  E_FilterMode.Lowpass    first order low-pass: after a step, fOut has moved
63 % of the way after tTc, 95 % after 3 x tTc
E_FilterMode.Average    moving average of the last tTc, updated every scan:
the window being filled plus the share of the
last whole window still inside tTc (two sums,
no history)
E_FilterMode.BlockAvg  average of each tTc window, updated once at the
end of each window

The first scan, bReset, and tTc = 0 (or less than 1 ms) pass fIn straight
through. Changing eMode or tTc carries on from the present fOut without a jump.

Time is measured from TIME() differences in whole milliseconds; the part of a
millisecond left over is carried to the next scan, so nothing drifts and the
result is the same at any task interval.

A value that is not a number (NaN, infinity), or bInGood FALSE, is ignored:
fOut holds, bBadInput is set (a number only), and the time it lasted does not
count. bGood: a value has been taken and the input is usable now. Filtering carries
on from the held value when the input is good again. *)

FUNCTION_BLOCK FB_Filter
  VAR_INPUT
    fIn : REAL; (* noisy value *)
    bInGood : BOOL := TRUE; (* FALSE: fOut held, the time not counted *)
    tTc : TIME := T#1s; (* time constant (low-pass) or window length (averages) *)
    eMode : E_FilterMode; (* E_FilterMode.Lowpass, E_FilterMode.Average, E_FilterMode.BlockAvg *)
    bReset : BOOL; (* fOut jumps straight to fIn *)
  END_VAR
  VAR_OUTPUT
    bGood : BOOL; (* bInGood, a value taken, fIn a number *)
    fOut : REAL;
    bBadInput : BOOL; (* fIn is NaN or infinite: fOut is held *)
  END_VAR
  VAR
    bStarted : BOOL; (* the first good value has been taken *)
    tPrev : TIME; (* time counted up to *)
    fY : LREAL; (* the filtered value *)
    fTcPrev : LREAL; (* tTc in ms last scan *)
    eModePrev : E_FilterMode;
    fPrevAvg : LREAL; (* AVERAGE: the average of the last whole window *)
    fAcc : LREAL; (* value x ms in the slice or window being filled *)
    fFilled : LREAL; (* ms in the slice or window being filled *)
    fX : LREAL;
    fTcMs : LREAL;
    dMs : LINT;
    dtMs : LREAL;
    fRest : LREAL;
    bSkip : BOOL; (* this scan's reading is not used *)
  END_VAR


bBadInput := NOT (fIn = fIn) OR fIn > 3.4E38 OR fIn < -3.4E38;
bSkip := bBadInput OR NOT bInGood;
fX := REAL_TO_LREAL(fIn);
fTcMs := TIME_TO_LREAL(tTc);       (* milliseconds *)

IF NOT bStarted OR bReset THEN
  IF NOT bSkip THEN
    fY := fX;                      (* first scan and bReset: straight through *)
    bStarted := TRUE;
  END_IF;
  tPrev := TIME();
  fAcc := 0.0;
  fFilled := 0.0;
  fPrevAvg := fY;
ELSIF eMode <> eModePrev OR fTcMs <> fTcPrev THEN
  fAcc := 0.0;                    (* restart from the present value, no jump *)
  fFilled := 0.0;
  fPrevAvg := fY;
END_IF;
eModePrev := eMode;
fTcPrev := fTcMs;

IF bSkip THEN
  tPrev := TIME();               (* bad time does not count *)
ELSIF bStarted THEN
  dMs := TIME_TO_LINT(TIME() - tPrev);         (* whole ms elapsed *)
  IF dMs > 0 THEN
    tPrev := tPrev + LINT_TO_TIME(dMs);        (* the part of a ms left over carries on *)
    dtMs := LINT_TO_LREAL(dMs);
    IF fTcMs <= 0.0 THEN
      fY := fX;
    ELSIF eMode = E_FilterMode.Average THEN
      IF dtMs >= fTcMs - fFilled THEN
        fPrevAvg := (fAcc + fX * (fTcMs - fFilled)) / fTcMs;   (* a window has ended *)
        fRest := dtMs - (fTcMs - fFilled);
        IF fRest >= fTcMs THEN
          fPrevAvg := fX;          (* whole windows passed in one scan *)
          fRest := 0.0;
        END_IF;
        fAcc := fX * fRest;
        fFilled := fRest;
      ELSE
        fAcc := fAcc + fX * dtMs;
        fFilled := fFilled + dtMs;
      END_IF;
      (* the window being filled, and the last whole window's share of tTc *)
      fY := (fAcc + fPrevAvg * (fTcMs - fFilled)) / fTcMs;
    ELSIF eMode = E_FilterMode.BlockAvg THEN
      IF dtMs >= fTcMs - fFilled THEN
        fY := (fAcc + fX * (fTcMs - fFilled)) / fTcMs;    (* a window has ended *)
        fRest := dtMs - (fTcMs - fFilled);
        IF fRest >= fTcMs THEN
          fY := fX;                (* whole windows passed in one scan *)
          fRest := 0.0;
        END_IF;
        fAcc := fX * fRest;
        fFilled := fRest;
      ELSE
        fAcc := fAcc + fX * dtMs;
        fFilled := fFilled + dtMs;
      END_IF;
    ELSE
      fY := fY + (fX - fY) * (1.0 - EXP(-dtMs / fTcMs));
    END_IF;
  END_IF;
END_IF;
fOut := LREAL_TO_REAL(fY);
bGood := bStarted AND NOT bSkip;

END_FUNCTION_BLOCK