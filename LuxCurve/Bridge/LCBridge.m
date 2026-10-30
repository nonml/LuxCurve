//
//  LCBridge.m
//  LuxCurve
//
//  Implementation of the private-API bridge. The function prototypes below are
//  the undocumented Apple symbols we rely on; they are declared here (not in any
//  public SDK header) and resolved at link time:
//    - IOHIDEventSystem*  -> IOKit.framework            (ambient light sensor)
//    - DisplayServices*   -> DisplayServices.framework  (internal display brightness)
//
//  See LuxCurve.xcodeproj build settings: FRAMEWORK_SEARCH_PATHS includes
//  /System/Library/PrivateFrameworks and OTHER_LDFLAGS links DisplayServices.
//

#import "LCBridge.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>

#pragma mark - Private IOKit / IOHIDEventSystem (ambient light sensor)

typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);

#pragma mark - Private DisplayServices (internal display brightness)

extern int DisplayServicesGetLinearBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetLinearBrightness(CGDirectDisplayID display, float brightness);
extern int DisplayServicesCanChangeBrightness(CGDirectDisplayID display);

// Apple Silicon ambient light sensor: usage page 0xff00, usage 4.
// The lux value lives in event type 12 (kIOHIDEventTypeAmbientLightSensor),
// field == (type << 16).
#define kLCEventTypeALS 12
#define kLCALSField ((int32_t)(kLCEventTypeALS << 16))

#pragma mark - Public bridge functions

// The event-system client and the sensor's service are looked up once and kept,
// rather than re-created on every poll. They are only touched from the main
// thread (DaemonManager's tick). If the cached service stops returning events
// (for example after sleep), it is released and looked up again.
static IOHIDEventSystemClientRef sALSClient = NULL;
static IOHIDServiceClientRef sALSService = NULL;

static void LCReleaseALSService(void) {
    if (sALSService) { CFRelease(sALSService); sALSService = NULL; }
    if (sALSClient) { CFRelease(sALSClient); sALSClient = NULL; }
}

/// Find the first matching service that returns an ALS event and cache it.
static void LCFindALSService(void) {
    sALSClient = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
    if (!sALSClient) { return; }

    NSDictionary *match = @{ @"PrimaryUsagePage": @(0xff00), @"PrimaryUsage": @(4) };
    IOHIDEventSystemClientSetMatching(sALSClient, (__bridge CFDictionaryRef)match);
    CFArrayRef services = IOHIDEventSystemClientCopyServices(sALSClient);
    if (services) {
        long count = CFArrayGetCount(services);
        for (long i = 0; i < count; i++) {
            IOHIDServiceClientRef service = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
            IOHIDEventRef event = IOHIDServiceClientCopyEvent(service, kLCEventTypeALS, 0, 0);
            if (event) {
                CFRelease(event);
                sALSService = (IOHIDServiceClientRef)CFRetain(service);
                break;
            }
        }
        CFRelease(services);
    }
    if (!sALSService) { LCReleaseALSService(); }
}

double LCReadAmbientLux(bool *ok) {
    if (ok) { *ok = false; }

    // Second attempt runs only if the cached service returned no event.
    for (int attempt = 0; attempt < 2; attempt++) {
        if (!sALSService) { LCFindALSService(); }
        if (!sALSService) { return 0.0; }

        IOHIDEventRef event = IOHIDServiceClientCopyEvent(sALSService, kLCEventTypeALS, 0, 0);
        if (event) {
            double lux = IOHIDEventGetFloatValue(event, kLCALSField);
            CFRelease(event);
            if (ok) { *ok = true; }
            return lux < 0.0 ? 0.0 : lux;
        }
        LCReleaseALSService();
    }
    return 0.0;
}

bool LCCanChangeBrightness(void) {
    return DisplayServicesCanChangeBrightness(CGMainDisplayID()) != 0;
}

bool LCGetLinearBrightness(float *outValue) {
    float value = 0.0f;
    int rc = DisplayServicesGetLinearBrightness(CGMainDisplayID(), &value);
    if (rc == 0 && outValue) { *outValue = value; }
    return rc == 0;
}

bool LCSetLinearBrightness(float value) {
    if (value < 0.0f) { value = 0.0f; }
    if (value > 1.0f) { value = 1.0f; }
    int rc = DisplayServicesSetLinearBrightness(CGMainDisplayID(), value);
    return rc == 0;
}

#pragma mark - Private CoreBrightness (Night Shift / color temperature)

// CBBlueLightClient is the Night Shift engine in the private CoreBrightness
// framework. We load the framework at runtime and look the class up by name, so
// the app degrades gracefully (warmth simply reported unavailable) if a future
// macOS removes or renames it. Every message send is guarded by
// respondsToSelector for the same reason.
@interface CBBlueLightClient : NSObject
- (BOOL)setStrength:(float)strength commit:(BOOL)commit;
- (BOOL)setEnabled:(BOOL)enabled;
@end

static id LCBlueLightClient(void) {
    static id client = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        dlopen("/System/Library/PrivateFrameworks/CoreBrightness.framework/CoreBrightness", RTLD_LAZY);
        Class cls = NSClassFromString(@"CBBlueLightClient");
        if (cls) { client = [[cls alloc] init]; }
    });
    return client;
}

bool LCCanControlWarmth(void) {
    id c = LCBlueLightClient();
    return c != nil
        && [c respondsToSelector:@selector(setStrength:commit:)]
        && [c respondsToSelector:@selector(setEnabled:)];
}

bool LCSetWarmth(float strength) {
    if (!LCCanControlWarmth()) { return false; }
    CBBlueLightClient *c = (CBBlueLightClient *)LCBlueLightClient();
    if (strength < 0.0f) { strength = 0.0f; }
    if (strength > 1.0f) { strength = 1.0f; }
    if (strength <= 0.0001f) {
        return [c setEnabled:NO];
    }
    BOOL okStrength = [c setStrength:strength commit:YES];
    BOOL okEnabled = [c setEnabled:YES];
    return okStrength && okEnabled;
}

bool LCDisableWarmth(void) {
    if (!LCCanControlWarmth()) { return false; }
    CBBlueLightClient *c = (CBBlueLightClient *)LCBlueLightClient();
    return [c setEnabled:NO];
}
