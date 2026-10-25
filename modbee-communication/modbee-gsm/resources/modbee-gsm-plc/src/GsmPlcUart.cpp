// ModBee GSM - the OpenPLC layer.
//
// Licensed under the GNU Affero General Public License, Version 3, WITH
// ADDITIONAL TERMS - see LICENSE. Commercial use requires a separate licence.
//
// See GsmPlcUart.h for why this exists.

#include "GsmPlcUart.h"

#if defined(ARDUINO_ARCH_ESP32)

#include <Arduino.h>
#include <string.h>

#include "driver/uart.h"
#include "esp_attr.h"
#include "esp_heap_caps.h"
#include "esp_intr_alloc.h"
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"
#include "hal/uart_ll.h"
#include "soc/uart_periph.h"

namespace gsmplc {

namespace {

// --- How big the interrupt's own rings are --------------------------------------
//
// RECEIVE, 1024 bytes. The ring has to hold whatever arrives while the
// service task cannot run, and the longest such window is a flash operation:
// with the cache off, neither core runs a task, only IRAM interrupts. A 4 kB
// sector erase is the longest one this firmware makes (~45 ms typical on the
// Node's flash; page writes are ~1 ms). At 115200 baud, 8N1, the modem sends
// 11.5 bytes a millisecond, so 45 ms is 518 bytes. 1024 is 89 ms: the erase
// twice over, or the erase plus 44 ms for the task to be scheduled after it,
// and the UART's own 128-byte FIFO is 11 ms more on top. Measured on the Node
// during a signed OTA over LTE: 0 bytes lost (see the commit).
//
// TRANSMIT, 512 bytes. The interrupt refills the FIFO from it with the cache
// off, so it too must be internal. Its size costs nothing but throughput: a
// write that does not fit is taken in part and resumed on the next poll (the
// transport contract), the task polls every 2 ms and is woken the moment the
// ring empties, and 512 bytes is 44 ms of line - the line never waits on it.
constexpr uint32_t kStageRxBytes = 1024;
constexpr uint32_t kStageTxBytes = 512;

// EVERYTHING THE INTERRUPT TOUCHES IS HERE, IN INTERNAL RAM: this block
// (DRAM_ATTR, a few dozen bytes) and the two staging rings (MALLOC_CAP_INTERNAL,
// taken in open() and freed in close()). With the cache off, PSRAM and flash
// cannot be read, and the interrupt runs precisely then.
struct Shared {
    uart_dev_t* hw = nullptr;
    uint8_t* rx = nullptr;
    uint32_t rxSize = 0;
    volatile uint32_t rxHead = 0;     // written by the interrupt only
    volatile uint32_t rxTail = 0;     // written by the mover only
    uint8_t* tx = nullptr;
    uint32_t txSize = 0;
    volatile uint32_t txHead = 0;     // written by the task only
    volatile uint32_t txTail = 0;     // written by the interrupt only
    volatile uint32_t fifoOverruns = 0;
    volatile uint32_t ringOverruns = 0;
    portMUX_TYPE mux = portMUX_INITIALIZER_UNLOCKED;
    intr_handle_t handle = nullptr;
    TaskHandle_t wake = nullptr;
};

DRAM_ATTR Shared s_uart;

// The FIFO raises its interrupt at this fill. 128 bytes deep: the 64 left
// above the mark are ~5.5 ms at 115200 baud of interrupt latency the link
// can absorb - far more than an IRAM interrupt ever sees, cache off or not.
constexpr uint16_t kRxFullAt = 64;
// And after this many bit times of silence, so the tail of a reply that does
// not reach the mark is delivered at once (3 characters).
constexpr uint16_t kRxIdleBits = 30;
// Refilled when the transmit FIFO drains below this.
constexpr uint16_t kTxRefillAt = 16;

constexpr uint32_t kRxBits = UART_INTR_RXFIFO_FULL | UART_INTR_RXFIFO_TOUT |
                             UART_INTR_RXFIFO_OVF;

void IRAM_ATTR wakeTask(Shared& u) {
    if (u.wake != nullptr) {
        BaseType_t woken = pdFALSE;
        vTaskNotifyGiveFromISR(u.wake, &woken);
        if (woken == pdTRUE) { portYIELD_FROM_ISR(); }
    }
}

void IRAM_ATTR onUart(void*) {
    Shared& u = s_uart;
    uart_dev_t* hw = u.hw;
    const uint32_t status = uart_ll_get_intsts_mask(hw);

    if (status & kRxBits) {
        uint32_t waiting = uart_ll_get_rxfifo_len(hw);
        uint32_t head = u.rxHead;
        while (waiting > 0) {
            uint8_t byte;
            uart_ll_read_rxfifo(hw, &byte, 1);
            waiting--;
            const uint32_t next = (head + 1u == u.rxSize) ? 0u : head + 1u;
            if (next == u.rxTail) {
                u.ringOverruns = u.ringOverruns + 1u;   // the task is not moving them
                continue;
            }
            u.rx[head] = byte;
            head = next;
        }
        u.rxHead = head;
        if (status & UART_INTR_RXFIFO_OVF) {
            u.fifoOverruns = u.fifoOverruns + 1u;
            uart_ll_rxfifo_rst(hw);
        }
        uart_ll_clr_intsts_mask(hw, status & kRxBits);
        wakeTask(u);
    }

    if (status & UART_INTR_TXFIFO_EMPTY) {
        bool drained = false;
        portENTER_CRITICAL_ISR(&u.mux);
        uint32_t room = uart_ll_get_txfifo_len(hw);
        uint32_t tail = u.txTail;
        while (room > 0 && tail != u.txHead) {
            uart_ll_write_txfifo(hw, &u.tx[tail], 1);
            tail = (tail + 1u == u.txSize) ? 0u : tail + 1u;
            room--;
        }
        u.txTail = tail;
        if (tail == u.txHead) {
            uart_ll_disable_intr_mask(hw, UART_INTR_TXFIFO_EMPTY);
            drained = true;
        }
        uart_ll_clr_intsts_mask(hw, UART_INTR_TXFIFO_EMPTY);
        portEXIT_CRITICAL_ISR(&u.mux);
        // Room for the rest of a long write: the task tops the ring up now
        // rather than at its next tick.
        if (drained) { wakeTask(u); }
    }
}

uint8_t* internalBuffer(size_t bytes) {
    return (uint8_t*)heap_caps_malloc(bytes, MALLOC_CAP_INTERNAL | MALLOC_CAP_8BIT);
}

// The receive ring is read only by tasks, never with the cache off, so it
// goes to PSRAM where there is any.
uint8_t* externalBuffer(size_t bytes) {
    uint8_t* memory = (uint8_t*)heap_caps_malloc(bytes, MALLOC_CAP_SPIRAM | MALLOC_CAP_8BIT);
    return memory != nullptr ? memory : internalBuffer(bytes);
}

void freeBuffer(uint8_t*& buffer) {
    if (buffer != nullptr) { heap_caps_free(buffer); }
    buffer = nullptr;
}

} // namespace

IramUart& iramUart() {
    static IramUart one;
    return one;
}

bool IramUart::holdsAnything() const {
    const Shared& u = s_uart;
    return _open || u.handle != nullptr || u.rx != nullptr || u.tx != nullptr ||
           _ring != nullptr;
}

bool IramUart::open(int port, uint32_t baud, int rxPin, int txPin, size_t rxBytes,
                    const char** why) {
    if (_open) { return true; }
    if (port < 0 || port >= SOC_UART_NUM) {
        *why = "PORT names a UART this chip does not have";
        return false;
    }
    if (holdsAnything()) {
        // A close that has not finished: the layer finishes it first.
        *why = "the modem's serial link is still closing";
        return false;
    }
    const uart_port_t num = (uart_port_t)port;
    Shared& u = s_uart;

    // The receive ring is the size RX_BUFFER asks for: the library caps every
    // modem read to it (receiveCapacity()). One slot more, which a ring keeps
    // empty, so it holds exactly that.
    _ringSize = (uint32_t)rxBytes + 1u;
    _ring = externalBuffer(_ringSize);
    u.rxSize = kStageRxBytes;
    u.rx = internalBuffer(u.rxSize);
    u.txSize = kStageTxBytes;
    u.tx = internalBuffer(u.txSize);
    if (_ring == nullptr || u.rx == nullptr || u.tx == nullptr) {
        close();
        *why = "no RAM for the modem's serial buffers";
        return false;
    }
    _ringHead = _ringTail = 0;
    u.rxHead = u.rxTail = 0;
    u.txHead = u.txTail = 0;
    _rxSize = rxBytes;

    uart_config_t config = {};
    config.baud_rate = (int)baud;
    config.data_bits = UART_DATA_8_BITS;
    config.parity = UART_PARITY_DISABLE;
    config.stop_bits = UART_STOP_BITS_1;
    config.flow_ctrl = UART_HW_FLOWCTRL_DISABLE;   // the HAT has no RTS/CTS
    config.source_clk = UART_SCLK_DEFAULT;
    if (uart_param_config(num, &config) != ESP_OK ||
        uart_set_pin(num, txPin, rxPin, UART_PIN_NO_CHANGE, UART_PIN_NO_CHANGE) != ESP_OK) {
        close();
        *why = "the modem's UART would not configure (baud or pins)";
        return false;
    }

    u.hw = UART_LL_GET_HW(num);
    uart_ll_disable_intr_mask(u.hw, UART_LL_INTR_MASK);
    uart_ll_clr_intsts_mask(u.hw, UART_LL_INTR_MASK);
    uart_ll_rxfifo_rst(u.hw);
    uart_ll_txfifo_rst(u.hw);
    uart_ll_set_rxfifo_full_thr(u.hw, kRxFullAt);
    uart_ll_set_rx_tout(u.hw, kRxIdleBits);
    uart_ll_set_txfifo_empty_thr(u.hw, kTxRefillAt);

    // ESP_INTR_FLAG_IRAM: kept enabled while the cache is off. ESP-IDF refuses
    // it for a handler outside IRAM, so a successful allocation is the check.
    if (esp_intr_alloc(uart_periph_signal[num].irq, ESP_INTR_FLAG_IRAM | ESP_INTR_FLAG_LOWMED,
                       &onUart, nullptr, &u.handle) != ESP_OK) {
        u.handle = nullptr;
        close();
        *why = "no IRAM interrupt for the modem's UART";
        return false;
    }
    uart_ll_ena_intr_mask(u.hw, kRxBits);

    _baud = baud;
    _open = true;
    return true;
}

void IramUart::stopInterrupt() {
    Shared& u = s_uart;
    _open = false;                      // write() and begin() refuse from here
    if (u.hw != nullptr) {
        portENTER_CRITICAL(&u.mux);
        uart_ll_disable_intr_mask(u.hw, UART_LL_INTR_MASK);
        uart_ll_clr_intsts_mask(u.hw, UART_LL_INTR_MASK);
        portEXIT_CRITICAL(&u.mux);
    }
    // Freed on the core it was allocated on (ESP-IDF does that itself), and
    // not while the handler runs there: after this no interrupt is in flight
    // and none will come, so nothing wakes a task that may be about to go.
    if (u.handle != nullptr) {
        esp_intr_free(u.handle);
        u.handle = nullptr;
    }
    u.wake = nullptr;
}

void IramUart::close() {
    stopInterrupt();
    Shared& u = s_uart;
    freeBuffer(u.rx);
    freeBuffer(u.tx);
    u.rxSize = u.txSize = 0;
    u.rxHead = u.rxTail = 0;
    u.txHead = u.txTail = 0;
    freeBuffer(_ring);
    _ringSize = 0;
    _ringHead = _ringTail = 0;
    _taskMoves = false;
}

size_t IramUart::drain() {
    Shared& u = s_uart;
    if (u.rx == nullptr || _ring == nullptr) { return 0; }
    const uint32_t head = u.rxHead;
    uint32_t tail = u.rxTail;
    uint32_t ringHead = _ringHead;
    const uint32_t ringTail = _ringTail;
    size_t moved = 0;
    while (tail != head) {
        const uint32_t next = (ringHead + 1u == _ringSize) ? 0u : ringHead + 1u;
        if (next == ringTail) { break; }   // the ring is full; the rest waits staged
        _ring[ringHead] = u.rx[tail];
        ringHead = next;
        tail = (tail + 1u == u.rxSize) ? 0u : tail + 1u;
        moved++;
    }
    _ringHead = ringHead;
    u.rxTail = tail;
    return moved;
}

size_t IramUart::readable() {
    if (_ring == nullptr) { return 0; }
    if (!_taskMoves) { drain(); }
    const uint32_t head = _ringHead, tail = _ringTail;
    return head >= tail ? head - tail : _ringSize - tail + head;
}

size_t IramUart::read(uint8_t* into, size_t length) {
    if (into == nullptr || length == 0 || _ring == nullptr) { return 0; }
    if (!_taskMoves) { drain(); }
    const uint32_t head = _ringHead;
    uint32_t tail = _ringTail;
    size_t taken = 0;
    while (taken < length && tail != head) {
        into[taken++] = _ring[tail];
        tail = (tail + 1u == _ringSize) ? 0u : tail + 1u;
    }
    _ringTail = tail;
    return taken;
}

size_t IramUart::write(const uint8_t* from, size_t length) {
    Shared& u = s_uart;
    if (from == nullptr || length == 0) { return 0; }
    // CLOSED: the modem is switched off and nobody is listening. The bytes go
    // nowhere, as they would down a wire to a module that is off, so a command
    // the library submits now (a socket's close after the stop) concludes by
    // its own time limit. Refusing them instead would leave it waiting to be
    // written for as long as the link stays closed - the engine times out a
    // command's reply, not its sending - and send it, stale, at the next open.
    if (!_open || u.tx == nullptr) { return length; }
    size_t taken = 0;
    portENTER_CRITICAL(&u.mux);
    uint32_t head = u.txHead;
    while (taken < length) {
        const uint32_t next = (head + 1u == u.txSize) ? 0u : head + 1u;
        if (next == u.txTail) { break; }              // full: the rest next poll
        u.tx[head] = from[taken++];
        head = next;
    }
    u.txHead = head;
    if (taken > 0) { uart_ll_ena_intr_mask(u.hw, UART_INTR_TXFIFO_EMPTY); }
    portEXIT_CRITICAL(&u.mux);
    return taken;
}

void IramUart::wakeOnReceive(void* task) { s_uart.wake = (TaskHandle_t)task; }

uint32_t IramUart::fifoOverruns() const { return s_uart.fifoOverruns; }
uint32_t IramUart::ringOverruns() const { return s_uart.ringOverruns; }

} // namespace gsmplc

#endif
