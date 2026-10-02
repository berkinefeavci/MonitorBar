#import "DDCBridge.h"
#import <CoreFoundation/CoreFoundation.h>
#import <IOKit/IOKitLib.h>
#import <dlfcn.h>
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
