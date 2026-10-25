/* Where a ModBee controller's randomness comes from.
 *
 * Licensed under the GNU Affero General Public License, Version 3, WITH
 * ADDITIONAL TERMS - see LICENSE. Commercial use requires a separate licence.
 *
 * ---------------------------------------------------------------------------
 *
 * WHY THIS FILE EXISTS, and it is not a preference.
 *
 * wolfSSL seeds itself per platform. On a host it reads /dev/urandom and this
 * file compiles to nothing. On Arduino it reaches wc_GenerateSeed's ARDUINO
 * branch, and for every board it does not recognise by name that branch is:
 *
 *     / * TODO: Pull requests appreciated for new targets.
 *       * Do *all* other Arduino boards support random()?
 *       * Probably not 100%, but most will likely work: * /
 *     rand = random();
 *
 * Arduino's random() is a DETERMINISTIC PRNG. Unseeded it returns the same
 * sequence on every boot, so a controller would generate the same "private"
 * key every time it started, and every unit off the same production line would
 * generate the SAME key as every other. A key anyone can reproduce is not a
 * key, and the failure is completely silent: TLS negotiates, the certificate
 * looks right, the fingerprint is stable - it is stable because it is fixed.
 *
 * wolfSSL recognises three boards by name (SAMD_NANO_33_IOT, RP2040, SAM_DUE).
 * This library claims six architectures. So the seed is named here, per
 * architecture, and an architecture that has not been checked FAILS TO BUILD.
 * A build error on a desk is cheap; a predictable key on a panel is not, and
 * nobody would ever find it by looking.
 */

#include "user_settings.h"

#if defined(MODBEE_WOLFSSL_CUSTOM_SEED)

#include <stdint.h>
#include <string.h>

/* --- ESP32 -------------------------------------------------------------- */
#if defined(ESP32) || defined(ARDUINO_ARCH_ESP32)
    #include <esp_system.h>
    #include <esp_random.h>
    #define MODBEE_SEED_WORD()   ((uint32_t)esp_random())
    #define MODBEE_SEED_SOURCE   "ESP32 hardware RNG (esp_random)"

/* --- ESP8266 ------------------------------------------------------------ */
#elif defined(ESP8266) || defined(ARDUINO_ARCH_ESP8266)
    /* The RNG register the SDK's os_random() reads. Documented by Espressif
     * as hardware-backed and usable before WiFi is up. */
    #include <Arduino.h>
    #ifndef RANDOM_REG32
        #define RANDOM_REG32 (*(volatile uint32_t*)0x3FF20E44UL)
    #endif
    #define MODBEE_SEED_WORD()   ((uint32_t)RANDOM_REG32)
    #define MODBEE_SEED_SOURCE   "ESP8266 hardware RNG register"

/* --- RP2040 ------------------------------------------------------------- */
#elif defined(ARDUINO_ARCH_RP2040) || defined(PICO_RP2040)
    /* The ring-oscillator entropy the SDK exposes. wolfSSL already vouches
     * for random() here, and this is what the core implements it with. */
    #include <Arduino.h>
    #if defined(__has_include)
        #if __has_include(<pico/rand.h>)
            #include <pico/rand.h>
            #define MODBEE_SEED_WORD()   ((uint32_t)get_rand_32())
            #define MODBEE_SEED_SOURCE   "RP2040 ring oscillator (pico get_rand_32)"
        #endif
    #endif
    #ifndef MODBEE_SEED_WORD
        #define MODBEE_SEED_WORD()   ((uint32_t)random())
        #define MODBEE_SEED_SOURCE   "RP2040 core random()"
    #endif

/* --- STM32 -------------------------------------------------------------- */
#elif defined(ARDUINO_ARCH_STM32) || defined(STM32_CORE_VERSION)
    /* Most STM32 parts carry an RNG peripheral and the core exposes it as
     * HAL_RNG_GenerateRandomNumber. A part WITHOUT one must not silently fall
     * back to random(), so it is an error rather than a warning - and the
     * verdict comes before the headers, for the reason given under SAMD. */
    #if !defined(HAL_RNG_MODULE_ENABLED)
        #error "modbee-mqtt: this STM32 has no RNG peripheral enabled. Enable HAL_RNG_MODULE_ENABLED in the core's hal_conf, or the TLS key would come from a predictable sequence."
    #endif
    #include <Arduino.h>
    #if defined(HAL_RNG_MODULE_ENABLED)
        extern RNG_HandleTypeDef hrng;
        static uint32_t modbee_stm32_word(void) {
            uint32_t value = 0;
            if (HAL_RNG_GenerateRandomNumber(&hrng, &value) != HAL_OK) return 0;
            return value;
        }
        #define MODBEE_SEED_WORD()   modbee_stm32_word()
        #define MODBEE_SEED_SOURCE   "STM32 RNG peripheral (HAL_RNG)"
    #else
        #error "modbee-mqtt: this STM32 has no RNG peripheral enabled. Enable HAL_RNG_MODULE_ENABLED in the core's hal_conf, or the TLS key would come from a predictable sequence."
    #endif

/* --- SAMD --------------------------------------------------------------- */
#elif defined(ARDUINO_ARCH_SAMD)
    /* THE VERDICT FIRST, THEN THE HEADERS. A part that is going to be refused
     * must be refused for the reason that matters, not for a missing include
     * it was only going to need if it had passed. */
    #if !defined(__SAMD51__) && !defined(ARDUINO_SAMD_NANO_33_IOT)
        #error "modbee-mqtt: this SAMD part has no true RNG (SAMD21 does not). Arduino random() is deterministic, so a TLS key made here would be the same on every boot and on every unit. Use a SAMD51, or supply MODBEE_SEED_WORD for a real entropy source on this board."
    #endif
    #include <Arduino.h>
    #if defined(__SAMD51__)
        /* SAMD51 has a true RNG; SAMD21 does not, and its random() is the
         * ordinary deterministic one. */
        static uint32_t modbee_samd51_word(void) {
            MCLK->APBCMASK.bit.TRNG_ = 1;
            TRNG->CTRLA.bit.ENABLE = 1;
            while (!TRNG->INTFLAG.bit.DATARDY) { }
            return (uint32_t)TRNG->DATA.reg;
        }
        #define MODBEE_SEED_WORD()   modbee_samd51_word()
        #define MODBEE_SEED_SOURCE   "SAMD51 true RNG"
    #else
        /* wolfSSL names the Nano 33 IoT as tested; its core backs random()
         * with the NINA module's entropy. The guard above has already refused
         * anything that is neither this nor a SAMD51. */
        #define MODBEE_SEED_WORD()   ((uint32_t)random())
        #define MODBEE_SEED_SOURCE   "Nano 33 IoT core random()"
    #endif

/* --- mbed --------------------------------------------------------------- */
#elif defined(ARDUINO_ARCH_MBED)
    /* The verdict before the headers, as above. */
    #if !defined(__has_include)
        #error "modbee-mqtt: this compiler has no __has_include, so an mbed board's TRNG cannot be found. Supply MODBEE_SEED_WORD for this board's entropy source."
    #elif !__has_include(<mbed.h>)
        #error "modbee-mqtt: this mbed target exposes no TRNG this build can find. mbed's random() is deterministic, so a TLS key made here would repeat. Supply MODBEE_SEED_WORD for this board's entropy source."
    #endif
    #include <Arduino.h>
    #if defined(__has_include)
        #if __has_include(<mbed_rand.h>) || __has_include(<drivers/TrueRandomNumberGenerator.h>)
            #include <mbed.h>
            static uint32_t modbee_mbed_word(void) {
                uint32_t value = 0;
                size_t got = 0;
                if (mbed::TrueRandomNumberGenerator().get_bytes(
                        (uint8_t*)&value, sizeof value, &got) != 0) {
                    return 0;
                }
                return value;
            }
            #define MODBEE_SEED_WORD()   modbee_mbed_word()
            #define MODBEE_SEED_SOURCE   "mbed TRNG"
        #endif
    #endif
    #ifndef MODBEE_SEED_WORD
        #error "modbee-mqtt: this mbed target exposes no TRNG this build can find. mbed's random() is deterministic, so a TLS key made here would repeat. Supply MODBEE_SEED_WORD for this board's entropy source."
    #endif

#else
    #error "modbee-mqtt: no entropy source is known for this board, and wolfSSL's fallback for an unrecognised Arduino target is random() - a deterministic sequence, so every unit would generate the same private key. Add this architecture to resources/wolfssl/modbee-seed.c with a real source before using TLS on it."
#endif

/* The one function wolfSSL calls. Zero on success, as its own documentation
 * for CUSTOM_RAND_GENERATE_SEED says.
 *
 * A word at a time and memcpy'd rather than cast, because `output` carries no
 * alignment guarantee and an unaligned 32-bit store is a fault on several of
 * these parts. */
int modbee_wolfssl_seed(unsigned char* output, unsigned int size)
{
    if (output == 0) return -1;

    while (size > 0) {
        const uint32_t word = MODBEE_SEED_WORD();
        unsigned int take = sizeof word;
        if (take > size) take = size;
        memcpy(output, &word, take);
        output += take;
        size -= take;
    }
    return 0;
}

/* Visible in a build log, so which source a board actually got is a fact
 * somebody can check rather than infer. */
const char* modbee_wolfssl_seed_source(void) { return MODBEE_SEED_SOURCE; }

#endif /* MODBEE_WOLFSSL_CUSTOM_SEED */
