(* The unit table: a unit's kind (0 none or unknown, 1 pressure, 2 flow, 3 volume,
4 temperature, 5 length, 6 percent, 7 current, 8 frequency, 9 power) and how to reach
the kind's base unit: base = value * fK + fO *)

FUNCTION F_UnitKind : E_UnitKind
  VAR_INPUT
    eUnit : E_Unit;
  END_VAR
  VAR_OUTPUT
    fK : LREAL; (* scale to the base unit (1 when unknown) *)
    fO : LREAL; (* offset to the base unit *)
  END_VAR


fK := 1.0;
fO := 0.0;
CASE eUnit OF
E_Unit.Bar:  F_UnitKind := E_UnitKind.Pressure; fK := 100.0;
E_Unit.KPa:  F_UnitKind := E_UnitKind.Pressure;
E_Unit.Psi:  F_UnitKind := E_UnitKind.Pressure; fK := 6.894757293168361;
E_Unit.MetreH2O: F_UnitKind := E_UnitKind.Pressure; fK := 9.80665;
E_Unit.LitrePerSec:  F_UnitKind := E_UnitKind.Flow;
E_Unit.LitrePerMin:  F_UnitKind := E_UnitKind.Flow; fK := 1.0 / 60.0;
E_Unit.M3PerHour:  F_UnitKind := E_UnitKind.Flow; fK := 1.0 / 3.6;
E_Unit.GalPerMin:  F_UnitKind := E_UnitKind.Flow; fK := 3.785411784 / 60.0;
E_Unit.M3PerDay:  F_UnitKind := E_UnitKind.Flow; fK := 1.0 / 86.4;
E_Unit.MegaLitrePerDay:  F_UnitKind := E_UnitKind.Flow; fK := 1000000.0 / 86400.0;
E_Unit.Litre:    F_UnitKind := E_UnitKind.Volume;
E_Unit.M3:   F_UnitKind := E_UnitKind.Volume; fK := 1000.0;
E_Unit.MegaLitre:   F_UnitKind := E_UnitKind.Volume; fK := 1000000.0;
E_Unit.Gallon:  F_UnitKind := E_UnitKind.Volume; fK := 3.785411784;
E_Unit.DegC: F_UnitKind := E_UnitKind.Temperature; fO := 273.15;
E_Unit.DegF: F_UnitKind := E_UnitKind.Temperature; fK := 5.0 / 9.0; fO := 459.67 * 5.0 / 9.0;
E_Unit.Kelvin:    F_UnitKind := E_UnitKind.Temperature;
E_Unit.Mm:   F_UnitKind := E_UnitKind.Length; fK := 0.001;
E_Unit.Cm:   F_UnitKind := E_UnitKind.Length; fK := 0.01;
E_Unit.Metre:    F_UnitKind := E_UnitKind.Length;
E_Unit.Inch:   F_UnitKind := E_UnitKind.Length; fK := 0.0254;
E_Unit.Foot:   F_UnitKind := E_UnitKind.Length; fK := 0.3048;
E_Unit.Kg:   F_UnitKind := E_UnitKind.Mass;
E_Unit.Tonne:   F_UnitKind := E_UnitKind.Mass; fK := 1000.0;
E_Unit.Percent:  F_UnitKind := E_UnitKind.Percent;
E_Unit.Amp:    F_UnitKind := E_UnitKind.Current;
E_Unit.Hertz:   F_UnitKind := E_UnitKind.Frequency;
E_Unit.KW:   F_UnitKind := E_UnitKind.Power;
ELSE
  F_UnitKind := E_UnitKind.None;
END_CASE;

END_FUNCTION