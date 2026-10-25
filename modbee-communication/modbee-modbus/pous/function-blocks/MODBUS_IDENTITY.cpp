(* What this node says it is when a client asks. Optional.

NODE      which node. Must be wired.
VENDOR    who made it.
PRODUCT   what it is.
REVISION  which version.

APPLIED  the nameplate reached the node.
ERROR    it did not.
STATUS   why. MODBUS_OK when fine.

---

  name( NODE := node, VENDOR := 'Example Co', PRODUCT := 'Intake RTU',
        REVISION := '1.0' );

This is the answer to function code 43, the one a commissioning engineer reads
off a handheld tool or off MODBUS_DEVICE's VENDOR, PRODUCT and REVISION pins at
the other end of the wire.

WORTH SETTING ON ANYTHING SOMEBODY ELSE WILL COMMISSION. A panel with six
identical-looking nodes on one segment is a panel where the only way to tell
which is which is to ask them, and a device that answers "ModBee / Intake RTU"
has just saved somebody an afternoon with a wiring drawing.

Leave it out and the node simply does not answer function code 43, which is
what most devices on most sites do. *)

FUNCTION_BLOCK MODBUS_IDENTITY
  VAR_IN_OUT
    NODE : MODBUS_NODE;
  END_VAR
  VAR_INPUT
    VENDOR : STRING(32);
    PRODUCT : STRING(32);
    REVISION : STRING(32);
  END_VAR
  VAR_OUTPUT
    APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : MODBUS_RESULT;
  END_VAR
  VAR
  END_VAR

#include <ModBeeModbus.h>

// The node's server half, defined by MODBUS_NODE. A nameplate is something a
// server answers with, so this block hands it to its node.
MODBUS_RESULT mbServe(ModbusAPI* mb, uint8_t kind, bool onWifi, uint16_t tcpPort,
                      uint8_t maxClients, mb_time_t idleMs, uint8_t unitId,
                      bool& opened, const char*& why);

strucpp::XWORD_t mb_currentTask();
bool mb_inTask(strucpp::XWORD_t owner);

void setup()
{
    APPLIED = false;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
}

void loop()
{
    if (!mb_inTask((strucpp::XWORD_t)NODE.FBTASK)) {   // one task per node: see MODBUS_ARDUINO
        ERROR = true;
        STATUS = MODBUS_RESULT::MODBUS_WRONG_TASK;
        return;
    }
    // Not guarded on NODE.READY: like MODBUS_CONFIG, this has to have run
    // before the link is built, which is why the node waits a scan.
    NODE.FBSERVE = (strucpp::XWORD_t)(uintptr_t)&mbServe;
    NODE.FBVENDOR = VENDOR;
    NODE.FBPRODUCT = PRODUCT;
    NODE.FBREVISION = REVISION;

    // Settable on a live link too, so a nameplate corrected while running
    // takes effect without reopening anything.
    ModbusAPI* mb = (ModbusAPI*)(uintptr_t)(strucpp::XWORD_t)NODE.FBAPI;
    if (mb && (bool)NODE.READY && VENDOR.length() > 0) {
        mb->identity(VENDOR.c_str(), PRODUCT.c_str(), REVISION.c_str());
    }

    APPLIED = true;
    ERROR = false;
    STATUS = MODBUS_RESULT::MODBUS_OK;
}

END_FUNCTION_BLOCK