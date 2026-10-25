(* UT_TANK_CALC — the maths of one tank at level H (metres): volume, full volume
and water-surface area (m3, m2), clamped at the top (Overfull). A private
FUNCTION, called once per tank by UT_VESSEL (tanks joined at the bottom).

VERTICAL   flat-bottom vertical cylinder: diameter, height
CONE       a hopper (coneHeight, from outletDiameter up to diameter) under a
           cylinder of `height`
HORIZONTAL horizontal cylinder with flat ends: diameter, length
RECT       length, width, height
SPHERE     diameter
POND       sloped banks: floor length x width, depth `height`, bank `slope`
           (horizontal per 1 vertical, e.g. 3 for 3:1); slope 0 = RECT
TABLE      volume and area from a UT_LINEARISE table (TableVol / TableArea),
           tableFull = the volume when full, `height` = the level when full
SAME       tanks 2..6: as tank 1 (the caller passes tank 1's geometry) *)

FUNCTION UT_TANK_CALC : BOOL
  VAR_INPUT
    H : REAL; (* level from the bottom, m *)
    TableVol : REAL; (* TABLE: volume at H (the table's Out) *)
    TableArea : REAL; (* TABLE: area at H (the table's Slope) *)
  END_VAR
  VAR_IN_OUT
    G : UT_TANK_GEOM;
    R : UT_TANK_RES;
  END_VAR
  VAR
    BIG : REAL := 1.0E30;
    piVal : REAL := 3.14159265;
    lvl : REAL;
    rad : REAL;
    rOut : REAL;
    rAt : REAL;
    area : REAL;
    coneFull : REAL;
    c : REAL;
    s : REAL;
  END_VAR


R.bad := UT_F_NONE;
rad := G.diameter / 2.0;
CASE G.shape OF
UT_SHAPE_CONE:
  IF NOT (G.diameter > 0.0 AND G.diameter <= BIG) THEN R.bad := UT_F_DIAMETER;
  ELSIF NOT (G.height >= 0.0 AND G.height <= BIG) THEN R.bad := UT_F_TANK_HEIGHT;
  ELSIF NOT (G.coneHeight >= 0.0 AND G.coneHeight <= BIG AND G.outletDiameter >= 0.0
             AND G.outletDiameter <= G.diameter AND (G.height > 0.0 OR G.coneHeight > 0.0)) THEN R.bad := UT_F_CONE;
  END_IF;
  R.top := G.coneHeight + G.height;
UT_SHAPE_HORIZONTAL:
  IF NOT (G.diameter > 0.0 AND G.diameter <= BIG) THEN R.bad := UT_F_DIAMETER;
  ELSIF NOT (G.length > 0.0 AND G.length <= BIG) THEN R.bad := UT_F_LENGTH_WIDTH;
  END_IF;
  R.top := G.diameter;
UT_SHAPE_RECT:
  IF NOT (G.length > 0.0 AND G.length <= BIG AND G.width > 0.0 AND G.width <= BIG) THEN R.bad := UT_F_LENGTH_WIDTH;
  ELSIF NOT (G.height > 0.0 AND G.height <= BIG) THEN R.bad := UT_F_TANK_HEIGHT;
  END_IF;
  R.top := G.height;
UT_SHAPE_SPHERE:
  IF NOT (G.diameter > 0.0 AND G.diameter <= BIG) THEN R.bad := UT_F_DIAMETER; END_IF;
  R.top := G.diameter;
UT_SHAPE_POND:
  IF NOT (G.length > 0.0 AND G.length <= BIG AND G.width > 0.0 AND G.width <= BIG) THEN R.bad := UT_F_LENGTH_WIDTH;
  ELSIF NOT (G.height > 0.0 AND G.height <= BIG) THEN R.bad := UT_F_TANK_HEIGHT;
  ELSIF NOT (G.slope >= 0.0 AND G.slope <= 100.0) THEN R.bad := UT_F_SLOPE;
  END_IF;
  R.top := G.height;
UT_SHAPE_TABLE:
  IF NOT (G.tableFull > 0.0 AND G.tableFull <= BIG) THEN R.bad := UT_F_TABLE;
  ELSIF NOT (G.height > 0.0 AND G.height <= BIG) THEN R.bad := UT_F_TANK_HEIGHT;
  END_IF;
  R.top := G.height;
UT_SHAPE_VERTICAL:
  IF NOT (G.diameter > 0.0 AND G.diameter <= BIG) THEN R.bad := UT_F_DIAMETER;
  ELSIF NOT (G.height > 0.0 AND G.height <= BIG) THEN R.bad := UT_F_TANK_HEIGHT;
  END_IF;
  R.top := G.height;
ELSE
  R.bad := UT_F_SETTING;         // SAME (the caller resolves it) or not a shape
  R.top := 0.0;
END_CASE;
IF R.bad <> UT_F_NONE OR NOT (H = H) THEN
  R.volume := 0.0;
  R.full := 0.0;
  R.area := 0.0;
  R.overfull := FALSE;
  UT_TANK_CALC := FALSE;
  RETURN;
END_IF;
lvl := H;
R.overfull := lvl > R.top;
IF lvl > R.top THEN lvl := R.top; END_IF;
IF lvl < 0.0 THEN lvl := 0.0; END_IF;
CASE G.shape OF
UT_SHAPE_CONE:
  rOut := G.outletDiameter / 2.0;
  area := piVal * rad * rad;
  coneFull := piVal * G.coneHeight / 3.0 * (rOut * rOut + rOut * rad + rad * rad);
  R.full := coneFull + area * G.height;
  IF G.coneHeight > 0.0 AND lvl <= G.coneHeight THEN
    rAt := rOut + (rad - rOut) * lvl / G.coneHeight;
    R.volume := piVal * lvl / 3.0 * (rOut * rOut + rOut * rAt + rAt * rAt);
    R.area := piVal * rAt * rAt;
  ELSE
    R.volume := coneFull + area * (lvl - G.coneHeight);
    R.area := area;
  END_IF;
UT_SHAPE_HORIZONTAL:
  R.full := piVal * rad * rad * G.length;
  c := (rad - lvl) / rad;
  IF c > 1.0 THEN c := 1.0; ELSIF c < -1.0 THEN c := -1.0; END_IF;
  R.volume := (rad * rad * ACOS(c) - (rad - lvl) * SQRT(MAX(0.0, 2.0 * rad * lvl - lvl * lvl))) * G.length;
  R.area := 2.0 * SQRT(MAX(0.0, lvl * (G.diameter - lvl))) * G.length;
UT_SHAPE_RECT:
  R.full := G.length * G.width * G.height;
  R.volume := G.length * G.width * lvl;
  R.area := G.length * G.width;
UT_SHAPE_SPHERE:
  R.full := 4.0 / 3.0 * piVal * rad * rad * rad;
  R.volume := piVal * lvl * lvl * (3.0 * rad - lvl) / 3.0;
  R.area := piVal * lvl * (G.diameter - lvl);
UT_SHAPE_POND:
  s := G.slope;
  R.full := G.length * G.width * G.height + (G.length + G.width) * s * G.height * G.height
            + 4.0 / 3.0 * s * s * G.height * G.height * G.height;
  R.volume := G.length * G.width * lvl + (G.length + G.width) * s * lvl * lvl + 4.0 / 3.0 * s * s * lvl * lvl * lvl;
  R.area := (G.length + 2.0 * s * lvl) * (G.width + 2.0 * s * lvl);
UT_SHAPE_TABLE:
  R.full := G.tableFull;
  R.volume := MAX(0.0, MIN(TableVol, G.tableFull));
  R.area := MAX(0.0, TableArea);
ELSE
  area := piVal * rad * rad;
  R.full := area * G.height;
  R.volume := area * lvl;
  R.area := area;
END_CASE;
UT_TANK_CALC := TRUE;

END_FUNCTION