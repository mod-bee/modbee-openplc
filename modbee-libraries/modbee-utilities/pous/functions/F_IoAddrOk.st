(* F_IoAddrOk — an address the IO maps can keep: a known source and a module of at most 127. *)

FUNCTION F_IoAddrOk : BOOL
  VAR_INPUT
    eSrc : E_IoSrc;
    nModule : USINT;
  END_VAR

CASE eSrc OF
  E_IoSrc.None, E_IoSrc.Board, E_IoSrc.I2c, E_IoSrc.Field, E_IoSrc.Remote:
    F_IoAddrOk := nModule <= 127;
ELSE
  F_IoAddrOk := FALSE;
END_CASE;

END_FUNCTION