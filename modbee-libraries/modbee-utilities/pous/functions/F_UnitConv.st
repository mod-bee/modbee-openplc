(* F_UnitConv — converts a value from one engineering unit to another
(function); F_UnitOk says whether two units can be converted; F_UnitKind
is the one table both read.

Psi := F_UnitConv(fIn := PressureBar, eFromUnit := E_Unit.Bar, eToUnit := E_Unit.Psi);

Kinds and units (E_Unit):
pressure     Bar, KPa, Psi, MetreH2O (metres of water, 9.80665 kPa)
flow         LitrePerSec, LitrePerMin, M3PerHour, GalPerMin (US gal/min), M3PerDay, MegaLitrePerDay,
LitrePerHour, MegaLitrePerHour, GalPerHour (US gal/h)
volume       Litre, M3, MegaLitre, Gallon (US gallon)
temperature  DegC, DegF, Kelvin
length       Mm, Cm, Metre, Inch, Foot
mass         Kg, Tonne
percent      Percent      current  Amp
frequency    Hertz        power    KW

Units of different kinds (bar to L/s), or E_Unit.None on either side,
can't be converted: the value comes back UNCHANGED (never NaN, which would
silently defeat every comparison downstream). Check a pair you build at
run time with F_UnitOk. The same unit on both sides also gives fIn back
unchanged.

Worked in LREAL, so a round trip loses nothing a REAL can show. NaN in
gives NaN out; a result beyond the REAL range is infinite. *)

FUNCTION F_UnitConv : REAL
  VAR_INPUT
    fIn : REAL; (* the value, in unit eFromUnit *)
    eFromUnit : E_Unit; (* its unit *)
    eToUnit : E_Unit; (* the unit wanted *)
  END_VAR
  VAR
    eKindFrom : E_UnitKind;
    eKindTo : E_UnitKind;
    fKFrom : LREAL; (* base = value * k + o (base: kPa, L/s, L, fK, m, %, A, Hz, kW) *)
    fOFrom : LREAL;
    fKTo : LREAL;
    fOTo : LREAL;
  END_VAR


eKindFrom := F_UnitKind(eUnit := eFromUnit, fK => fKFrom, fO => fOFrom);
eKindTo := F_UnitKind(eUnit := eToUnit, fK => fKTo, fO => fOTo);
IF eKindFrom = E_UnitKind.None OR eKindFrom <> eKindTo OR eFromUnit = eToUnit THEN
  F_UnitConv := fIn;
ELSE
  F_UnitConv := LREAL_TO_REAL((REAL_TO_LREAL(fIn) * fKFrom + fOFrom - fOTo) / fKTo);
END_IF;

END_FUNCTION