(* TRUE when F_UnitConv can convert eFromUnit to eToUnit: both units are of the same
kind and neither is NONE *)

FUNCTION F_UnitOk : BOOL
  VAR_INPUT
    eFromUnit : E_Unit;
    eToUnit : E_Unit;
  END_VAR
  VAR
    eKindFrom : E_UnitKind;
  END_VAR


eKindFrom := F_UnitKind(eUnit := eFromUnit);
F_UnitOk := eKindFrom <> E_UnitKind.None AND eKindFrom = F_UnitKind(eUnit := eToUnit);

END_FUNCTION