(* The unit table: a unit's kind (0 none or unknown, 1 pressure, 2 flow, 3 volume,
4 temperature, 5 length, 6 percent, 7 current, 8 frequency, 9 power) and how to reach
the kind's base unit: base = value * fScaleToBase + fOffsetToBase *)

FUNCTION F_UnitKind : E_UnitKind
  VAR_INPUT
    eUnit : E_Unit; (* the unit of the value *)
  END_VAR
  VAR_OUTPUT
    fScaleToBase : LREAL; (* scale to the base unit (1 when unknown) *)
    fOffsetToBase : LREAL; (* offset to the base unit *)
  END_VAR


fScaleToBase := 1.0;
fOffsetToBase := 0.0;
CASE eUnit OF
E_Unit.Bar:  F_UnitKind := E_UnitKind.Pressure; fScaleToBase := 100.0;
E_Unit.KPa:  F_UnitKind := E_UnitKind.Pressure;
E_Unit.Psi:  F_UnitKind := E_UnitKind.Pressure; fScaleToBase := 6.894757293168361;
E_Unit.MetreH2O: F_UnitKind := E_UnitKind.Pressure; fScaleToBase := 9.80665;
E_Unit.LitrePerSec:  F_UnitKind := E_UnitKind.Flow;
E_Unit.LitrePerMin:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 1.0 / 60.0;
E_Unit.M3PerHour:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 1.0 / 3.6;
E_Unit.GalPerMin:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 3.785411784 / 60.0;
E_Unit.M3PerDay:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 1.0 / 86.4;
E_Unit.MegaLitrePerDay:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 1000000.0 / 86400.0;
E_Unit.LitrePerHour:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 1.0 / 3600.0;
E_Unit.MegaLitrePerHour:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 1000000.0 / 3600.0;
E_Unit.GalPerHour:  F_UnitKind := E_UnitKind.Flow; fScaleToBase := 3.785411784 / 3600.0;
E_Unit.Litre:    F_UnitKind := E_UnitKind.Volume;
E_Unit.M3:   F_UnitKind := E_UnitKind.Volume; fScaleToBase := 1000.0;
E_Unit.MegaLitre:   F_UnitKind := E_UnitKind.Volume; fScaleToBase := 1000000.0;
E_Unit.Gallon:  F_UnitKind := E_UnitKind.Volume; fScaleToBase := 3.785411784;
E_Unit.DegC: F_UnitKind := E_UnitKind.Temperature; fOffsetToBase := 273.15;
E_Unit.DegF: F_UnitKind := E_UnitKind.Temperature; fScaleToBase := 5.0 / 9.0; fOffsetToBase := 459.67 * 5.0 / 9.0;
E_Unit.Kelvin:    F_UnitKind := E_UnitKind.Temperature;
E_Unit.Mm:   F_UnitKind := E_UnitKind.Length; fScaleToBase := 0.001;
E_Unit.Cm:   F_UnitKind := E_UnitKind.Length; fScaleToBase := 0.01;
E_Unit.Metre:    F_UnitKind := E_UnitKind.Length;
E_Unit.Inch:   F_UnitKind := E_UnitKind.Length; fScaleToBase := 0.0254;
E_Unit.Foot:   F_UnitKind := E_UnitKind.Length; fScaleToBase := 0.3048;
E_Unit.Kg:   F_UnitKind := E_UnitKind.Mass;
E_Unit.Tonne:   F_UnitKind := E_UnitKind.Mass; fScaleToBase := 1000.0;
E_Unit.Percent:  F_UnitKind := E_UnitKind.Percent;
E_Unit.Amp:    F_UnitKind := E_UnitKind.Current;
E_Unit.Hertz:   F_UnitKind := E_UnitKind.Frequency;
E_Unit.KW:   F_UnitKind := E_UnitKind.Power;
ELSE
  F_UnitKind := E_UnitKind.None;
END_CASE;

END_FUNCTION