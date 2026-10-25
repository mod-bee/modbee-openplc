(* How the controller itself is doing - for diagnosis on site. Refreshed once a
second.

HEAP_FREE     internal RAM free now, bytes.
HEAP_MIN      the least it has been since the board started. Watch this: a
              figure that keeps falling over days is a leak.
HEAP_LARGEST  the largest single block that could be allocated now. Much
              smaller than HEAP_FREE means the heap is fragmented.
PSRAM_FREE    external RAM free, bytes.
PSRAM_SIZE    external RAM fitted. 0 on a board without PSRAM.
STACK_MIN     the smallest stack margin among the PLC's tasks, bytes - how
              close the deepest call has come to overflowing. Under about
              512 is worth a look.
STACK_TASK    the task it belongs to (its IEC task name, or plc_modbus,
              plc_protocols, plc_dispatch for the firmware's own).
UPTIME        since the board started.
RESET_REASON  why it last started.
                UIO_RST_POWER_ON, UIO_RST_SOFTWARE (RESTART, an update),
                UIO_RST_PANIC (a crash), UIO_RST_INT_WDT / UIO_RST_TASK_WDT /
                UIO_RST_OTHER_WDT (a watchdog: something hung),
                UIO_RST_BROWNOUT (the supply dipped), UIO_RST_DEEP_SLEEP,
                UIO_RST_EXTERNAL (the reset pin), ...
PROGRAM_ID    the program's identity (its MD5, as the editor's debugger sees
              it). Tells which program is on a board.
FIRMWARE      the firmware and the ESP-IDF it was built with.
STATUS        UIO_OK; UIO_UNSUPPORTED on the Runtime.

---

  info();
  STS.heapMin := info.HEAP_MIN;
  STS.resetReason := info.RESET_REASON;

A PANIC OR A WATCHDOG IN RESET_REASON IS THE ONE TO ALARM ON: the board
restarted by itself. A board that keeps restarting on a watchdog usually has a
task that takes too long (see STACK_TASK and the debugger's task statistics); a
brownout points at the supply, not the program.

No inputs: call it anywhere, once. The heap figures walk the heap, so it reads
them only once a second. *)

FUNCTION_BLOCK SYS_INFO
  VAR_OUTPUT
    HEAP_FREE : UDINT;
    HEAP_MIN : UDINT;
    HEAP_LARGEST : UDINT;
    PSRAM_FREE : UDINT;
    PSRAM_SIZE : UDINT;
    STACK_MIN : UDINT;
    STACK_TASK : STRING(16);
    UPTIME : TIME;
    RESET_REASON : UIO_RESET;
    PROGRAM_ID : STRING(32);
    FIRMWARE : STRING(30);
    STATUS : UIO_RESULT;
  END_VAR
  VAR
    fbAt : UDINT;
    fbRead : BOOL;
  END_VAR
#include <NodeUioAPI.h>
#include <cstdio>

// The program's identity and the firmware version are in the sketch's own
// headers, which sit beside this file in the build. Looked for rather than
// assumed, so a build without them still compiles.
#if defined(ARDUINO)
#if __has_include("defines.h")
#include "defines.h"
#endif
#if __has_include("openplc_version.h")
#include "openplc_version.h"
#endif
#include <esp_idf_version.h>
#endif

UIO_RESULT uio_status(UioResult result);
uint32_t uio_nowMs();
strucpp::IEC_TIME uio_timeOfMs(uint32_t milliseconds);

void setup()
{
  HEAP_FREE = 0;
  HEAP_MIN = 0;
  HEAP_LARGEST = 0;
  PSRAM_FREE = 0;
  PSRAM_SIZE = 0;
  STACK_MIN = 0;
  STACK_TASK = "";
  UPTIME = uio_timeOfMs(0);
  RESET_REASON = UIO_RESET::UIO_RST_UNKNOWN;
  PROGRAM_ID = "";
  FIRMWARE = "";
  STATUS = UIO_RESULT::UIO_OK;
  fbAt = 0;
  fbRead = false;
}

void loop()
{
  const uint32_t now = uio_nowMs();
  if ((bool)fbRead && (uint32_t)(now - (uint32_t)fbAt) < 1000u) return;
  fbRead = true;
  fbAt = now;

  if (PROGRAM_ID.length() == 0) {
#if defined(PROGRAM_MD5)
    PROGRAM_ID = PROGRAM_MD5;
#endif
    char firmware[31];
#if defined(ARDUINO)
#if defined(OPENPLC_RUNTIME_VERSION)
    std::snprintf(firmware, sizeof firmware, "OpenPLC %s IDF %s", OPENPLC_RUNTIME_VERSION,
                  esp_get_idf_version());
#else
    std::snprintf(firmware, sizeof firmware, "IDF %s", esp_get_idf_version());
#endif
#else
    std::snprintf(firmware, sizeof firmware, "OpenPLC Runtime");
#endif
    FIRMWARE = firmware;
  }

  UioSysInfo info;
  const UioResult result = uio().systemInfo(info);
  STATUS = uio_status(result);
  if (result != UIO_OK) return;

  HEAP_FREE = info.heapFree;
  HEAP_MIN = info.heapMin;
  HEAP_LARGEST = info.heapLargest;
  PSRAM_FREE = info.psramFree;
  PSRAM_SIZE = info.psramSize;
  STACK_MIN = info.stackMin;
  STACK_TASK = info.stackTask;
  // TIME is signed nanoseconds: milliseconds since boot fit for 290 years.
  UPTIME = strucpp::IEC_TIME((strucpp::TIME_t)info.uptimeMs * strucpp::NS_PER_MS);
  RESET_REASON = info.resetReason <= (uint8_t)UIO_RESET::UIO_RST_CPU_LOCKUP
                     ? (UIO_RESET)info.resetReason
                     : UIO_RESET::UIO_RST_UNKNOWN;
}

END_FUNCTION_BLOCK