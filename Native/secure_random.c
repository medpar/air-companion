#include <Security/SecRandom.h>
#include <stdint.h>
#include <stdlib.h>
#include "xp/common/gg_utils.h"
void GG_GetRandomBytes(uint8_t* buffer, size_t length) {
    if (SecRandomCopyBytes(kSecRandomDefault, length, buffer) != errSecSuccess) abort();
}
uint32_t GG_GetRandomInteger(void) {
    uint32_t value;
    GG_GetRandomBytes((uint8_t*)&value, sizeof value);
    return value;
}
