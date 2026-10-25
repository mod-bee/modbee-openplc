/* The header a ModBee sketch includes to make wolfSSL reachable.
 *
 * Licensed under the GNU Affero General Public License, Version 3, WITH
 * ADDITIONAL TERMS - see LICENSE. Commercial use requires a separate licence.
 *
 * ---------------------------------------------------------------------------
 *
 * IT EXISTS FOR TWO REASONS AND BOTH WERE MEASURED.
 *
 * 1. ARDUINO-CLI FINDS A LIBRARY BY A TOP-LEVEL HEADER. It resolves
 *    `#include <X>` by matching X against the top level of a library's src/,
 *    not against a path inside it - so <wolfssl/ssl.h> names nothing it can
 *    resolve, the library is never added to the include path, and
 *    src/MqttFeatures.h's __has_include then correctly answers "there is no
 *    engine". Measured: with the path present a board TU resolves
 *    MQTT_TLS_ENGINE_NAME to "wolfSSL", and without it to "none".
 *
 * 2. WOLFSSL'S OPENSSL COMPATIBILITY LAYER CANNOT SHARE A TRANSLATION UNIT
 *    WITH WiFiClientSecure ON AN ESP32. That header reaches, through
 *    NetworkClientSecure -> ssl_client.h -> mbedtls/ssl.h -> psa/crypto.h, the
 *    ESP32 ROM header esp32/rom/sha.h, which defines SHA_CTX. wolfSSL's
 *    openssl/sha.h typedefs SHA_CTX as well, and the two are different types.
 *    Including <wolfssl.h> - which pulls <wolfssl/ssl.h> and with it the whole
 *    compatibility layer - therefore breaks any file that also talks to the
 *    board's own TLS client.
 *
 * So this header does the first job without the second's cost: it is at the
 * top level where arduino-cli can match it, and it brings in the CONFIGURATION
 * only. No compatibility layer, no SHA_CTX, nothing that collides with
 * anything the Arduino core declares.
 *
 * The files that genuinely use wolfSSL - MqttIdentity.cpp and the wolfSSL
 * transports - include the real headers themselves, in their own translation
 * units, where WiFiClientSecure is not present. That separation is not
 * incidental: it is what lets one board carry both.
 */

#ifndef MODBEE_WOLFSSL_H
#define MODBEE_WOLFSSL_H

#ifndef WOLFSSL_USER_SETTINGS
#define WOLFSSL_USER_SETTINGS
#endif

#include <wolfssl/wolfcrypt/settings.h>

#endif /* MODBEE_WOLFSSL_H */
