#pragma once
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

void MBMakeGetPacket(uint8_t code, uint8_t output[4]);
void MBMakeSetPacket(uint8_t code, uint16_t value, uint8_t output[6]);
bool MBParseReply(const uint8_t *reply, size_t count, uint8_t code, uint16_t *current, uint16_t *maximum);

void MBRescan(void);
int32_t MBServiceCount(void);
bool MBServiceIdentity(int32_t index, uint32_t *vendor, uint32_t *product, uint32_t *serial);
bool MBReadVCP(int32_t index, uint8_t code, uint16_t *current, uint16_t *maximum);
bool MBWriteVCP(int32_t index, uint8_t code, uint16_t value);

bool MBReadBuiltInBrightness(uint32_t displayID, float *value);
bool MBWriteBuiltInBrightness(uint32_t displayID, float value);
bool MBReadKeyboardBrightness(float *value);
bool MBWriteKeyboardBrightness(float value);
bool MBReadNightShift(bool *active, bool *enabled, int32_t *mode);
bool MBSetNightShiftWarm(bool warm, bool enabledWhenOff);
