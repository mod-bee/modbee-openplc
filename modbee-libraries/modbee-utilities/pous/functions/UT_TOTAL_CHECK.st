(* The settings check of UT_TOTALISER: TRUE when every setting is usable *)

FUNCTION UT_TOTAL_CHECK : BOOL
  VAR_IN_OUT
    Set : UT_TOTAL_SET;
  END_VAR

UT_TOTAL_CHECK := (Set.countMethod = UT_TM_RATE OR Set.countMethod = UT_TM_PULSE
                   OR Set.countMethod = UT_TM_REGISTER OR Set.countMethod = UT_TM_CHANGE
                   OR Set.countMethod = UT_TM_RUNTIME OR Set.countMethod = UT_TM_SAMPLE
                   OR Set.countMethod = UT_TM_SNAPSHOT OR Set.countMethod = UT_TM_COUNT)
              AND (Set.rateUnit = UT_PER_SEC OR Set.rateUnit = UT_PER_MIN
                   OR Set.rateUnit = UT_PER_HOUR OR Set.rateUnit = UT_PER_DAY)
              AND (Set.inUnit = UT_VOL_NONE OR Set.inUnit = UT_VOL_L OR Set.inUnit = UT_VOL_M3 OR Set.inUnit = UT_VOL_ML)
              AND (Set.outUnit = UT_VOL_NONE OR Set.outUnit = UT_VOL_L OR Set.outUnit = UT_VOL_M3 OR Set.outUnit = UT_VOL_ML)
              AND Set.pulseValue > 0.0 AND Set.pulseValue <= 3.4E38
              AND Set.nominalRate >= 0.0 AND Set.nominalRate <= 3.4E38
              AND Set.lowCutoff >= 0.0 AND Set.lowCutoff <= 3.4E38
              AND Set.rolloverAt >= 0.0 AND Set.rolloverAt <= 3.4E38
              AND NOT (Set.countMethod = UT_TM_COUNT AND Set.rolloverAt <> 0.0
                       AND NOT (Set.rolloverAt >= 2.0 AND Set.rolloverAt <= 4294967296.0))
              AND Set.maxStep >= 0.0 AND Set.maxStep <= 3.4E38
              AND Set.deadband >= 0.0 AND Set.deadband <= 3.4E38
              AND Set.batchTarget >= 0.0 AND Set.batchTarget <= 1.0E15
              AND Set.dayLimit >= 0.0 AND Set.dayLimit <= 1.0E15
              AND Set.scale >= 0.0 AND Set.scale <= 3.4E38
              AND Set.sampleTime >= T#0s AND Set.recordEvery >= T#0s AND Set.retryWindow >= T#0s;

END_FUNCTION