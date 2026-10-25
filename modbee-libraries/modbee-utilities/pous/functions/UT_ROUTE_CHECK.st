FUNCTION UT_ROUTE_CHECK : BOOL
  VAR_IN_OUT
    S : UT_ROUTE_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR
  VAR
    k : INT;
  END_VAR


Id := UT_F_NONE;
FOR k := 1 TO 4 DO
  IF NOT (S.outlet[k].kind = UT_OUT_NONE OR S.outlet[k].kind = UT_OUT_IRRIGATION OR S.outlet[k].kind = UT_OUT_STORAGE
          OR S.outlet[k].kind = UT_OUT_OTHER) THEN
    Id := UT_F_OUTLET_KIND;
  ELSIF S.outlet[k].preset < -1 OR S.outlet[k].preset > 2 THEN
    Id := UT_F_PRESET;
  END_IF;
END_FOR;
IF S.levelOutlet > 4 OR S.runOutlet > 4 OR S.storageOutlet > 4 THEN
  Id := UT_F_OUTLET_NUMBER;
ELSIF S.closeDelay < T#0s OR S.closeDelay > T#10m THEN
  Id := UT_F_CLOSE_DELAY;
END_IF;
UT_ROUTE_CHECK := Id = UT_F_NONE;

END_FUNCTION