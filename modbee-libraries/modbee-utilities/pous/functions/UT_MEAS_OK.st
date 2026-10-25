FUNCTION UT_MEAS_OK : BOOL
  VAR_INPUT
    OrderCheck : BOOL := TRUE; (* the analog setpoints in use must be in order *)
  END_VAR
  VAR_IN_OUT
    M : UT_MEAS;
  END_VAR
  VAR
    ok : BOOL;
  END_VAR


ok := UT_LEVEL_OK(L := M.hiHi) AND UT_LEVEL_OK(L := M.hi) AND UT_LEVEL_OK(L := M.lo) AND UT_LEVEL_OK(L := M.loLo)
      AND UT_PROT_OK(P := M.sensorBad)
      AND (M.sensor = UT_SENSOR_SWITCH OR M.sensor = UT_SENSOR_ANALOG OR M.sensor = UT_SENSOR_BOTH)
      AND (M.highSwitch = UT_LVL_NONE OR M.highSwitch = UT_LVL_HIHI OR M.highSwitch = UT_LVL_HI)
      AND (M.lowSwitch = UT_LVL_NONE OR M.lowSwitch = UT_LVL_LO OR M.lowSwitch = UT_LVL_LOLO);
IF ok AND OrderCheck AND M.installed AND M.sensor <> UT_SENSOR_SWITCH THEN
  ok := NOT ((M.hiHi.response <> UT_RESP_OFF AND M.hi.response <> UT_RESP_OFF AND M.hiHi.sp < M.hi.sp)
          OR (M.hi.response <> UT_RESP_OFF AND M.lo.response <> UT_RESP_OFF AND M.hi.sp <= M.lo.sp)
          OR (M.hiHi.response <> UT_RESP_OFF AND M.lo.response <> UT_RESP_OFF AND M.hiHi.sp <= M.lo.sp)
          OR (M.lo.response <> UT_RESP_OFF AND M.loLo.response <> UT_RESP_OFF AND M.lo.sp < M.loLo.sp)
          OR (M.hi.response <> UT_RESP_OFF AND M.loLo.response <> UT_RESP_OFF AND M.hi.sp <= M.loLo.sp)
          OR (M.hiHi.response <> UT_RESP_OFF AND M.loLo.response <> UT_RESP_OFF AND M.hiHi.sp <= M.loLo.sp));
END_IF;
UT_MEAS_OK := ok;

END_FUNCTION