(* FB_Linearise — lookup table / curve.

Converts fIn using a table of points (aX[i], aY[i]) with straight lines between
them: tank strapping tables, non-linear sensors, weirs and flumes, valve
characteristics, pump curves.

aX and aY are arrays of any size and any lower bound (ARRAY[1..20],
ARRAY[0..9] ...). Point 1 is the first element of each, so aX and aY may even
have different lower bounds. nPoints = N uses only the first N points;
0 uses the whole arrays, which must then be the same length.

The table is checked every scan (an HMI may edit it): aX must be strictly
increasing, and every aX and aY a number. A table that fails holds fOut and
bOutOfRange where they were and sets bTableOk FALSE.

Beyond the first or last point: bExtrapolate FALSE gives that end's aY,
TRUE carries the end segment on. A one-point table gives its aY everywhere.
A NaN or infinite fIn holds fOut and bOutOfRange and sets bBadInput; bInGood
FALSE holds them too. bGood: bInGood, bTableOk and fIn a number. fSlope is
dY / dX of the segment in use (the end segment beyond the ends; 0 for a
one-point table): a vessel's TABLE area. *)

FUNCTION_BLOCK FB_Linearise
  VAR_INPUT
    fIn : REAL; (* value to look up *)
    bInGood : BOOL := TRUE; (* its health; FALSE: fOut held *)
    nPoints : INT; (* use only the first N points (0 = whole array) *)
    bExtrapolate : BOOL; (* beyond the ends: FALSE = end value, TRUE = extend the end segment *)
  END_VAR
  VAR_OUTPUT
    bGood : BOOL; (* bInGood, bTableOk, fIn a number *)
    fOut : REAL; (* interpolated result *)
    fSlope : REAL; (* dY / dX of the segment in use *)
    bOutOfRange : BOOL; (* fIn is beyond the first or last point *)
    bTableOk : BOOL; (* table valid: aX strictly increasing, all numbers, lengths agree *)
    bBadInput : BOOL; (* fIn is NaN or infinite: fOut is held *)
  END_VAR
  VAR_IN_OUT
    aX : ARRAY [*] OF REAL; (* input points, increasing *)
    aY : ARRAY [*] OF REAL; (* output points *)
  END_VAR
  VAR
    nXLo : DINT; (* lower bound of aX *)
    nYLo : DINT; (* lower bound of aY *)
    nX : DINT;
    nY : DINT;
    nN : DINT; (* points in use *)
    nI : DINT;
    nSeg : DINT; (* the last point at or below fIn (0 = first, -1 = below the first) *)
    nA : DINT; (* segment used: points a and a + 1 *)
    fXv : REAL;
    fYv : REAL;
    bOk : BOOL;
    bExact : BOOL; (* fIn is exactly on point seg *)
  END_VAR


nXLo := LOWER_BOUND(aX, 1);
nYLo := LOWER_BOUND(aY, 1);
nX := UPPER_BOUND(aX, 1) - nXLo + 1;
nY := UPPER_BOUND(aY, 1) - nYLo + 1;
IF nPoints = 0 THEN
  nN := nX;
  bOk := nX = nY;
ELSE
  nN := INT_TO_DINT(nPoints);
  bOk := nN <= nX AND nN <= nY;
END_IF;
bOk := bOk AND nN >= 1;

bBadInput := NOT (fIn = fIn) OR fIn > 3.4E38 OR fIn < -3.4E38;

(* check the table and find the segment in one pass *)
nSeg := -1;
IF bOk THEN
  FOR nI := 0 TO nN - 1 DO
    fXv := aX[nXLo + nI];
    fYv := aY[nYLo + nI];
    IF NOT (fXv = fXv) OR fXv > 3.4E38 OR fXv < -3.4E38 OR NOT (fYv = fYv) OR fYv > 3.4E38 OR fYv < -3.4E38 THEN
      bOk := FALSE;
      EXIT;
    END_IF;
    IF nI > 0 THEN
      IF NOT (fXv > aX[nXLo + nI - 1]) THEN
        bOk := FALSE;             (* unsorted or a duplicate aX *)
        EXIT;
      END_IF;
    END_IF;
    IF fXv <= fIn THEN
      nSeg := nI;
    END_IF;
  END_FOR;
END_IF;
bTableOk := bOk;

bGood := bInGood AND bOk AND NOT bBadInput;
IF bOk AND NOT bBadInput AND bInGood THEN
  IF nN = 1 THEN
    fSlope := 0.0;
  ELSE
    IF nSeg < 0 THEN
      nA := 0;
    ELSIF nSeg >= nN - 1 THEN
      nA := nN - 2;
    ELSE
      nA := nSeg;
    END_IF;
    fSlope := LREAL_TO_REAL((REAL_TO_LREAL(aY[nYLo + nA + 1]) - REAL_TO_LREAL(aY[nYLo + nA]))
                           / (REAL_TO_LREAL(aX[nXLo + nA + 1]) - REAL_TO_LREAL(aX[nXLo + nA])));
  END_IF;
  bOutOfRange := fIn < aX[nXLo] OR fIn > aX[nXLo + nN - 1];
  bExact := FALSE;
  IF nSeg >= 0 THEN               (* (AND does not short-circuit in IEC) *)
    bExact := fIn = aX[nXLo + nSeg];
  END_IF;
  IF nN = 1 THEN
    fOut := aY[nYLo];
  ELSIF bExact THEN
    fOut := aY[nYLo + nSeg];         (* exactly on a point *)
  ELSIF bOutOfRange AND NOT bExtrapolate THEN
    IF nSeg < 0 THEN
      fOut := aY[nYLo];
    ELSE
      fOut := aY[nYLo + nN - 1];
    END_IF;
  ELSE
    IF nSeg < 0 THEN
      nA := 0;                    (* below the first point: first segment *)
    ELSIF nSeg >= nN - 1 THEN
      nA := nN - 2;                (* above the last point: last segment *)
    ELSE
      nA := nSeg;
    END_IF;
    fOut := LREAL_TO_REAL(REAL_TO_LREAL(aY[nYLo + nA])
           + (REAL_TO_LREAL(fIn) - REAL_TO_LREAL(aX[nXLo + nA]))
           * (REAL_TO_LREAL(aY[nYLo + nA + 1]) - REAL_TO_LREAL(aY[nYLo + nA]))
           / (REAL_TO_LREAL(aX[nXLo + nA + 1]) - REAL_TO_LREAL(aX[nXLo + nA])));
  END_IF;
END_IF;

END_FUNCTION_BLOCK