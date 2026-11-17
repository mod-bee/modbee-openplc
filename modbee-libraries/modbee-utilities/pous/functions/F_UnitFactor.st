(* F_UnitFactor — the factor that turns a quantity in volume unit eFromUnit into volume unit eToUnit (litre, m3,
megalitre, gallon; E_Unit), for the meters' input and output units. Both None: factor 1 (no conversion), bOk
TRUE. One None, or a unit that is not a volume, or two units of different kinds: factor 1, bOk FALSE (the
caller refuses the setting). Worked in LREAL from F_UnitKind's table. *)

FUNCTION F_UnitFactor : LREAL
  VAR_INPUT
    eFromUnit : E_Unit;
    eToUnit : E_Unit;
  END_VAR
  VAR_OUTPUT
    bOk : BOOL;
  END_VAR
  VAR
    fKFrom : LREAL;
    fKTo : LREAL;
    fO : LREAL;
  END_VAR


F_UnitFactor := 1.0;
bOk := FALSE;
IF eFromUnit = E_Unit.None AND eToUnit = E_Unit.None THEN
  bOk := TRUE;
ELSIF F_UnitKind(eUnit := eFromUnit, fK => fKFrom, fO => fO) = E_UnitKind.Volume
      AND F_UnitKind(eUnit := eToUnit, fK => fKTo, fO => fO) = E_UnitKind.Volume THEN
  F_UnitFactor := fKFrom / fKTo;
  bOk := TRUE;
END_IF;

END_FUNCTION