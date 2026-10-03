#if defined(__x86_64__)
#import "DDCBridge.h"
#import <CoreGraphics/CoreGraphics.h>
#import <IOKit/IOKitLib.h>
#import <IOKit/i2c/IOI2CInterface.h>
#import <dlfcn.h>
#import <mach/mach_time.h>
#import <string.h>
#import <unistd.h>

typedef io_service_t (*MBDisplayPort)(CGDirectDisplayID);

typedef struct {
    CGDirectDisplayID displayID;
    uint32_t vendor;
    uint32_t product;
    uint32_t serial;
} MBIntelEntry;

static MBIntelEntry entries[32];
static int32_t entryCount = -1;

static MBDisplayPort MBPortFunction(void) {
    static MBDisplayPort function;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        void *framework = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY);
        if (framework) function = (MBDisplayPort)dlsym(framework, "CGDisplayIOServicePort");
    });
    return function;
}

void MBRescan(void) {
    entryCount = 0;
    MBDisplayPort portForDisplay = MBPortFunction();
    if (!portForDisplay) return;
    CGDirectDisplayID displayIDs[32];
    uint32_t count = 0;
    if (CGGetOnlineDisplayList(32, displayIDs, &count) != kCGErrorSuccess) return;
    for (uint32_t i = 0; i < count; i++) {
        CGDirectDisplayID displayID = displayIDs[i];
        if (CGDisplayIsBuiltin(displayID)) continue;
        io_service_t framebuffer = portForDisplay(displayID);
        IOItemCount buses = 0;
        if (!framebuffer || IOFBGetI2CInterfaceCount(framebuffer, &buses) != KERN_SUCCESS || !buses) continue;
        entries[entryCount++] = (MBIntelEntry){displayID, CGDisplayVendorNumber(displayID),
                                                CGDisplayModelNumber(displayID), CGDisplaySerialNumber(displayID)};
    }
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
    if (!MBValidIndex(index)) return false;
    if (vendor) *vendor = entries[index].vendor;
    if (product) *product = entries[index].product;
    if (serial) *serial = entries[index].serial;
    return true;
}

static uint64_t MBReplyDelay(void) {
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.numer) return 0;
    return 50000000ULL * timebase.denom / timebase.numer;
}

static bool MBTransact(CGDirectDisplayID displayID, const uint8_t *packet, uint32_t packetSize,
                       uint8_t code, uint16_t *current, uint16_t *maximum) {
    MBDisplayPort portForDisplay = MBPortFunction();
    io_service_t framebuffer = portForDisplay ? portForDisplay(displayID) : IO_OBJECT_NULL;
    IOItemCount buses = 0;
    if (!framebuffer || IOFBGetI2CInterfaceCount(framebuffer, &buses) != KERN_SUCCESS) return false;

    uint8_t frame[7] = {0x51};
    memcpy(frame + 1, packet, packetSize);
    for (IOOptionBits bus = 0; bus < buses; bus++) {
        io_service_t interface = IO_OBJECT_NULL;
        if (IOFBCopyI2CInterfaceForBus(framebuffer, bus, &interface) != KERN_SUCCESS) continue;
        IOI2CConnectRef connection = NULL;
        bool opened = IOI2CInterfaceOpen(interface, kNilOptions, &connection) == KERN_SUCCESS;
        IOObjectRelease(interface);
        if (!opened) continue;

        bool succeeded = false;
        for (int type = 0; type < (current ? 2 : 1) && !succeeded; type++) {
            uint8_t reply[11] = {0};
            IOI2CRequest request = {0};
            request.sendAddress = 0x6e;
            request.sendTransactionType = kIOI2CSimpleTransactionType;
            request.sendBuffer = (vm_address_t)frame;
            request.sendBytes = packetSize + 1;
            if (current) {
                request.replyAddress = 0x6f;
                request.replySubAddress = 0x51;
                request.replyTransactionType = type == 0 ? kIOI2CDDCciReplyTransactionType :
                                                           kIOI2CSimpleTransactionType;
                request.replyBuffer = (vm_address_t)reply;
                request.replyBytes = sizeof(reply);
                request.minReplyDelay = MBReplyDelay();
            }
            if (IOI2CSendRequest(connection, kNilOptions, &request) == KERN_SUCCESS &&
                request.result == KERN_SUCCESS) {
                succeeded = !current || MBParseReply(reply, request.replyBytes, code, current, maximum);
            }
        }
        IOI2CInterfaceClose(connection, kNilOptions);
        if (succeeded) return true;
    }
    return false;
}

bool MBReadVCP(int32_t index, uint8_t code, uint16_t *current, uint16_t *maximum) {
    if (!MBValidIndex(index) || !current || !maximum) return false;
    uint8_t packet[4];
    MBMakeGetPacket(code, packet);
    for (int attempt = 0; attempt < 4; attempt++) {
        if (MBTransact(entries[index].displayID, packet, sizeof(packet), code, current, maximum)) return true;
        usleep(40000);
    }
    return false;
}

bool MBWriteVCP(int32_t index, uint8_t code, uint16_t value) {
    if (!MBValidIndex(index)) return false;
    uint8_t packet[6];
    MBMakeSetPacket(code, value, packet);
    for (int attempt = 0; attempt < 3; attempt++) {
        if (MBTransact(entries[index].displayID, packet, sizeof(packet), code, NULL, NULL)) return true;
        usleep(40000);
    }
    return false;
}
#endif
