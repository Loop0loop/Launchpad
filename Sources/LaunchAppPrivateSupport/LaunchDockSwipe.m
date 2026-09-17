#import "LaunchDockSwipe.h"

#import <AppKit/AppKit.h>
#import <ApplicationServices/ApplicationServices.h>
#import <dlfcn.h>
#import <mach/mach_time.h>

@interface LaunchHIDEvent : NSObject
- (nullable instancetype)initWithType:(uint32_t)type
                            timestamp:(uint64_t)timestamp
                             senderID:(uint64_t)senderID;
- (void)setIntegerValue:(NSInteger)value forField:(uint32_t)field;
- (void)setDoubleValue:(double)value forField:(uint32_t)field;
- (void)appendEvent:(LaunchHIDEvent *)event;
@property uint32_t options;
@end

typedef void (*SLEventSetIOHIDEventFn)(CGEventRef event, CFTypeRef hidEvent);

enum {
    LaunchHIDEventTypeVelocity = 9,
    LaunchHIDEventTypeDockSwipe = 23,
    LaunchHIDGestureFlavorDockPrimary = 3,
    LaunchHIDEventPhaseEnded = 1 << 2,
    LaunchHIDEventPhaseCancelled = 1 << 3,
    LaunchHIDEventPhaseShift = 24,
};

#define LaunchHIDFieldBase(type) ((uint32_t)(type) << 16)
static const uint32_t LaunchHIDFieldVelocityX = LaunchHIDFieldBase(LaunchHIDEventTypeVelocity) | 0;
static const uint32_t LaunchHIDFieldVelocityY = LaunchHIDFieldBase(LaunchHIDEventTypeVelocity) | 1;
static const uint32_t LaunchHIDFieldVelocityZ = LaunchHIDFieldBase(LaunchHIDEventTypeVelocity) | 2;
static const uint32_t LaunchHIDFieldDockSwipeMotion = LaunchHIDFieldBase(LaunchHIDEventTypeDockSwipe) | 1;
static const uint32_t LaunchHIDFieldDockSwipeProgress = LaunchHIDFieldBase(LaunchHIDEventTypeDockSwipe) | 2;
static const uint32_t LaunchHIDFieldDockSwipeFlavor = LaunchHIDFieldBase(LaunchHIDEventTypeDockSwipe) | 5;

static SLEventSetIOHIDEventFn setHIDEvent;
static Class hidEventClass;

bool LaunchDockSwipePrepare(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = dlopen(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight",
            RTLD_NOW | RTLD_LOCAL
        );
        if (!handle) return;
        setHIDEvent = (SLEventSetIOHIDEventFn)dlsym(handle, "SLEventSetIOHIDEvent");
        hidEventClass = NSClassFromString(@"HIDEvent");
    });
    return setHIDEvent != NULL && hidEventClass != Nil;
}

bool LaunchDockSwipePost(double progress, double velocity, uint32_t phase) {
    if (!LaunchDockSwipePrepare()) return false;

    @autoreleasepool {
        uint64_t timestamp = mach_absolute_time();
        LaunchHIDEvent *hidEvent = [[hidEventClass alloc]
            initWithType:LaunchHIDEventTypeDockSwipe
                timestamp:timestamp
                 senderID:0];
        if (!hidEvent) return false;

        hidEvent.options = phase << LaunchHIDEventPhaseShift;
        [hidEvent setIntegerValue:3 forField:LaunchHIDFieldDockSwipeMotion];
        [hidEvent setIntegerValue:LaunchHIDGestureFlavorDockPrimary
                         forField:LaunchHIDFieldDockSwipeFlavor];
        [hidEvent setDoubleValue:progress forField:LaunchHIDFieldDockSwipeProgress];

        if (phase == LaunchHIDEventPhaseEnded || phase == LaunchHIDEventPhaseCancelled) {
            LaunchHIDEvent *velocityEvent = [[hidEventClass alloc]
                initWithType:LaunchHIDEventTypeVelocity
                    timestamp:timestamp
                     senderID:0];
            if (velocityEvent) {
                [velocityEvent setDoubleValue:velocity forField:LaunchHIDFieldVelocityX];
                [velocityEvent setDoubleValue:velocity forField:LaunchHIDFieldVelocityY];
                [velocityEvent setDoubleValue:0 forField:LaunchHIDFieldVelocityZ];
                [hidEvent appendEvent:velocityEvent];
            }
        }

        CGEventRef event = CGEventCreate(NULL);
        if (!event) return false;
        CGEventSetType(event, (CGEventType)30);
        setHIDEvent(event, (__bridge CFTypeRef)hidEvent);
        CGEventPost(kCGSessionEventTap, event);
        CFRelease(event);
        return true;
    }
}
