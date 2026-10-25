(* The group settings for N members: TRUE when usable; Id = the first that is not *)

FUNCTION UT_GROUP_CHECK : BOOL
  VAR_INPUT
    N : INT; (* members *)
  END_VAR
  VAR_IN_OUT
    Set : UT_GROUP_SET;
  END_VAR
  VAR_OUTPUT
    Id : UT_FAULT;
  END_VAR


Id := UT_F_NONE;
IF N < 1 OR N > 32 THEN Id := UT_F_GROUP_SIZE; END_IF;
IF Set.maxRunning < 0 THEN Id := UT_F_GROUP_SETTING; END_IF;
IF Set.stageDelay < T#0s OR Set.destageDelay < T#0s OR Set.failoverDelay <= T#0s
   OR Set.exerciseEvery < T#0s OR Set.exerciseTime < T#0s THEN
  Id := UT_F_GROUP_SETTING;
END_IF;
CASE Set.rotation OF
  UT_ROT_FIXED:
    IF Set.fixedLead < 1 OR Set.fixedLead > N THEN Id := UT_F_GROUP_SETTING; END_IF;
  UT_ROT_EACH_START, UT_ROT_HOURS:
    ;
  UT_ROT_INTERVAL:
    IF Set.rotateInterval <= T#0s THEN Id := UT_F_GROUP_SETTING; END_IF;
ELSE
  Id := UT_F_GROUP_SETTING;
END_CASE;
UT_GROUP_CHECK := Id = UT_F_NONE;

END_FUNCTION