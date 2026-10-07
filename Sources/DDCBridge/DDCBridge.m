#import "DDCBridge.h"
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
#import <math.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <string.h>
#import <unistd.h>

typedef CFTypeRef MBAVService;
typedef MBAVService (*MBCreateService)(CFAllocatorRef, io_service_t);
typedef IOReturn (*MBCopyEDID)(MBAVService, CFDataRef *);
typedef IOReturn (*MBI2CRead)(MBAVService, uint32_t, uint32_t, void *, uint32_t);
typedef IOReturn (*MBI2CWrite)(MBAVService, uint32_t, uint32_t, void *, uint32_t);

static MBCreateService createService;
static MBCopyEDID copyEDID;
static MBI2CRead readI2C;
static MBI2CWrite writeI2C;
typedef int (*MBDisplayBrightnessGet)(uint32_t, float *);
typedef int (*MBDisplayBrightnessSet)(uint32_t, float);
typedef void (*MBDisplayBrightnessChanged)(uint32_t, double);
static MBDisplayBrightnessGet displayBrightnessGet;
static MBDisplayBrightnessSet displayBrightnessSet;
static MBDisplayBrightnessChanged displayBrightnessChanged;

static bool MBLoadDisplayServices(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *library = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW);
        if (!library) return;
        displayBrightnessGet = (MBDisplayBrightnessGet)dlsym(library, "DisplayServicesGetBrightness");
        displayBrightnessSet = (MBDisplayBrightnessSet)dlsym(library, "DisplayServicesSetBrightness");
        displayBrightnessChanged = (MBDisplayBrightnessChanged)dlsym(library, "DisplayServicesBrightnessChanged");
    });
    return displayBrightnessGet && displayBrightnessSet;
}

bool MBReadBuiltInBrightness(uint32_t displayID, float *value) {
    if (!value || !MBLoadDisplayServices()) return false;
    float level = -1;
    if (displayBrightnessGet(displayID, &level) != 0 || level < 0 || level > 1) return false;
    *value = level;
    return true;
}

bool MBWriteBuiltInBrightness(uint32_t displayID, float value) {
    if (!MBLoadDisplayServices() || value < 0 || value > 1 || displayBrightnessSet(displayID, value) != 0) return false;
    if (displayBrightnessChanged) displayBrightnessChanged(displayID, value);
    return true;
}

static id MBKeyboardClient(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)) return;
        Class cls = objc_getClass("KeyboardBrightnessClient");
        if (!cls) return;
        id allocated = ((id (*)(id, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
        client = ((id (*)(id, SEL))objc_msgSend)(allocated, sel_registerName("init"));
    });
    return client;
}

static bool MBKeyboardID(uint64_t *keyboardID) {
    id client = MBKeyboardClient();
    if (!client || !class_getInstanceMethod(object_getClass(client), sel_registerName("copyKeyboardBacklightIDs"))) return false;
    id ids = ((id (*)(id, SEL))objc_msgSend)(client, sel_registerName("copyKeyboardBacklightIDs"));
    if (!ids) return false;
    uint64_t count = ((uint64_t (*)(id, SEL))objc_msgSend)(ids, sel_registerName("count"));
    if (count) {
        id number = ((id (*)(id, SEL, uint64_t))objc_msgSend)(ids, sel_registerName("objectAtIndex:"), 0);
        *keyboardID = ((uint64_t (*)(id, SEL))objc_msgSend)(number, sel_registerName("unsignedLongLongValue"));
    }
    ((void (*)(id, SEL))objc_msgSend)(ids, sel_registerName("release"));
    return count > 0;
}

bool MBReadKeyboardBrightness(float *value) {
    uint64_t keyboardID;
    id client = MBKeyboardClient();
    if (!value || !MBKeyboardID(&keyboardID) ||
        !class_getInstanceMethod(object_getClass(client), sel_registerName("brightnessForKeyboard:"))) return false;
    float level = ((float (*)(id, SEL, uint64_t))objc_msgSend)(client, sel_registerName("brightnessForKeyboard:"), keyboardID);
    if (!isfinite(level) || level < 0 || level > 1) return false;
    *value = level;
    return true;
}

bool MBWriteKeyboardBrightness(float value) {
    uint64_t keyboardID;
    id client = MBKeyboardClient();
    if (!isfinite(value) || value < 0 || value > 1 || !MBKeyboardID(&keyboardID) ||
        !class_getInstanceMethod(object_getClass(client), sel_registerName("setBrightness:forKeyboard:"))) return false;
    ((void (*)(id, SEL, float, uint64_t))objc_msgSend)(client, sel_registerName("setBrightness:forKeyboard:"), value, keyboardID);
    return true;
}

bool MBReadKeyboardAutoBrightness(bool *enabled) {
    uint64_t keyboardID;
    id client = MBKeyboardClient();
    if (!enabled || !MBKeyboardID(&keyboardID) ||
        !class_getInstanceMethod(object_getClass(client), sel_registerName("isAutoBrightnessEnabledForKeyboard:"))) return false;
    *enabled = ((bool (*)(id, SEL, uint64_t))objc_msgSend)(client,
        sel_registerName("isAutoBrightnessEnabledForKeyboard:"), keyboardID);
    return true;
}

bool MBSetKeyboardAutoBrightness(bool enabled) {
    uint64_t keyboardID;
    id client = MBKeyboardClient();
    if (!MBKeyboardID(&keyboardID) ||
        !class_getInstanceMethod(object_getClass(client), sel_registerName("enableAutoBrightness:forKeyboard:"))) return false;
    ((void (*)(id, SEL, bool, uint64_t))objc_msgSend)(client,
        sel_registerName("enableAutoBrightness:forKeyboard:"), enabled, keyboardID);
    bool readback = !enabled;
    return MBReadKeyboardAutoBrightness(&readback) && readback == enabled;
}

static id MBNightShiftClient(void) {
    static id client;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        if (!dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_NOW)) return;
        Class cls = objc_getClass("CBBlueLightClient");
        if (!cls) return;
        id allocated = ((id (*)(id, SEL))objc_msgSend)(cls, sel_registerName("alloc"));
        client = ((id (*)(id, SEL))objc_msgSend)(allocated, sel_registerName("init"));
    });
    return client;
}

bool MBReadNightShift(bool *active, bool *enabled, int32_t *mode) {
    id client = MBNightShiftClient();
    SEL selector = sel_registerName("getBlueLightStatus:");
    if (!active || !enabled || !mode || !client ||
        !class_getInstanceMethod(object_getClass(client), selector)) return false;
    uint8_t status[64] = {0};
    if (!((BOOL (*)(id, SEL, void *))objc_msgSend)(client, selector, status)) return false;
    int32_t rawMode;
    memcpy(&rawMode, status + 4, sizeof(rawMode));
    if (status[0] > 1 || status[1] > 1 || rawMode < 0 || rawMode > 2) return false;
    *active = status[0] != 0;
    *enabled = status[1] != 0;
    *mode = rawMode;
    return true;
}

bool MBSetNightShiftWarm(bool warm, bool enabledWhenOff) {
    id client = MBNightShiftClient();
    SEL setActive = sel_registerName("setActive:");
    SEL setEnabled = sel_registerName("setEnabled:");
    bool active, enabled;
    int32_t mode;
    if (!client || !class_getInstanceMethod(object_getClass(client), setActive) ||
        !class_getInstanceMethod(object_getClass(client), setEnabled) ||
        !MBReadNightShift(&active, &enabled, &mode)) return false;
    if (warm && !enabled && !((BOOL (*)(id, SEL, BOOL))objc_msgSend)(client, setEnabled, YES)) return false;
    if (!((BOOL (*)(id, SEL, BOOL))objc_msgSend)(client, setActive, warm ? YES : NO)) return false;
    if (!warm && enabled != enabledWhenOff &&
        !((BOOL (*)(id, SEL, BOOL))objc_msgSend)(client, setEnabled, enabledWhenOff)) return false;
    return MBReadNightShift(&active, &enabled, &mode) &&
           (active && enabled) == warm && (warm || enabled == enabledWhenOff);
}

typedef struct {
    MBAVService service;
    uint32_t vendor;
    uint32_t product;
    uint32_t serial;
    bool hasEDID;
} MBEntry;

static MBEntry entries[8];
static int32_t entryCount = -1;

static bool MBLoad(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        const char *libraries[] = {
            "/System/Library/Frameworks/CoreDisplay.framework/CoreDisplay",
            "/System/Library/PrivateFrameworks/IOMobileFramebuffer.framework/IOMobileFramebuffer",
            "/System/Library/PrivateFrameworks/AVService.framework/AVService",
        };
        for (size_t i = 0; i < sizeof(libraries) / sizeof(libraries[0]); i++) {
            dlopen(libraries[i], RTLD_NOW | RTLD_GLOBAL);
            createService = (MBCreateService)dlsym(RTLD_DEFAULT, "IOAVServiceCreateWithService");
            copyEDID = (MBCopyEDID)dlsym(RTLD_DEFAULT, "IOAVServiceCopyEDID");
            readI2C = (MBI2CRead)dlsym(RTLD_DEFAULT, "IOAVServiceReadI2C");
            writeI2C = (MBI2CWrite)dlsym(RTLD_DEFAULT, "IOAVServiceWriteI2C");
            if (createService && readI2C && writeI2C) break;
        }
    });
    return createService && readI2C && writeI2C;
}

static uint8_t MBXOR(const uint8_t *bytes, size_t count, uint8_t seed) {
    for (size_t i = 0; i < count; i++) seed ^= bytes[i];
    return seed;
}

void MBMakeGetPacket(uint8_t code, uint8_t output[4]) {
    output[0] = 0x82;
    output[1] = 0x01;
    output[2] = code;
    output[3] = MBXOR(output, 3, 0x6e ^ 0x51);
}

void MBMakeSetPacket(uint8_t code, uint16_t value, uint8_t output[6]) {
    output[0] = 0x84;
    output[1] = 0x03;
    output[2] = code;
    output[3] = (uint8_t)(value >> 8);
    output[4] = (uint8_t)value;
    output[5] = MBXOR(output, 5, 0x6e ^ 0x51);
}

bool MBParseReply(const uint8_t *reply, size_t count, uint8_t code,
                  uint16_t *current, uint16_t *maximum) {
    if (!reply || count < 11 || reply[0] != 0x6e || reply[1] != 0x88 ||
        reply[2] != 0x02 || reply[3] != 0 || reply[4] != code ||
        MBXOR(reply, 10, 0x50) != reply[10]) return false;
    uint16_t maxValue = ((uint16_t)reply[6] << 8) | reply[7];
    uint16_t currentValue = ((uint16_t)reply[8] << 8) | reply[9];
    if (maxValue == 0 || currentValue > maxValue) return false;
    if (current) *current = currentValue;
    if (maximum) *maximum = maxValue;
    return true;
}

void MBRescan(void) {
    for (int32_t i = 0; i < entryCount; i++) {
        if (entries[i].service) CFRelease(entries[i].service);
        entries[i] = (MBEntry){0};
    }
    entryCount = 0;
    if (!MBLoad()) return;

    io_iterator_t iterator = IO_OBJECT_NULL;
    if (IOServiceGetMatchingServices(kIOMainPortDefault,
                                     IOServiceMatching("DCPAVServiceProxy"),
                                     &iterator) != KERN_SUCCESS) return;
    io_service_t node;
    while ((node = IOIteratorNext(iterator)) != IO_OBJECT_NULL) {
        CFTypeRef location = IORegistryEntryCreateCFProperty(node, CFSTR("Location"),
                                                              kCFAllocatorDefault, 0);
        bool external = location && CFGetTypeID(location) == CFStringGetTypeID() &&
                        CFEqual(location, CFSTR("External"));
        if (location) CFRelease(location);
        if (external && entryCount < 8) {
            MBAVService service = createService(kCFAllocatorDefault, node);
            if (service) {
                MBEntry *entry = &entries[entryCount++];
                entry->service = service;
                CFDataRef edid = NULL;
                if (copyEDID && copyEDID(service, &edid) == KERN_SUCCESS && edid) {
                    if (CFDataGetLength(edid) >= 16) {
                        const uint8_t *data = CFDataGetBytePtr(edid);
                        entry->vendor = ((uint32_t)data[8] << 8) | data[9];
                        entry->product = ((uint32_t)data[11] << 8) | data[10];
                        entry->serial = ((uint32_t)data[15] << 24) | ((uint32_t)data[14] << 16) |
                                        ((uint32_t)data[13] << 8) | data[12];
                        entry->hasEDID = true;
                    }
                    CFRelease(edid);
                }
            }
        }
        IOObjectRelease(node);
    }
    IOObjectRelease(iterator);
}

static bool MBValidIndex(int32_t index) {
    if (entryCount < 0) MBRescan();
    return index >= 0 && index < entryCount;
}

int32_t MBServiceCount(void) {
    if (entryCount < 0) MBRescan();
    return entryCount;
}

bool MBServiceIdentity(int32_t index, uint32_t *vendor, uint32_t *product, uint32_t *serial) {
    if (!MBValidIndex(index) || !entries[index].hasEDID) return false;
    if (vendor) *vendor = entries[index].vendor;
    if (product) *product = entries[index].product;
    if (serial) *serial = entries[index].serial;
    return true;
}

bool MBReadVCP(int32_t index, uint8_t code, uint16_t *current, uint16_t *maximum) {
    if (!MBValidIndex(index)) return false;
    uint8_t packet[4];
    MBMakeGetPacket(code, packet);
    for (int attempt = 0; attempt < 4; attempt++) {
        if (writeI2C(entries[index].service, 0x37, 0x51, packet, 4) != KERN_SUCCESS) {
            usleep(40000);
            continue;
        }
        usleep(50000);
        uint8_t response[11] = {0};
        if (readI2C(entries[index].service, 0x37, 0x51, response, 11) == KERN_SUCCESS &&
            MBParseReply(response, 11, code, current, maximum)) return true;
        usleep(40000);
    }
    return false;
}

bool MBWriteVCP(int32_t index, uint8_t code, uint16_t value) {
    if (!MBValidIndex(index)) return false;
    uint8_t packet[6];
    MBMakeSetPacket(code, value, packet);
    for (int attempt = 0; attempt < 3; attempt++) {
        if (writeI2C(entries[index].service, 0x37, 0x51, packet, 6) == KERN_SUCCESS) {
            usleep(50000);
            return true;
        }
        usleep(40000);
    }
    return false;
}
