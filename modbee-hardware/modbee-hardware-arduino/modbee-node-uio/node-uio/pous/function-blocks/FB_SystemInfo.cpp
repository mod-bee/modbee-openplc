(* How the controller itself is doing - for diagnosis on site. Refreshed once a
second.

nHeapFreeBytes  internal RAM free now, bytes.
nHeapLowestBytes  the least it has been since the board started. Watch this: a
              figure that keeps falling over days is a leak.
nHeapLargestBlockBytes  the largest single block that could be allocated now. Much
              smaller than nHeapFreeBytes means the heap is fragmented.
nPsramFreeBytes  external RAM free, bytes.
nPsramSizeBytes  external RAM fitted. 0 on a board without PSRAM.
nStackLowestMarginBytes  the smallest stack margin among the PLC's tasks, bytes - how
              close the deepest call has come to overflowing. Under about
              512 is worth a look.
sStackLowestTask  the task it belongs to (its IEC task name, or plc_modbus,
              plc_protocols, plc_dispatch for the firmware's own).
tUptime       since the board started.
eResetReason  why it last started.
                UIO_RST_POWER_ON, UIO_RST_SOFTWARE (FB_Restart, an update),
                UIO_RST_PANIC (a crash), UIO_RST_INT_WDT / UIO_RST_TASK_WDT /
                UIO_RST_OTHER_WDT (a watchdog: something hung),
                UIO_RST_BROWNOUT (the supply dipped), UIO_RST_DEEP_SLEEP,
                UIO_RST_EXTERNAL (the reset pin), ...
sProgramId    the program's identity (its MD5, as the editor's debugger sees
              it). Tells which program is on a board.
sFirmwareVersion  the firmware and the ESP-IDF it was built with.
eErrorId      UIO_OK; UIO_UNSUPPORTED on the Runtime.

---

  info();
  STS.heapMin := info.nHeapLowestBytes;
  STS.resetReason := info.eResetReason;

A PANIC OR A WATCHDOG IN eResetReason IS THE ONE TO ALARM ON: the board
restarted by itself. A board that keeps restarting on a watchdog usually has a
task that takes too long (see sStackLowestTask and the debugger's task statistics); a
brownout points at the supply, not the program.

No inputs: call it anywhere, once. The heap figures walk the heap, so it reads
them only once a second. *)

FUNCTION_BLOCK FB_SystemInfo
  VAR_OUTPUT
    nHeapFreeBytes : UDINT; (* internal RAM free now, bytes *)
    nHeapLowestBytes : UDINT; (* the least internal RAM free since start, bytes; falling over days = a leak *)
    nHeapLargestBlockBytes : UDINT; (* the largest block that could be allocated now, bytes *)
    nPsramFreeBytes : UDINT; (* external RAM (PSRAM) free, bytes *)
    nPsramSizeBytes : UDINT; (* external RAM fitted, bytes; 0 = none *)
    nStackLowestMarginBytes : UDINT; (* the smallest stack margin among the PLC's tasks, bytes; under about 512 is worth a look *)
    sStackLowestTask : STRING(16); (* the task that margin belongs to *)
    tUptime : TIME; (* time since the board started *)
    eResetReason : E_ResetReason; (* why it last started (power-on, software, crash, watchdog, brownout ...) *)
    sProgramId : STRING(32); (* the program's identity (MD5, as the debugger sees it) *)
    sFirmwareVersion : STRING(30); (* the firmware and the ESP-IDF it was built with *)
    eErrorId : E_UioResult; (* UIO_OK; UIO_UNSUPPORTED on the Runtime *)
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

E_UIORESULT uio_status(UioResult result);
uint32_t uio_nowMs();
strucpp::IEC_TIME uio_timeOfMs(uint32_t milliseconds);

void setup()
{
  nHeapFreeBytes = 0;
  nHeapLowestBytes = 0;
  nHeapLargestBlockBytes = 0;
  nPsramFreeBytes = 0;
  nPsramSizeBytes = 0;
  nStackLowestMarginBytes = 0;
  sStackLowestTask = "";
  tUptime = uio_timeOfMs(0);
  eResetReason = E_RESETREASON::UIO_RST_UNKNOWN;
  sProgramId = "";
  sFirmwareVersion = "";
  eErrorId = E_UIORESULT::UIO_OK;
  fbAt = 0;
  fbRead = false;
}

void loop()
{
  const uint32_t now = uio_nowMs();
  if ((bool)fbRead && (uint32_t)(now - (uint32_t)fbAt) < 1000u) return;
  fbRead = true;
  fbAt = now;

  if (sProgramId.length() == 0) {
#if defined(PROGRAM_MD5)
    sProgramId = PROGRAM_MD5;
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
    sFirmwareVersion = firmware;
  }

  UioSysInfo info;
  const UioResult result = uio().systemInfo(info);
  eErrorId = uio_status(result);
  if (result != UIO_OK) return;

  nHeapFreeBytes = info.heapFree;
  nHeapLowestBytes = info.heapMin;
  nHeapLargestBlockBytes = info.heapLargest;
  nPsramFreeBytes = info.psramFree;
  nPsramSizeBytes = info.psramSize;
  nStackLowestMarginBytes = info.stackMin;
  sStackLowestTask = info.stackTask;
  // TIME is signed nanoseconds: milliseconds since boot fit for 290 years.
  tUptime = strucpp::IEC_TIME((strucpp::TIME_t)info.uptimeMs * strucpp::NS_PER_MS);
  eResetReason = info.resetReason <= (uint8_t)E_RESETREASON::UIO_RST_CPU_LOCKUP
                     ? (E_RESETREASON)info.resetReason
                     : E_RESETREASON::UIO_RST_UNKNOWN;
}

END_FUNCTION_BLOCK