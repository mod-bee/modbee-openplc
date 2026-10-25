(* UT_LINEARISE — lookup table / curve.

Converts In using a table of points (X[i], Y[i]) with straight lines between
them: tank strapping tables, non-linear sensors, weirs and flumes, valve
characteristics, pump curves.

X and Y are arrays of any size and any lower bound (ARRAY[1..20],
ARRAY[0..9] ...). Point 1 is the first element of each, so X and Y may even
have different lower bounds. Points = N uses only the first N points;
0 uses the whole arrays, which must then be the same length.

The table is checked every scan (an HMI may edit it): X must be strictly
increasing, and every X and Y a number. A table that fails holds Out and
OutOfRange where they were and sets TableOk FALSE.

Beyond the first or last point: Extrapolate FALSE gives that end's Y,
TRUE carries the end segment on. A one-point table gives its Y everywhere.
A NaN or infinite In holds Out and OutOfRange and sets BadInput; InGood
FALSE holds them too. Good: InGood, TableOk and In a number. Slope is
dY / dX of the segment in use (the end segment beyond the ends; 0 for a
one-point table): a vessel's TABLE area. *)

FUNCTION_BLOCK UT_LINEARISE
  VAR_INPUT
    In : REAL; (* value to look up *)
    InGood : BOOL := TRUE; (* its health; FALSE: Out held *)
    Points : INT; (* use only the first N points (0 = whole array) *)
    Extrapolate : BOOL; (* beyond the ends: FALSE = end value, TRUE = extend the end segment *)
  END_VAR
  VAR_OUTPUT
    Good : BOOL; (* InGood, TableOk, In a number *)
    Out : REAL; (* interpolated result *)
    Slope : REAL; (* dY / dX of the segment in use *)
    OutOfRange : BOOL; (* In is beyond the first or last point *)
    TableOk : BOOL; (* table valid: X strictly increasing, all numbers, lengths agree *)
    BadInput : BOOL; (* In is NaN or infinite: Out is held *)
  END_VAR
  VAR_IN_OUT
    X : ARRAY [*] OF REAL; (* input points, increasing *)
    Y : ARRAY [*] OF REAL; (* output points *)
  END_VAR
  VAR
    xLo : DINT; (* lower bound of X *)
    yLo : DINT; (* lower bound of Y *)
    nX : DINT;
    nY : DINT;
    n : DINT; (* points in use *)
    i : DINT;
    seg : DINT; (* the last point at or below In (0 = first, -1 = below the first) *)
    a : DINT; (* segment used: points a and a + 1 *)
    xv : REAL;
    yv : REAL;
    ok : BOOL;
    exact : BOOL; (* In is exactly on point seg *)
  END_VAR


xLo := LOWER_BOUND(X, 1);
yLo := LOWER_BOUND(Y, 1);
nX := UPPER_BOUND(X, 1) - xLo + 1;
nY := UPPER_BOUND(Y, 1) - yLo + 1;
IF Points = 0 THEN
  n := nX;
  ok := nX = nY;
ELSE
  n := INT_TO_DINT(Points);
  ok := n <= nX AND n <= nY;
END_IF;
ok := ok AND n >= 1;

BadInput := NOT (In = In) OR In > 3.4E38 OR In < -3.4E38;

(* check the table and find the segment in one pass *)
seg := -1;
IF ok THEN
  FOR i := 0 TO n - 1 DO
    xv := X[xLo + i];
    yv := Y[yLo + i];
    IF NOT (xv = xv) OR xv > 3.4E38 OR xv < -3.4E38 OR NOT (yv = yv) OR yv > 3.4E38 OR yv < -3.4E38 THEN
      ok := FALSE;
      EXIT;
    END_IF;
    IF i > 0 THEN
      IF NOT (xv > X[xLo + i - 1]) THEN
        ok := FALSE;             (* unsorted or a duplicate X *)
        EXIT;
      END_IF;
    END_IF;
    IF xv <= In THEN
      seg := i;
    END_IF;
  END_FOR;
END_IF;
TableOk := ok;

Good := InGood AND ok AND NOT BadInput;
IF ok AND NOT BadInput AND InGood THEN
  IF n = 1 THEN
    Slope := 0.0;
  ELSE
    IF seg < 0 THEN
      a := 0;
    ELSIF seg >= n - 1 THEN
      a := n - 2;
    ELSE
      a := seg;
    END_IF;
    Slope := LREAL_TO_REAL((REAL_TO_LREAL(Y[yLo + a + 1]) - REAL_TO_LREAL(Y[yLo + a]))
                           / (REAL_TO_LREAL(X[xLo + a + 1]) - REAL_TO_LREAL(X[xLo + a])));
  END_IF;
  OutOfRange := In < X[xLo] OR In > X[xLo + n - 1];
  exact := FALSE;
  IF seg >= 0 THEN               (* (AND does not short-circuit in IEC) *)
    exact := In = X[xLo + seg];
  END_IF;
  IF n = 1 THEN
    Out := Y[yLo];
  ELSIF exact THEN
    Out := Y[yLo + seg];         (* exactly on a point *)
  ELSIF OutOfRange AND NOT Extrapolate THEN
    IF seg < 0 THEN
      Out := Y[yLo];
    ELSE
      Out := Y[yLo + n - 1];
    END_IF;
  ELSE
    IF seg < 0 THEN
      a := 0;                    (* below the first point: first segment *)
    ELSIF seg >= n - 1 THEN
      a := n - 2;                (* above the last point: last segment *)
    ELSE
      a := seg;
    END_IF;
    Out := LREAL_TO_REAL(REAL_TO_LREAL(Y[yLo + a])
           + (REAL_TO_LREAL(In) - REAL_TO_LREAL(X[xLo + a]))
           * (REAL_TO_LREAL(Y[yLo + a + 1]) - REAL_TO_LREAL(Y[yLo + a]))
           / (REAL_TO_LREAL(X[xLo + a + 1]) - REAL_TO_LREAL(X[xLo + a])));
  END_IF;
END_IF;

END_FUNCTION_BLOCK