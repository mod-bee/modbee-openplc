(* UT_UNIT_CONV — converts a value from one engineering unit to another
(function); UT_UNIT_OK says whether two units can be converted; UT_UNIT_KIND
is the one table both read.

Psi := UT_UNIT_CONV(In := PressureBar, FromUnit := UT_UNIT_BAR, ToUnit := UT_UNIT_PSI);

Kinds and units (UT_UNIT):
pressure     BAR, KPA, PSI, MH2O (metres of water, 9.80665 kPa)
flow         LPS (L/s), LPM (L/min), M3H (m3/h), GPM (US gal/min), M3D (m3/day), MLD (ML/day)
volume       L, M3, ML (megalitre), GAL (US gallon)
temperature  DEGC, DEGF, K
length       MM, CM, M, IN, FT
percent      PCT          current  A
frequency    HZ           power    KW

Units of different kinds (bar to L/s), or UT_UNIT_NONE on either side,
can't be converted: the value comes back UNCHANGED (never NaN, which would
silently defeat every comparison downstream). Check a pair you build at
run time with UT_UNIT_OK. The same unit on both sides also gives In back
unchanged.

Worked in LREAL, so a round trip loses nothing a REAL can show. NaN in
gives NaN out; a result beyond the REAL range is infinite. *)

FUNCTION UT_UNIT_CONV : REAL
  VAR_INPUT
    In : REAL; (* the value, in unit FromUnit *)
    FromUnit : UT_UNIT; (* its unit *)
    ToUnit : UT_UNIT; (* the unit wanted *)
  END_VAR
  VAR
    kindFrom : USINT;
    kindTo : USINT;
    kFrom : LREAL; (* base = value * k + o (base: kPa, L/s, L, K, m, %, A, Hz, kW) *)
    oFrom : LREAL;
    kTo : LREAL;
    oTo : LREAL;
  END_VAR


kindFrom := UT_UNIT_KIND(Unit := FromUnit, K => kFrom, O => oFrom);
kindTo := UT_UNIT_KIND(Unit := ToUnit, K => kTo, O => oTo);
IF kindFrom = 0 OR kindFrom <> kindTo OR FromUnit = ToUnit THEN
  UT_UNIT_CONV := In;
ELSE
  UT_UNIT_CONV := LREAL_TO_REAL((REAL_TO_LREAL(In) * kFrom + oFrom - oTo) / kTo);
END_IF;

END_FUNCTION