(* Which radio, which bands, which operator. Optional: without it the module
searches everything it supports and the network chooses.

MODEM         which modem. Must be wired.
MODE          which technology to search for.
                GSM_RADIO_AUTO        leave the module's own setting alone
                GSM_RADIO_GSM_ONLY    2G
                GSM_RADIO_LTE_ONLY    4G
                GSM_RADIO_GSM_AND_LTE either
                GSM_RADIO_CAT_M       LTE-M (a low-power module only)
                GSM_RADIO_NB_IOT      NB-IoT (a low-power module only)
                GSM_RADIO_CAT_M_AND_NB_IOT  both
OPERATOR      the one network to use, as its numeric code (MCC and MNC, five
              or six digits, e.g. '53001'). Empty lets the module choose.
CAT_M_BANDS   LTE-M bands to search, as a list: '3, 28'. Empty searches all.
NB_IOT_BANDS  NB-IoT bands to search, the same way.

APPLIED       the settings reached the modem block.
ERROR         a value was not understood; nothing was changed.
STATUS        why. GSM_OK when fine.

---

  radio( MODEM := modem, MODE := GSM_RADIO_CAT_M, CAT_M_BANDS := '3, 28' );

LEAVE IT ALONE UNLESS YOU KNOW THE SITE. A controller on a pole has to take
what it can get: pinning it to one technology or one network means a site
where that one is missing never connects, and nothing about that failure
explains itself.

THE BANDS ARE THE SETTING THAT SAVES TIME on a low-power (LTE-M / NB-IoT)
module. A fresh one searches every band it supports - dozens of slow scans -
and naming the one or two a country uses turns minutes into seconds. They do
nothing on an ordinary 4G (Cat-1) module such as the A7670.

The settings are read during the modem's bring-up. A change while the modem
is up starts the bring-up again, which drops the data connection for the
seconds that takes. *)

FUNCTION_BLOCK GSM_RADIO
  VAR_INPUT
    MODE : GSM_RADIO_MODE;
    OPERATOR : STRING(7);
    CAT_M_BANDS : STRING(64);
    NB_IOT_BANDS : STRING(64);
  END_VAR
  VAR_OUTPUT
    APPLIED : BOOL;
    ERROR : BOOL;
    STATUS : GSM_RESULT;
  END_VAR
  VAR_IN_OUT
    MODEM : GSM_MODEM;
  END_VAR

#include <ModBeeGsmPlc.h>

void setup()
{
    APPLIED = false;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
}

void loop()
{
    // Checked here, so a mistake is this block's ERROR and the modem keeps
    // the settings it had rather than half of the new ones.
    bool valid = true;

    const char* code = OPERATOR.c_str();
    const size_t codeLength = OPERATOR.length();
    if (codeLength != 0) {
        if (codeLength < 5 || codeLength > 6) valid = false;
        for (size_t i = 0; i < codeLength; i++) {
            if (code[i] < '0' || code[i] > '9') valid = false;
        }
    }

    uint8_t bands[32];
    uint8_t count = 0;
    if (!gsmplc::parseBands(CAT_M_BANDS.c_str(), bands, sizeof bands, &count)) valid = false;
    if (!gsmplc::parseBands(NB_IOT_BANDS.c_str(), bands, sizeof bands, &count)) valid = false;

    const int mode = (int)(GSM_RADIO_MODE)MODE;
    if (mode < 0 || mode > (int)GSM_RADIO_MODE::GSM_RADIO_CAT_M_AND_NB_IOT) valid = false;

    if (!valid) {
        APPLIED = false;
        ERROR = true;
        STATUS = GSM_RESULT::GSM_INVALID_ARGUMENT;
        return;
    }

    MODEM.FBRADIOMODE = MODE;
    MODEM.FBOPERATOR = OPERATOR;
    MODEM.FBCATMBANDS = CAT_M_BANDS;
    MODEM.FBNBIOTBANDS = NB_IOT_BANDS;

    APPLIED = true;
    ERROR = false;
    STATUS = GSM_RESULT::GSM_OK;
}


END_FUNCTION_BLOCK