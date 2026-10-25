/* ModBee's wolfSSL configuration.
 *
 * Licensed under the GNU Affero General Public License, Version 3, WITH
 * ADDITIONAL TERMS - see LICENSE. Commercial use requires a separate licence.
 * wolfSSL itself is GPLv3; see COPYING and LICENSING beside this file.
 *
 * ---------------------------------------------------------------------------
 *
 * This is the ONE file under resources/wolfssl/ that is a decision rather than
 * a copy. Everything else is upstream's own Arduino packaging, reproduced by
 * internal/sync-wolfssl.sh, and must not be edited by hand.
 *
 * WHAT IT HAS TO MATCH. The blocks are built against the modbee-mqtt C++
 * library, and that library needs exactly these capabilities:
 *
 *   OPENSSL_EXTRA / OPENSSL_ALL   src/transport/ speaks OpenSSL's names, and
 *                                 wolfSSL's compatibility layer provides them.
 *   WOLFSSL_CERT_GEN / _EXT       MqttIdentity mints a self-signed
 *   WOLFSSL_KEY_GEN               certificate so a broker can serve TLS
 *                                 without anybody having issued it one.
 *   HAVE_ECC                      P-256: about a second on an ESP32, where
 *                                 RSA-2048 is minutes.
 *   WOLFSSL_ALT_NAMES             a certificate a verifying client can match.
 *   HAVE_SNI                      a broker serving several names.
 *
 * The values below are the ones the library was actually tested with - 22/22
 * ctest suites and the whole TLS matrix, client and server - rather than a set
 * assembled by reading documentation.
 *
 * ANYTHING RETYPED, REMOVED OR REORDERED HERE CHANGES WHAT COMPILES. Adding a
 * capability is safe; taking one away is how a board ends up unable to make
 * its own certificate, and the failure is at run time on a panel rather than
 * at build time on a desk.
 */

#ifndef MODBEE_WOLFSSL_USER_SETTINGS_H
#define MODBEE_WOLFSSL_USER_SETTINGS_H

#ifdef __cplusplus
extern "C" {
#endif

/* --- The platform ------------------------------------------------------ */

/* Guarded: the Runtime's build also passes -DWOLFSSL_USER_SETTINGS, and an
 * unguarded definition made every wolfSSL translation unit warn that it was
 * redefined - two thousand lines of an upload log that hid anything real. */
#ifndef WOLFSSL_USER_SETTINGS
#define WOLFSSL_USER_SETTINGS
#endif
#define WOLFSSL_IGNORE_FILE_WARN      /* the packaging flattens the tree */

/* EVERY Arduino board, not a list of the ones somebody remembered. ARDUINO is
 * defined by the core on all of them, and the specific architecture macros
 * only ever add to it - so a board nobody anticipated still lands here rather
 * than in the host branch, where it would be told it has a file system. */
#if defined(ARDUINO)
    #define WOLFSSL_ARDUINO
    #define NO_FILESYSTEM             /* a board has none to read a key from */

    /* WE SUPPLY THE I/O, so wolfSSL must not compile its own socket layer.
     *
     * Without this, wolfio.h is pulled in and wants the platform's socket
     * types - SOCKADDR, and everything under it - which a board does not have
     * where wolfSSL expects to find them. The build fails inside our own
     * MqttIdentity.cpp, on a type that has nothing to do with making a key.
     *
     * It is also the correct description of what happens here. On a board the
     * bytes reach the network through MqttStreamTransport over an Arduino
     * Client, and wolfSSL's part is the cryptography: an identity, a
     * certificate and a fingerprint to pin against. If a board ever serves TLS
     * itself, this is still the mode it does it in - with
     * wolfSSL_SetIOSend/SetIORecv over that same Client. */
    #define WOLFSSL_USER_IO

    /* AND NO SOCKETS AT ALL. OPENSSL_ALL turns on WOLFSSL_HAVE_BIO_ADDR
     * (wolfssl/ssl.h), whose WOLFSSL_BIO_ADDR union is declared in terms of
     * SOCKADDR and SOCKADDR_IN - and on Arduino wolfio.h only defines those
     * under WOLFSSL_DTLS. So the OpenSSL compatibility layer and the Arduino
     * platform do not agree with each other out of the box, and the build
     * fails inside OUR files on a type that has nothing to do with what they
     * are for. WOLFSSL_NO_SOCK is checked by that same guard, so declaring it
     * here stops BIO_ADDR ever being enabled.
     *
     * It is also true. On a board wolfSSL does cryptography; the bytes reach
     * the network through an Arduino Client. */
    #define WOLFSSL_NO_SOCK
    #define NO_WRITEV
    #define NO_MAIN_DRIVER
    #define SINGLE_THREADED
    #define NO_WOLFSSL_DIR
    /* Small stack: a scan cycle runs on a task stack measured in kilobytes,
     * and wolfSSL's default temporaries do not fit on one. */
    #define WOLFSSL_SMALL_STACK
#else
    /* The OpenPLC runtime, and a host build. It has a file system, threads and
     * a real entropy source, and MQTT_TLS's CERT_FILE / KEY_FILE pins are
     * paths - so the file system is not optional here. */
    #define WOLFSSL_PTHREADS
    #define HAVE_PTHREAD
    #define HAVE_THREAD_LS
    #define HAVE_ERRNO_H

    /* The operating system's trust store, which is what
     * SSL_CTX_set_default_verify_paths() reads. Without it a runtime cannot
     * verify a PUBLIC broker at all - AWS IoT, HiveMQ, a customer's platform -
     * because there would be no roots to verify against and no way to name
     * them. A board has no such store and pins or carries its own CA instead. */
    #define WOLFSSL_SYS_CA_CERTS

    /* tls13.c calls gettimeofday() from its generic branch and only includes
     * <sys/time.h> for macOS, FreeBSD, NuttX and RIOT - every other POSIX
     * target is expected to have brought it in through its configuration.
     * With an autotools or CMake build that happens in options.h; a vendored
     * tree has no options.h, so it happens here. Without it the call is an
     * implicit declaration, which on a 64-bit target truncates the returned
     * pointer and is a crash rather than a warning. */
    #include <sys/time.h>
#endif

/* --- Entropy ----------------------------------------------------------- */
/*
 * A key generated from a predictable seed is not a key. Named per platform
 * rather than left to wolfSSL's guess, because the guess on a bare board is
 * "use time(NULL)" and that is exactly the failure this line exists to stop.
 */
#if defined(ARDUINO)
    /* NOT WOLFSSL_ESPIDF on an ESP32, and upstream's own Arduino
     * user_settings.h goes to the trouble of `#undef WOLFSSL_ESPIDF` with the
     * comment "Make sure this is not an ESP-IDF file". The distinction is
     * real: an ESP-IDF build has FreeRTOS headers at <FreeRTOS.h>, while the
     * Arduino ESP32 core puts them at <freertos/FreeRTOS.h>, so declaring the
     * wrong one fails on a missing header a long way from anything to do with
     * TLS. */
    #undef WOLFSSL_ESPIDF

    /* THE SEED IS OURS ON EVERY BOARD, and this is the most important line in
     * this file.
     *
     * wolfSSL's wc_GenerateSeed knows three Arduino boards by name. For every
     * other one its fallback is `rand = random()`, under a comment that says
     * "Probably not 100%, but most will likely work". Arduino's random() is a
     * DETERMINISTIC PRNG: unseeded it returns the same sequence on every boot,
     * so a controller would mint the same "private" key every start and every
     * unit off a line would mint the SAME key as its neighbours. Nothing about
     * that is visible in operation - TLS negotiates, the certificate parses,
     * the fingerprint is stable because it is FIXED.
     *
     * This library claims esp32, esp8266, samd, mbed, rp2040 and stm32. So the
     * source is named per architecture in modbee-seed.c beside this file, and
     * an architecture that has not been checked is a #error rather than a
     * guess. A build failure on a desk is cheap. */
    #define MODBEE_WOLFSSL_CUSTOM_SEED
    int modbee_wolfssl_seed(unsigned char* output, unsigned int size);
    #define CUSTOM_RAND_GENERATE_SEED  modbee_wolfssl_seed
#endif

/* ===========================================================================
 * THE BOARD PROFILE - every Arduino build.
 *
 * A board does four things with wolfSSL and nothing else (src/transport/:
 * MqttStreamTlsListener, MqttTlsAccept, MqttIdentity):
 *   - serve TLS, as a broker, with its own certificate (no client
 *     certificates are asked for)
 *   - make that certificate: an EC P-256 key, self-signed, with extensions
 *   - load it back from PEM and fingerprint its key
 * So this is exactly that, and the full set below is for the OpenPLC runtime
 * and every host build, which have the flash to spare and need the rest
 * (RSA brokers, client connections, a system trust store).
 *
 * WHAT A CLIENT NEEDS TO CONNECT: TLS 1.2 or 1.3, ECDHE on P-256, an ECDSA
 * certificate, and AES-128-GCM with SHA-256 - which OpenSSL, mbedTLS (ESP32's
 * WiFiClientSecure), BearSSL (SSLClient) and every MQTT client in use offer.
 * TLS 1.2 stays because BearSSL and older embedded clients have nothing newer.
 *
 * Define MODBEE_WOLFSSL_BOARD_PROFILE on a host to build and test exactly this
 * set there (with MODBEE_WOLFSSL_BOARD_CLIENT for a test that dials it).
 * =========================================================================== */
#if defined(ARDUINO) || defined(MODBEE_WOLFSSL_BOARD_PROFILE)

/* Protocol: TLS 1.2, server only. 1.2 is what every client speaks - BearSSL
 * (SSLClient) and older embedded stacks have nothing newer - and with ECDHE,
 * AES-GCM and the extended master secret it is sound. TLS 1.3 costs about
 * 22 kB more on an ESP32; define MODBEE_WOLFSSL_BOARD_TLS13 to add it. */
#if defined(MODBEE_WOLFSSL_BOARD_TLS13)
    #define WOLFSSL_TLS13
    #define HAVE_HKDF
#endif
#define HAVE_TLS_EXTENSIONS
#define HAVE_SUPPORTED_CURVES
#define HAVE_EXTENDED_MASTER
#define HAVE_SNI
/* RFC 5746's renegotiation_info in the ServerHello. OpenSSL 3 REFUSES a
 * TLS 1.2 server that does not send it ("unsafe legacy renegotiation
 * disabled") - so without this, Mosquitto, Paho and every other OpenSSL
 * client could not connect to the board at all. Found by connecting one. */
#define HAVE_SERVER_RENEGOTIATION_INFO
#define NO_OLD_TLS
#define WOLFSSL_NO_TLS12_DOWNGRADE
#if !defined(MODBEE_WOLFSSL_BOARD_CLIENT)
    #define NO_WOLFSSL_CLIENT         /* a board dials TLS through its core's own client */
#endif
#define NO_ERROR_STRINGS             /* codes, not sentences: about 11 kB */
#define NO_SESSION_CACHE              /* a handful of clients, and RAM is scarce */

/* Public key: ECC P-256 only, single-precision maths, small code. */
#define HAVE_ECC
#define ECC_USER_CURVES               /* P-256 and nothing else */
#define ECC_TIMING_RESISTANT
#define WOLFSSL_SP_MATH               /* SP only: no general multi-precision maths */
#define WOLFSSL_SP_SMALL
#define WOLFSSL_HAVE_SP_ECC
#define NO_RSA
#define NO_DH

/* Certificates the board makes for itself. */
#define WOLFSSL_KEY_GEN
#define WOLFSSL_CERT_GEN
#define WOLFSSL_CERT_EXT
#define WOLFSSL_ALT_NAMES
#define WOLFSSL_BASE64_ENCODE         /* wc_DerToPem */

/* Symmetric: AES-128-GCM and SHA-256 (SHA-1 stays: the subject key id). */
#define HAVE_AESGCM
#define GCM_SMALL
#define NO_AES_192
#define NO_AES_256
#define NO_AES_CBC
#define HAVE_HASHDRBG
#define NO_MD5
#define NO_DSA
#define NO_RC4
#define NO_MD4
#define NO_DES3
#define NO_PSK
/* NOT NO_PWDBASED: wolfSSL guards i2d_X509_PUBKEY - the key fingerprint - behind it. */
#define NO_PKCS12
#define WOLFSSL_NO_SHAKE128
#define WOLFSSL_NO_SHAKE256
#define WOLFSSL_NO_ML_KEM

/* The C++ library's OpenSSL names: identity load and fingerprint. */
#define OPENSSL_EXTRA
#define WOLFSSL_ERROR_CODE_OPENSSL
#define HAVE_LIMITS_H
#define NO_OLD_RNGNAME
#define NO_OLD_WC_NAMES

#else /* ------------- the full set: OpenPLC runtime and host builds ------- */

/* --- Protocol ---------------------------------------------------------- */

#define WOLFSSL_TLS13

/* TLS 1.3 refuses to build without one finite-field DH group named, even for a
 * build that will only ever negotiate ECDHE - src/tls.c makes it a #error.
 * 2048 is the smallest RFC 7919 group and the one a broker offering FFDHE at
 * all is most likely to offer. Roughly a kilobyte of constants, and it is the
 * difference between "a site broker configured for FFDHE is unreachable" and
 * "it works" - which is not a trade worth making to save a kilobyte on a
 * controller. */
#define HAVE_FFDHE_2048

#define HAVE_TLS_EXTENSIONS
#define HAVE_SUPPORTED_CURVES
#define HAVE_EXTENDED_MASTER
#define HAVE_ENCRYPT_THEN_MAC
#define HAVE_SNI
#define HAVE_ALPN
#define HAVE_HKDF
#define WC_RSA_PSS

/* 1.0 and 1.1 are withdrawn. A plant that has to talk to something older
 * should say so deliberately rather than have this library quietly agree. */
#define NO_OLD_TLS
#define WOLFSSL_NO_TLS12_DOWNGRADE

/* --- Public key -------------------------------------------------------- */

#define HAVE_ECC
#define TFM_ECC256
#define ECC_SHAMIR
#define HAVE_ECC_ENCRYPT
#define WOLFSSL_KEY_GEN               /* MqttIdentity makes keys */
#define WOLFSSL_CERT_GEN              /*   ...and certificates   */
#define WOLFSSL_CERT_EXT              /* basicConstraints, keyUsage, SKID */
#define WOLFSSL_CERT_REQ
#define WOLFSSL_CERT_NAME_ALL
#define WOLFSSL_ALT_NAMES             /* subjectAltName, so hostnames match */

/* RSA stays. Not because we generate RSA keys - we do not - but because a
 * cloud broker's certificate is very often RSA, and a client that cannot
 * verify one cannot connect to AWS IoT, HiveMQ or most site Mosquittos. */
#define WOLFSSL_SP_MATH_ALL
#define WOLFSSL_HAVE_SP_RSA
#define WOLFSSL_HAVE_SP_ECC

/* --- Symmetric --------------------------------------------------------- */

#define HAVE_AESGCM
#define WOLFSSL_AES_COUNTER
#define WOLFSSL_AES_DIRECT
#define HAVE_AES_KEYWRAP
#define HAVE_CHACHA
#define HAVE_POLY1305
#define HAVE_ONE_TIME_AUTH
#define WOLFSSL_SHA384
#define WOLFSSL_SHA512
#define WOLFSSL_SHA224

/* --- Hardening ---------------------------------------------------------- */
/*
 * wolfSSL warns at compile time when these are absent, and it is right to.
 * They make the big-integer and EC routines take the same time whatever the
 * secret is, so the key cannot be recovered by watching how long an operation
 * took. A controller on a panel is not the classic threat model for that -
 * anyone who can measure it can usually open the enclosure - but the cost is
 * a few percent of an operation that happens once per connection, and the
 * alternative is a build that warns on every compile until somebody learns to
 * ignore warnings.
 */
#define TFM_TIMING_RESISTANT
#define ECC_TIMING_RESISTANT
#define WC_RSA_BLINDING

/* --- The compatibility layer the C++ library is written against -------- */

#define OPENSSL_EXTRA
/* OPENSSL_ALL ON A HOST, NOT ON A BOARD.
 *
 * It force-enables HAVE_SESSION_TICKET (settings.h, in the
 * OPENSSL_ALL/NGINX/HAPROXY block). wolfSSL's own Arduino defaults meanwhile
 * set NO_SESSION_CACHE - sensible for a constrained CLIENT, which is all a
 * board was until MqttStreamTlsListener existed.
 *
 * Tickets on, cache off, and the SERVER side compiled in is a combination
 * wolfSSL does not support. internal.c references TlsSessionCacheGetAndRdLock
 * and TlsSessionCacheUnlockRow under `HAVE_SESSION_TICKET && WOLFSSL_TLS13`;
 * ssl_sess.c only defines them under `!NO_SESSION_CACHE`. Everything compiles
 * and the LINK fails - and only once something instantiates the listener,
 * which is why an ESP32 firmware that merely had the header available built
 * perfectly well and a PlatformIO project that actually used it did not.
 *
 * A board serving TLS to a handful of plant clients has no use for session
 * resumption: the tickets cost RAM and save a reconnect nobody measures. On a
 * board MqttTlsAccept.cpp uses wolfSSL's native certificate-buffer API, so
 * OPENSSL_EXTRA carries every name it needs.
 *
 * A HOST still gets it, because MqttTlsListener.cpp - which only exists where
 * there are BSD sockets - calls SSL_CTX_get0_certificate, and that name is in
 * the wider surface. A host has the RAM for a session cache and so does not
 * hit the conflict.
 */
#if !defined(ARDUINO)
#define OPENSSL_ALL
#endif

/* THE ONE THAT DECIDES WHETHER ANY OF THIS IS CORRECT, and it is not obvious.
 *
 * Without it, wolfSSL's compatibility functions keep WOLFSSL's own return
 * conventions rather than OpenSSL's - and the two are not merely different,
 * they are INVERTED for at least one function this library depends on.
 * wolfcrypt/src/evp.c ends wolfSSL_EVP_PKEY_cmp with:
 *
 *     #if defined(WOLFSSL_ERROR_CODE_OPENSSL)
 *         ret = 1;   / * the keys match * /
 *     #else
 *         ret = 0;   / * success * /
 *     #endif
 *
 * So  means "the same key" with this defined and
 * "NOT the same key" without it. mq_tls::keyMatchesCertificate() tests for 1,
 * as it must on OpenSSL, so leaving this out made every matching key and
 * certificate look mismatched and no broker would start. It was found by
 * building the vendored tree and running the suite against it - the installed
 * wolfSSL had it, because --enable-opensslall sets it, and nothing in a
 * header would have said so.
 *
 * Which is the general point: this library is WRITTEN against OpenSSL's API,
 * so it needs OpenSSL's return codes, not a near-miss of them. */
#define WOLFSSL_ERROR_CODE_OPENSSL

/* The rest of what --enable-opensslall implies, named here so the vendored
 * build is the same configuration that passed the suites rather than a
 * near-neighbour of it. */
#define WOLFSSL_EITHER_SIDE           /* a context that has not chosen a side */
#define WOLFSSL_TICKET_HAVE_ID
#define WOLFSSL_BASE64_ENCODE         /* wc_DerToPem needs it */
#define HAVE_HASHDRBG                 /* the RNG behind every key */
#define HAVE_LIMITS_H
#define HAVE_DH_DEFAULT_PARAMS
#define WC_RSA_NO_PADDING
#define WOLFSSL_PSS_LONG_SALT
#define GCM_TABLE_4BIT
#define NO_DES3_TLS_SUITES
#define WC_NO_ASYNC_THREADING

/* --- Not carried ------------------------------------------------------- */
/*
 * Each of these is a capability nothing in this library uses. They are named
 * rather than left at their defaults so that turning one back on is a
 * deliberate act with a reason beside it.
 */
#define NO_DSA                        /* superseded everywhere */
#define NO_RC4                        /* broken */
#define NO_MD4                        /* broken */
#define NO_DES3                       /* withdrawn from TLS */
#define NO_PSK                        /* we authenticate by certificate */
#define NO_DSA
#define WOLFSSL_NO_SHAKE128
#define WOLFSSL_NO_SHAKE256
#define NO_OLD_RNGNAME
#define NO_OLD_WC_NAMES

/* Post-quantum. Not off because it is bad - it is the future - but because
 * wc_mlkem*.c is a large amount of code for something no broker we can talk to
 * offers yet, and this tree has a 50 MB upload budget to live inside. */
#define WOLFSSL_NO_ML_KEM

#endif /* board profile */

#ifdef __cplusplus
}
#endif
#endif /* MODBEE_WOLFSSL_USER_SETTINGS_H */
