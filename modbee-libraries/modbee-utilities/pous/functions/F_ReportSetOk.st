(* the settings of one reported value are good (private to FB_Report and FB_ReportArray) *)

FUNCTION F_ReportSetOk : BOOL
  VAR_IN_OUT
    stSettings : ST_ReportSet; (* the settings to check *)
  END_VAR

F_ReportSetOk := F_ReportSetWhy(stSettings := stSettings) = E_UtError.None;

END_FUNCTION