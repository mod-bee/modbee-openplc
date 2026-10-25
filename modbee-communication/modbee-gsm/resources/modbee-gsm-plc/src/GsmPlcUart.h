// ModBee GSM - the OpenPLC layer.
//
// Licensed under the GNU Affero General Public License, Version 3, WITH
// ADDITIONAL TERMS - see LICENSE. Commercial use requires a separate licence.

#pragma once

// =============================================================================
// THE MODEM'S UART ON AN ESP32, WITH AN INTERRUPT THAT RUNS FROM IRAM
// =============================================================================
//
// WHY NOT HardwareSerial. Measured on a Node UIO with the A7670 HAT, 2026-10-15:
// an MQTT OTA download over the modem lost bytes every few kilobytes
// (UART_FIFO_OVF_ERROR). The Arduino core's UART interrupt lives in flash
// (CONFIG_UART_ISR_IN_IRAM is off in the prebuilt core), so it cannot run
// while the flash cache is off - during every flash erase and write, the OTA's
// and the retained-value store's alike. The UART's own FIFO is 128 bytes,
// about 11 ms at 115200 baud; a sector erase holds the cache off for ~45 ms.
// The HAT wires only TXD and RXD - the module's RTS and CTS are not connected -
// so the modem cannot be told to wait. Every byte that arrived in such a window
// beyond the FIFO was gone, and with it an AT reply, a data notice or part of
// a socket payload.
//
// THIS DRIVER'S INTERRUPT IS IN IRAM, so it keeps running with the cache off:
// the FIFO is drained whatever the flash is doing. Allocated with
// ESP_INTR_FLAG_IRAM, which ESP-IDF only grants to a handler that is genuinely
// in IRAM, and touching nothing but registers (the HAL's inline uart_ll
// calls) and internal RAM.
//
// --- ONLY WHAT THE INTERRUPT TOUCHES IS IN INTERNAL RAM, AND IT IS SMALL ---
//
// Internal RAM is what Wi-Fi, TLS and the PLC's tasks all need (Wi-Fi alone
// needs ~25 kB free to join), so nothing here holds it that does not have to:
//
//   staging rings  internal, small: the interrupt's only buffers. Receive
//                  kStageRxBytes, transmit kStageTxBytes - see the .cpp for
//                  how each was sized.
//   receive ring   RX_BUFFER bytes, in PSRAM where the board has it. The
//                  service task moves the staged bytes into it; the library
//                  reads from it, and its size is receiveCapacity().
//
// And ALL OF IT ONLY WHILE THE MODEM IS IN USE: open() takes the rings and
// the interrupt, close() gives every byte back. The layer (ModBeeGsmPlc.cpp)
// opens it when GSM_MODEM wants the modem and closes it once it is switched
// off and quiet, so a PLC on Wi-Fi has its RAM back.
//
// One modem per PLC, so one instance; it owns its UART completely (the
// Arduino Serial object for that port must not be begun as well).

#if defined(ARDUINO_ARCH_ESP32)

#include <GsmTransport.h>
#include <stddef.h>
#include <stdint.h>

namespace gsmplc {

class IramUart : public GsmTransport {
public:
    // Configures the port, takes the rings and installs the interrupt. False,
    // with a reason, when the port, the pins or the memory are not there -
    // and then nothing is held.
    bool open(int port, uint32_t baud, int rxPin, int txPin, size_t rxBytes,
              const char** why);

    // Step one of closing: the interrupt is removed (no byte arrives and no
    // task is woken after this returns). The rings stay, so a task still
    // moving bytes is not pulled out from under.
    void stopInterrupt();

    // Step two: every ring freed. Only once nothing moves bytes any more.
    void close();

    bool isOpen() const { return _open; }
    // Rings or interrupt still held.
    bool holdsAnything() const;

    bool begin() override { return _open; }
    void end() override {}

    size_t readable() override;
    size_t read(uint8_t* into, size_t length) override;
    size_t write(const uint8_t* from, size_t length) override;
    bool isConnected() const override { return _open; }

    // RX_BUFFER: what the receive ring holds, also while closed - the library
    // caps every modem read to it.
    size_t receiveCapacity() const override { return _rxSize; }
    uint32_t bitsPerSecond() const override { return _baud; }
    const char* name() const override { return "uart-iram"; }

    // Moves what the interrupt staged into the receive ring. The service task
    // calls it; while that task runs nobody else may (setMover(true)). With
    // no task, readable() moves the bytes itself.
    size_t drain();
    void setMover(bool taskMoves) { _taskMoves = taskMoves; }

    // Bytes the hardware FIFO lost before the interrupt could take them, and
    // bytes the staging ring had no room for. Both zero on a healthy link.
    // Kept across close and open.
    uint32_t fifoOverruns() const;
    uint32_t ringOverruns() const;

    // A task to wake (a FreeRTOS notification) whenever bytes arrive or the
    // transmit ring has emptied, so the modem is serviced as its reply comes
    // in rather than at the next scan.
    void wakeOnReceive(void* task);

private:
    bool _open = false;
    bool _taskMoves = false;
    uint32_t _baud = 0;
    size_t _rxSize = 0;

    // The receive ring (PSRAM): written by drain(), read by read().
    uint8_t* _ring = nullptr;
    uint32_t _ringSize = 0;              // RX_BUFFER + 1, one slot kept empty
    volatile uint32_t _ringHead = 0;     // written by drain() only
    volatile uint32_t _ringTail = 0;     // written by read() only
};

// The one instance.
IramUart& iramUart();

} // namespace gsmplc

#endif
