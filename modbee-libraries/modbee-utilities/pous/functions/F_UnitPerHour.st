(* F_UnitPerHour — the flow unit of a volume unit per hour (Litre: LitrePerHour, M3: M3PerHour, MegaLitre:
MegaLitrePerHour, Gallon: GalPerHour): a meter's rate unit. Any other unit: None. *)

FUNCTION F_UnitPerHour : E_Unit
  VAR_INPUT
    eUnit : E_Unit; (* a volume unit *)
  END_VAR

CASE eUnit OF
E_Unit.Litre:      F_UnitPerHour := E_Unit.LitrePerHour;
E_Unit.M3:         F_UnitPerHour := E_Unit.M3PerHour;
E_Unit.MegaLitre:  F_UnitPerHour := E_Unit.MegaLitrePerHour;
E_Unit.Gallon:     F_UnitPerHour := E_Unit.GalPerHour;
ELSE
  F_UnitPerHour := E_Unit.None;
END_CASE;

END_FUNCTION