// Hardware capability probe for LuxCurve.
// Verifies, on real hardware, that we can (a) read ambient lux from the
// built-in sensor via the private IOHIDEventSystem API, and (b) read/write
// the internal display brightness via the private DisplayServices API.
//
// This is a throwaway diagnostic, NOT part of the app. Kept in-repo so the
// private-API surface can be re-verified after macOS updates.
//
// Build & run:
//   clang -fobjc-arc -framework Foundation -framework CoreGraphics \
//     -framework IOKit -F /System/Library/PrivateFrameworks \
//     -framework DisplayServices probe.m -o probe && ./probe

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

// --- Private IOKit / IOHIDEventSystem (ambient light sensor) ---
typedef struct __IOHIDEvent *IOHIDEventRef;
typedef struct __IOHIDServiceClient *IOHIDServiceClientRef;
typedef struct __IOHIDEventSystemClient *IOHIDEventSystemClientRef;

extern IOHIDEventSystemClientRef IOHIDEventSystemClientCreate(CFAllocatorRef allocator);
extern int IOHIDEventSystemClientSetMatching(IOHIDEventSystemClientRef client, CFDictionaryRef match);
extern CFArrayRef IOHIDEventSystemClientCopyServices(IOHIDEventSystemClientRef client);
extern IOHIDEventRef IOHIDServiceClientCopyEvent(IOHIDServiceClientRef service, int64_t type, int32_t options, int64_t timestamp);
extern double IOHIDEventGetFloatValue(IOHIDEventRef event, int32_t field);
extern int64_t IOHIDEventGetIntegerValue(IOHIDEventRef event, int32_t field);

// --- Private DisplayServices (internal display brightness) ---
extern int DisplayServicesGetLinearBrightness(CGDirectDisplayID display, float *brightness);
extern int DisplayServicesSetLinearBrightness(CGDirectDisplayID display, float brightness);
extern int DisplayServicesCanChangeBrightness(CGDirectDisplayID display);

#define kIOHIDEventTypeAmbientLightSensor 12
#define IOHIDEventFieldBase(type) ((type) << 16)

int main(int argc, char **argv) {
    @autoreleasepool {
        printf("=== LuxCurve hardware probe ===\n");

        // --- Ambient Light Sensor ---
        printf("\n[1] Ambient Light Sensor (IOHIDEventSystem)\n");
        IOHIDEventSystemClientRef client = IOHIDEventSystemClientCreate(kCFAllocatorDefault);
        if (!client) {
            printf("  FAIL: could not create IOHIDEventSystemClient\n");
        } else {
            NSDictionary *match = @{ @"PrimaryUsagePage": @(0xff00), @"PrimaryUsage": @(4) };
            int rc = IOHIDEventSystemClientSetMatching(client, (__bridge CFDictionaryRef)match);
            CFArrayRef services = IOHIDEventSystemClientCopyServices(client);
            long n = services ? CFArrayGetCount(services) : 0;
            printf("  setMatching rc=%d, matching services=%ld\n", rc, n);
            BOOL gotLux = NO;
            for (long i = 0; i < n; i++) {
                IOHIDServiceClientRef svc = (IOHIDServiceClientRef)CFArrayGetValueAtIndex(services, i);
                IOHIDEventRef ev = IOHIDServiceClientCopyEvent(svc, kIOHIDEventTypeAmbientLightSensor, 0, 0);
                if (ev) {
                    int32_t field = (int32_t)IOHIDEventFieldBase(kIOHIDEventTypeAmbientLightSensor);
                    double fLux = IOHIDEventGetFloatValue(ev, field);
                    int64_t iLux = IOHIDEventGetIntegerValue(ev, field);
                    printf("  service[%ld]: lux(float)=%.4f  lux(int)=%lld\n", i, fLux, iLux);
                    gotLux = YES;
                    CFRelease(ev);
                }
            }
            if (!gotLux) printf("  WARN: matched %ld service(s) but read no ALS event\n", n);
            if (services) CFRelease(services);
            CFRelease(client);
        }

        // --- Display brightness ---
        printf("\n[2] Internal display brightness (DisplayServices)\n");
        CGDirectDisplayID disp = CGMainDisplayID();
        printf("  CGMainDisplayID = %u\n", disp);
        int can = DisplayServicesCanChangeBrightness(disp);
        printf("  canChangeBrightness = %d\n", can);
        float b = -1.0f;
        int grc = DisplayServicesGetLinearBrightness(disp, &b);
        printf("  getLinearBrightness rc=%d value=%.4f\n", grc, b);
        if (grc == 0 && b >= 0.0f) {
            // Safe: set to the SAME value -> no visible change, just confirms the write path.
            int src = DisplayServicesSetLinearBrightness(disp, b);
            printf("  setLinearBrightness(current=%.4f) rc=%d  (no-op write to confirm path)\n", b, src);
        } else {
            printf("  SKIP set test (getter failed)\n");
        }

        printf("\n=== probe complete ===\n");
    }
    return 0;
}
