(* The station's settings: TRUE when usable; Id = the first that is not *)

FUNCTION UT_STATION_CHECK : BOOL
  VAR_INPUT
    Units : DINT := 32767; (* pumps in the station's array (firstPump must be one of them) *)
  END_VAR
  VAR_IN_OUT
    S : UT_STATION_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR
  VAR
    k : INT;
    numOk : BOOL;
  END_VAR


Id := UT_F_NONE;
numOk := TRUE;
FOR k := 1 TO 4 DO
  IF NOT (ABS(S.stage[k].start) <= 3.4E38 AND ABS(S.stage[k].stop) <= 3.4E38) THEN
    numOk := FALSE;
  END_IF;
END_FOR;
IF NOT (S.stationMode = UT_SM_EMPTY OR S.stationMode = UT_SM_FILL OR S.stationMode = UT_SM_TRANSFER
        OR S.stationMode = UT_SM_TIMED) THEN
  Id := UT_F_SETTING;
ELSIF NOT numOk THEN
  Id := UT_F_POINTS;
ELSIF NOT (S.levelFail = UT_LF_FLOATS OR S.levelFail = UT_LF_STOP OR S.levelFail = UT_LF_RUN_ON) THEN
  Id := UT_F_LEVEL_FAIL;
ELSIF S.demandPumps < 1 OR NOT (ABS(S.demandStop) <= 3.4E38) OR NOT (ABS(S.demandRestart) <= 3.4E38) THEN
  Id := UT_F_DEMAND_PUMPS;
ELSIF S.cleanEvery < 0 OR NOT (ABS(S.cleanLevel) <= 3.4E38) OR S.cleanTime < T#0s OR S.maxCleanTime < T#0s THEN
  Id := UT_F_SETTING;
ELSIF S.onTime < T#0s OR S.offTime < T#0s OR S.levelRunOn < T#0s THEN
  Id := UT_F_SETTING;
ELSIF S.floats.highHold < T#0s OR S.floats.runTime < T#0s OR S.floats.lockout < T#0s OR S.floats.checkDelay < T#0s THEN
  Id := UT_F_SETTING;
ELSIF S.transfer.pumps < 1 OR S.transfer.runTime < T#0s OR NOT (S.transfer.runVolume >= 0.0)
      OR NOT (S.transfer.minFlow >= 0.0) THEN
  Id := UT_F_SETTING;
ELSIF NOT (ABS(S.source.stop) <= 3.4E38 AND ABS(S.source.restart) <= 3.4E38) OR S.source.stopDelay < T#0s
      OR S.source.restartDelay < T#0s THEN
  Id := UT_F_SOURCE_POINTS;
ELSIF NOT (S.noFlow.sp >= 0.0) OR S.noFlow.delay < T#0s OR S.noFlow.minRun < T#0s THEN
  Id := UT_F_NO_FLOW_STOP;
ELSIF NOT (S.booster.startBy = UT_BS_DELAY OR S.booster.startBy = UT_BS_PRESSURE) OR S.booster.delay < T#0s
      OR S.booster.stopGap < T#0s OR NOT (ABS(S.booster.startSp) <= 3.4E38 AND ABS(S.booster.stopSp) <= 3.4E38)
      OR (S.booster.startBy = UT_BS_PRESSURE AND NOT (S.booster.stopSp > S.booster.startSp)) THEN
  Id := UT_F_BOOSTER_SETTING;
ELSIF NOT (UT_PROT_OK(P := S.transducer) AND UT_PROT_OK(P := S.levelBad) AND UT_PROT_OK(P := S.source.bad)
           AND UT_PROT_OK(P := S.booster.lost)) THEN
  Id := UT_F_SETTING;
ELSIF NOT (S.levelVariation >= 0.0 AND S.levelVariation <= 3.4E38) OR NOT (ABS(S.highLevelAlarm) <= 3.4E38)
      OR S.pumpsUsed < 0 OR S.firstPump < 1 OR INT_TO_DINT(S.firstPump) > Units THEN
  Id := UT_F_SETTING;
ELSIF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
           OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)
           OR (S.run.style = UT_RS_PULSE_TIMER AND S.run.pulseTime > T#0s)) THEN
  Id := UT_F_RUN_STYLE;
END_IF;
UT_STATION_CHECK := Id = UT_F_NONE;

END_FUNCTION