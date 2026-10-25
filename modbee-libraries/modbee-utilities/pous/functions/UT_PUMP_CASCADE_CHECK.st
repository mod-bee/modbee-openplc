(* The cascade's own settings (the loop's are UT_SPEED_CTRL_CHECK's) for N duty pumps *)

FUNCTION UT_PUMP_CASCADE_CHECK : BOOL
  VAR_INPUT
    N : INT;
  END_VAR
  VAR_IN_OUT
    S : UT_PUMP_CASCADE_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR


IF NOT UT_GROUP_CHECK(N := N, Set := S.group, Id => Id) THEN
  ;
ELSIF NOT (S.stageBy = UT_PC_STAGE_PV OR S.stageBy = UT_PC_STAGE_FLOW OR S.stageBy = UT_PC_STAGE_PER_PUMP)
      OR NOT (S.stopMode = UT_PC_STOP_ALL_AT_ONCE OR S.stopMode = UT_PC_STOP_STAGED) OR S.stopStep < T#0s THEN
  Id := UT_F_GROUP_SETTING;
ELSIF NOT (S.addBand >= 0.0 AND S.addBand <= 3.4E38 AND S.dropBand >= 0.0 AND S.dropBand <= 3.4E38
           AND S.dropSpeed >= 0.0 AND S.dropSpeed <= 100.0 AND S.addPct > S.dropPct AND S.dropPct >= 0.0
           AND S.addPct <= 1000.0 AND S.bepMin >= 0.0 AND S.bepMax >= 0.0 AND S.bepMax <= 3.4E38) THEN
  Id := UT_F_GROUP_SETTING;
ELSIF NOT UT_LEVEL_OK(L := S.highFlow) THEN
  Id := UT_F_SETTING;
ELSIF NOT (S.run.style = UT_RS_HELD OR S.run.style = UT_RS_TOGGLE
           OR (S.run.style = UT_RS_KEEPALIVE AND S.run.keepAlive > T#0s)
           OR (S.run.style = UT_RS_PULSE_TIMER AND S.run.pulseTime > T#0s)) THEN
  Id := UT_F_RUN_STYLE;
END_IF;
UT_PUMP_CASCADE_CHECK := Id = UT_F_NONE;

END_FUNCTION