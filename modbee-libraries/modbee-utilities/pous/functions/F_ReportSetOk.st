(* the settings of one reported value are good (private to FB_Report and FB_ReportArray) *)

FUNCTION F_ReportSetOk : BOOL
  VAR_IN_OUT
    stS : ST_ReportSet;
  END_VAR

F_ReportSetOk := F_ReportSetWhy(stS := stS) = E_UtError.None;

END_FUNCTION