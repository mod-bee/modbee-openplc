(* F_UnitFactor — the factor that turns a quantity in volume unit eFromUnit into volume unit eToUnit (litre, m3,
megalitre, gallon; E_Unit), for the meters' input and output units. Both None: factor 1 (no conversion), bUnitsMatch
TRUE. One None, or a unit that is not a volume, or two units of different kinds: factor 1, bUnitsMatch FALSE (the
caller refuses the setting). Worked in LREAL from F_UnitKind's table. *)

FUNCTION F_UnitFactor : LREAL
  VAR_INPUT
    eFromUnit : E_Unit; (* the unit it is in *)
    eToUnit : E_Unit; (* the unit wanted *)
  END_VAR
  VAR_OUTPUT
    bUnitsMatch : BOOL; (* both units are known and of the same kind *)
  END_VAR
  VAR
    fKFrom : LREAL;
    fKTo : LREAL;
    fO : LREAL;
  END_VAR


F_UnitFactor := 1.0;
bUnitsMatch := FALSE;
IF eFromUnit = E_Unit.None AND eToUnit = E_Unit.None THEN
  bUnitsMatch := TRUE;
ELSIF F_UnitKind(eUnit := eFromUnit, fScaleToBase => fKFrom, fOffsetToBase => fO) = E_UnitKind.Volume
      AND F_UnitKind(eUnit := eToUnit, fScaleToBase => fKTo, fOffsetToBase => fO) = E_UnitKind.Volume THEN
  F_UnitFactor := fKFrom / fKTo;
  bUnitsMatch := TRUE;
END_IF;

END_FUNCTION