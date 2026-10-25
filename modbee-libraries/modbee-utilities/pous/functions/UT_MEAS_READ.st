(* Shared pieces for blocks that check a 4-level measurement (private).

UT_MEAS_READ — reads a measurement plug the way every consumer must
(catalogue §1, UT_I_MEAS): the value when the source has one, each band the
source has set up as that level's switch, Good, and fitted. Without a plug
(NULL) the block's own In / InGood are used.

UT_MEAS_STATUS — the status line of a 4-level measurement: a trip (HH, LL,
H, L, sensor bad) > inhibited > not fitted > a warning > a bad reading being
ridden through > a setting > OK (a level's delay counting is named, with its
time left). *)

FUNCTION UT_MEAS_READ : BOOL
  VAR_INPUT
    Sensor : UT_I_MEAS; (* NULL: In / InGood *)
    In : REAL;
    InGood : BOOL := TRUE;
  END_VAR
  VAR_OUTPUT
    V : REAL; (* the value (NaN when the source has none) *)
    G : BOOL; (* usable *)
    HasValue : BOOL;
    Fitted : BOOL;
    BandHH : BOOL; (* the source's bands (FALSE where not set up) *)
    BandH : BOOL;
    BandL : BOOL;
    BandLL : BOOL;
  END_VAR


IF Sensor <> NULL THEN
  Fitted := Sensor.IsFitted();
  HasValue := Sensor.HasValue();
  V := Sensor.GetValue();
  G := Sensor.GoodNow();
  BandHH := Sensor.HasBand(Band := UT_LVL_HIHI) AND Sensor.IsHiHiNow();
  BandH := Sensor.HasBand(Band := UT_LVL_HI) AND Sensor.IsHiNow() AND NOT Sensor.IsHiHiNow();
  BandL := Sensor.HasBand(Band := UT_LVL_LO) AND Sensor.IsLoNow() AND NOT Sensor.IsLoLoNow();
  BandLL := Sensor.HasBand(Band := UT_LVL_LOLO) AND Sensor.IsLoLoNow();
  IF NOT BandH AND Sensor.HasBand(Band := UT_LVL_HI) AND NOT Sensor.HasBand(Band := UT_LVL_HIHI) THEN
    BandH := Sensor.IsHiNow();      (* no HH switch: H as read *)
  END_IF;
  IF NOT BandL AND Sensor.HasBand(Band := UT_LVL_LO) AND NOT Sensor.HasBand(Band := UT_LVL_LOLO) THEN
    BandL := Sensor.IsLoNow();
  END_IF;
ELSE
  Fitted := TRUE;
  HasValue := TRUE;
  V := In;
  G := InGood;
  BandHH := FALSE;
  BandH := FALSE;
  BandL := FALSE;
  BandLL := FALSE;
END_IF;
UT_MEAS_READ := G;

END_FUNCTION