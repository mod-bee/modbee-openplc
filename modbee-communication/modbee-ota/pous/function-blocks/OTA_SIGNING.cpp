(* Only installs firmware signed with your key. Optional: a project without it carries none of its code.

NODE      the OTA_NODE to protect. Set REQUIRE_SIGNED on it too.
KEY       the public key: the P-256 point as 128 hex characters, as printed
          by `modbee_ota.py pubkey` without the commas and 0x.

ACTIVE    the key is in use.
ERROR     it is not; STATUS says why.
STATUS    OTA_INVALID_ARGUMENT for a key that is not 128 hex characters.

---

WHAT IT PROTECTS AGAINST. Without it the node checks that an update arrived
whole and is for this board - not who made it. Anyone able to publish to the
node's OTA topic could install their own firmware. With it, only firmware
signed by the holder of the private key installs; the key never leaves the PC
that signs the releases.

The check takes about 160 ms on a Node UIO and runs in the background, never
in a scan. It uses the wolfSSL the MQTT library already brings for TLS. *)

FUNCTION_BLOCK OTA_SIGNING
  VAR_INPUT
    KEY : STRING(130);
  END_VAR
  VAR_OUTPUT
    ACTIVE : BOOL;
    ERROR : BOOL;
    STATUS : OTA_RESULT;
  END_VAR
  VAR_IN_OUT
    NODE : OTA_NODE;
  END_VAR
  VAR
    fbContext : __XWORD;
  END_VAR
#include <ModBeeOta.h>
#include <verifiers/OtaEcdsaP256Verifier.h>
#include <new>
#include <string.h>

// Everything this block needs from OTA_NODE (OtaNodeContext) is declared in
// OTA_NODE's code, which sorts before this file in the one translation unit
// every C++ POU lands in.

#if defined(OTA_NODE_ON_BOARD) && defined(MODBEE_OTA_HAS_WOLFSSL) && \
    defined(MODBEE_OTA_HAS_ASYNC_VERIFIER)
#define OTA_SIGNING_ON_BOARD 1

// The check itself takes ~160 ms on the Node UIO, so it runs on the node's
// OTA worker, never in a scan. Made once, never freed.
struct OtaSigningContext {
  OtaEcdsaP256Verifier ecdsa;
  OtaAsyncVerifier async;
  explicit OtaSigningContext(const uint8_t key[64]) : ecdsa(key), async(ecdsa) {}
};
#endif

void setup()
{
    ACTIVE = false;
    ERROR = false;
    STATUS = OTA_RESULT::OTA_OK;
}

void loop()
{
#if !defined(OTA_SIGNING_ON_BOARD)
    ACTIVE = false;
    ERROR = true;
    STATUS = OTA_RESULT::OTA_UNSUPPORTED;
#else
    if ((strucpp::XWORD_t)fbContext != 0) return;  // attached; nothing more to do

    // Attaching reaches into OTA_NODE's updater, so it happens in its task.
    if (!mq_inTask((strucpp::XWORD_t)NODE.FBTASK)) {
        ACTIVE = false;
        ERROR = true;
        STATUS = OTA_RESULT::OTA_NOT_READY;
        return;
    }
    OtaNodeContext* node = (OtaNodeContext*)(uintptr_t)(strucpp::XWORD_t)NODE.FBCONTEXT;
    if (!node || !node->begun) {
        // The node block has not started yet - this block may run first in
        // a scan. REQUIRE_SIGNED on the node keeps offers out meanwhile.
        ACTIVE = false;
        ERROR = false;
        STATUS = OTA_RESULT::OTA_NOT_READY;
        return;
    }

    // The public key: the P-256 point, X then Y, as 128 hex characters -
    // what `modbee_ota.py pubkey` prints, without the commas and 0x.
    const char* hex = KEY.c_str();
    uint8_t key[64];
    if (strlen(hex) != 128 || ota_fromHex(hex, 128, key, sizeof(key)) != 64) {
        ACTIVE = false;
        ERROR = true;
        STATUS = OTA_RESULT::OTA_INVALID_ARGUMENT;
        return;
    }

    OtaSigningContext* c = new (std::nothrow) OtaSigningContext(key);
    if (!c || !node->worker.add(c->async)) {
        ACTIVE = false;
        ERROR = true;
        STATUS = OTA_RESULT::OTA_NO_MEMORY;
        return;
    }
    node->ota.verifier(&c->async);
    fbContext = (strucpp::XWORD_t)(uintptr_t)c;
    ACTIVE = true;
    ERROR = false;
    STATUS = OTA_RESULT::OTA_OK;
#endif
}


END_FUNCTION_BLOCK