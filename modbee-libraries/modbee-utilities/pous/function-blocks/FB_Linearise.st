(* FB_Linearise — lookup table / curve.

Converts fIn using a table of points (aInputPoints[i], aOutputPoints[i]) with straight lines between
them: tank strapping tables, non-linear sensors, weirs and flumes, valve
characteristics, pump curves.

aInputPoints and aOutputPoints are arrays of any size and any lower bound (ARRAY[1..20],
ARRAY[0..9] ...). Point 1 is the first element of each, so aInputPoints and aOutputPoints may even
have different lower bounds. nPointsUsed = N uses only the first N points;
0 uses the whole arrays, which must then be the same length.

The table is checked every scan (an HMI may edit it): aInputPoints must be strictly
increasing, and every aInputPoints and aOutputPoints a number. A table that fails holds fOut and
bOutOfRange where they were and sets bTableGood FALSE.

Beyond the first or last point: bExtrapolate FALSE gives that end's aOutputPoints,
TRUE carries the end segment on. A one-point table gives its aOutputPoints everywhere.
A NaN or infinite fIn holds fOut and bOutOfRange and sets bInputNotANumber; bInputGood
FALSE holds them too. bGood: bInputGood, bTableGood and fIn a number. fSlope is
dY / dX of the segment in use (the end segment beyond the ends; 0 for a
one-point table): a vessel's TABLE area. *)

FUNCTION_BLOCK FB_Linearise
  VAR_INPUT
    fIn : REAL; (* value to look up *)
    bInputGood : BOOL := TRUE; (* its health; FALSE: fOut held *)
    nPointsUsed : INT; (* use only the first N points (0 = whole array) *)
    bExtrapolate : BOOL; (* beyond the ends: FALSE = end value, TRUE = extend the end segment *)
  END_VAR
  VAR_OUTPUT
    fOut : REAL; (* interpolated result *)
    bGood : BOOL; (* bInputGood, bTableGood, fIn a number *)
    fSlope : REAL; (* dY / dX of the segment in use *)
    bOutOfRange : BOOL; (* fIn is beyond the first or last point *)
    bTableGood : BOOL; (* table valid: aInputPoints strictly increasing, all numbers, lengths agree *)
    bInputNotANumber : BOOL; (* fIn is NaN or infinite: fOut is held *)
  END_VAR
  VAR_IN_OUT
    aInputPoints : ARRAY [*] OF REAL; (* input points, increasing *)
    aOutputPoints : ARRAY [*] OF REAL; (* output points *)
  END_VAR
  VAR
    nXLo : DINT; (* lower bound of aInputPoints *)
    nYLo : DINT; (* lower bound of aOutputPoints *)
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


nXLo := LOWER_BOUND(aInputPoints, 1);
nYLo := LOWER_BOUND(aOutputPoints, 1);
nX := UPPER_BOUND(aInputPoints, 1) - nXLo + 1;
nY := UPPER_BOUND(aOutputPoints, 1) - nYLo + 1;
IF nPointsUsed = 0 THEN
  nN := nX;
  bOk := nX = nY;
ELSE
  nN := INT_TO_DINT(nPointsUsed);
  bOk := nN <= nX AND nN <= nY;
END_IF;
bOk := bOk AND nN >= 1;

bInputNotANumber := NOT (fIn = fIn) OR fIn > 3.4E38 OR fIn < -3.4E38;

(* check the table and find the segment in one pass *)
nSeg := -1;
IF bOk THEN
  FOR nI := 0 TO nN - 1 DO
    fXv := aInputPoints[nXLo + nI];
    fYv := aOutputPoints[nYLo + nI];
    IF NOT (fXv = fXv) OR fXv > 3.4E38 OR fXv < -3.4E38 OR NOT (fYv = fYv) OR fYv > 3.4E38 OR fYv < -3.4E38 THEN
      bOk := FALSE;
      EXIT;
    END_IF;
    IF nI > 0 THEN
      IF NOT (fXv > aInputPoints[nXLo + nI - 1]) THEN
        bOk := FALSE;             (* unsorted or a duplicate aInputPoints *)
        EXIT;
      END_IF;
    END_IF;
    IF fXv <= fIn THEN
      nSeg := nI;
    END_IF;
  END_FOR;
END_IF;
bTableGood := bOk;

bGood := bInputGood AND bOk AND NOT bInputNotANumber;
IF bOk AND NOT bInputNotANumber AND bInputGood THEN
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
    fSlope := LREAL_TO_REAL((REAL_TO_LREAL(aOutputPoints[nYLo + nA + 1]) - REAL_TO_LREAL(aOutputPoints[nYLo + nA]))
                           / (REAL_TO_LREAL(aInputPoints[nXLo + nA + 1]) - REAL_TO_LREAL(aInputPoints[nXLo + nA])));
  END_IF;
  bOutOfRange := fIn < aInputPoints[nXLo] OR fIn > aInputPoints[nXLo + nN - 1];
  bExact := FALSE;
  IF nSeg >= 0 THEN               (* (AND does not short-circuit in IEC) *)
    bExact := fIn = aInputPoints[nXLo + nSeg];
  END_IF;
  IF nN = 1 THEN
    fOut := aOutputPoints[nYLo];
  ELSIF bExact THEN
    fOut := aOutputPoints[nYLo + nSeg];         (* exactly on a point *)
  ELSIF bOutOfRange AND NOT bExtrapolate THEN
    IF nSeg < 0 THEN
      fOut := aOutputPoints[nYLo];
    ELSE
      fOut := aOutputPoints[nYLo + nN - 1];
    END_IF;
  ELSE
    IF nSeg < 0 THEN
      nA := 0;                    (* below the first point: first segment *)
    ELSIF nSeg >= nN - 1 THEN
      nA := nN - 2;                (* above the last point: last segment *)
    ELSE
      nA := nSeg;
    END_IF;
    fOut := LREAL_TO_REAL(REAL_TO_LREAL(aOutputPoints[nYLo + nA])
           + (REAL_TO_LREAL(fIn) - REAL_TO_LREAL(aInputPoints[nXLo + nA]))
           * (REAL_TO_LREAL(aOutputPoints[nYLo + nA + 1]) - REAL_TO_LREAL(aOutputPoints[nYLo + nA]))
           / (REAL_TO_LREAL(aInputPoints[nXLo + nA + 1]) - REAL_TO_LREAL(aInputPoints[nXLo + nA])));
  END_IF;
END_IF;

END_FUNCTION_BLOCK