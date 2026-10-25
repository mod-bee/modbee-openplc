(* The unit table: a unit's kind (0 none or unknown, 1 pressure, 2 flow, 3 volume,
4 temperature, 5 length, 6 percent, 7 current, 8 frequency, 9 power) and how to reach
the kind's base unit: base = value * K + O *)

FUNCTION UT_UNIT_KIND : USINT
  VAR_INPUT
    Unit : UT_UNIT;
  END_VAR
  VAR_OUTPUT
    K : LREAL; (* scale to the base unit (1 when unknown) *)
    O : LREAL; (* offset to the base unit *)
  END_VAR


K := 1.0;
O := 0.0;
CASE Unit OF
UT_UNIT_BAR:  UT_UNIT_KIND := 1; K := 100.0;
UT_UNIT_KPA:  UT_UNIT_KIND := 1;
UT_UNIT_PSI:  UT_UNIT_KIND := 1; K := 6.894757293168361;
UT_UNIT_MH2O: UT_UNIT_KIND := 1; K := 9.80665;
UT_UNIT_LPS:  UT_UNIT_KIND := 2;
UT_UNIT_LPM:  UT_UNIT_KIND := 2; K := 1.0 / 60.0;
UT_UNIT_M3H:  UT_UNIT_KIND := 2; K := 1.0 / 3.6;
UT_UNIT_GPM:  UT_UNIT_KIND := 2; K := 3.785411784 / 60.0;
UT_UNIT_M3D:  UT_UNIT_KIND := 2; K := 1.0 / 86.4;
UT_UNIT_MLD:  UT_UNIT_KIND := 2; K := 1000000.0 / 86400.0;
UT_UNIT_L:    UT_UNIT_KIND := 3;
UT_UNIT_M3:   UT_UNIT_KIND := 3; K := 1000.0;
UT_UNIT_ML:   UT_UNIT_KIND := 3; K := 1000000.0;
UT_UNIT_GAL:  UT_UNIT_KIND := 3; K := 3.785411784;
UT_UNIT_DEGC: UT_UNIT_KIND := 4; O := 273.15;
UT_UNIT_DEGF: UT_UNIT_KIND := 4; K := 5.0 / 9.0; O := 459.67 * 5.0 / 9.0;
UT_UNIT_K:    UT_UNIT_KIND := 4;
UT_UNIT_MM:   UT_UNIT_KIND := 5; K := 0.001;
UT_UNIT_CM:   UT_UNIT_KIND := 5; K := 0.01;
UT_UNIT_M:    UT_UNIT_KIND := 5;
UT_UNIT_IN:   UT_UNIT_KIND := 5; K := 0.0254;
UT_UNIT_FT:   UT_UNIT_KIND := 5; K := 0.3048;
UT_UNIT_PCT:  UT_UNIT_KIND := 6;
UT_UNIT_A:    UT_UNIT_KIND := 7;
UT_UNIT_HZ:   UT_UNIT_KIND := 8;
UT_UNIT_KW:   UT_UNIT_KIND := 9;
ELSE
  UT_UNIT_KIND := 0;
END_CASE;

END_FUNCTION