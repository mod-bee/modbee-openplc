(* F_IoAddrOk — an address the IO maps can keep: a known source and a module of at most 127. *)

FUNCTION F_IoAddrOk : BOOL
  VAR_INPUT
    eSource : E_IoSrc; (* where the channel is: None (not on this site), Board, I2c, Field or Remote *)
    nModuleNumber : USINT; (* the module number within that source (0..127) *)
  END_VAR

CASE eSource OF
  E_IoSrc.None, E_IoSrc.Board, E_IoSrc.I2c, E_IoSrc.Field, E_IoSrc.Remote:
    F_IoAddrOk := nModuleNumber <= 127;
ELSE
  F_IoAddrOk := FALSE;
END_CASE;

END_FUNCTION