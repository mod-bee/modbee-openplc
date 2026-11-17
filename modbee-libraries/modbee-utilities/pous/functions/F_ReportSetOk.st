(* the settings of one reported value are good (private to FB_Report and FB_ReportArray) *)

FUNCTION F_ReportSetOk : BOOL
  VAR_IN_OUT
    stS : ST_ReportSet;
  END_VAR

F_ReportSetOk := stS.fDeadband >= 0.0 AND stS.fDeadband <= REAL#3.4E38 AND stS.fSpan >= 0.0 AND stS.fSpan <= REAL#3.4E38
                 AND stS.fResolution >= 0.0 AND stS.fResolution <= REAL#3.4E38 AND stS.tMinInterval >= T#0s
                 AND stS.tHeartbeat >= T#0s
                 AND (stS.eDeadbandMode = E_DeadbandMode.Abs OR stS.eDeadbandMode = E_DeadbandMode.PctValue
                      OR (stS.eDeadbandMode = E_DeadbandMode.PctSpan AND stS.fSpan > 0.0));

END_FUNCTION