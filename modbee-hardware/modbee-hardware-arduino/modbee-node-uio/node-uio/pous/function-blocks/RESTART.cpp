(* Restarts the controller, and says why it last started.

REQ      rising edge: restart now, as the reset button would.

REASON   why this run started: the ESP-IDF reset reason. 1 power-on,
         3 a software restart (this block), 4 a crash, 5 to 7 a watchdog,
         8 waking from deep sleep, 9 a brownout. 0 off the board.
RESTARTED  this run started from a software restart (REASON 3).

---

FOR A SITE THAT HAS TO RECOVER BY ITSELF. A link supervisor that has tried the
modem and the HAT power and still has no link asks for one controlled restart;
this is the block that does it. Wire the request straight in:

  sup( LinkOk := sp.BORN, RebootAllowed := NOT pumpRunning, Data := supCfg );
  reboot( REQ := sup.RebootReq );

RETAINED VALUES ARE SAVED FIRST. Before restarting, the block has the firmware
save the program's retained values (OpenPLC's built-in store), so a change the
store was still holding within its save period is kept. The restart waits for
that save, about 10 to 50 ms, and happens whatever its result. On firmware too
old to offer the save, the values are only as fresh as the store's last save:
leave the Persistent Storage save period after the change you need kept.

Holding REQ TRUE restarts once: after the restart the edge has to come again. *)

FUNCTION_BLOCK RESTART
  VAR_INPUT
    REQ : BOOL;
  END_VAR
  VAR_OUTPUT
    REASON : USINT;
    RESTARTED : BOOL;
  END_VAR
  VAR
    lastReq : BOOL;
  END_VAR
#include <NodeUioAPI.h>

void setup()
{
  lastReq = true;  // a request already TRUE at start-up is not an edge
  REASON = uio().resetReason();
  RESTARTED = (REASON == 3);
}

void loop()
{
  const bool req = (bool)REQ;
  if (req && !(bool)lastReq) {
    uio().restart();
  }
  lastReq = req;
}

END_FUNCTION_BLOCK