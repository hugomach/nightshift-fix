// Re-applies Night Shift after display reconfiguration / screen wake (macOS bug workaround)
#import <Foundation/Foundation.h>
#import <AppKit/AppKit.h>
#import <CoreGraphics/CoreGraphics.h>

typedef struct { int hour; int minute; } NSFTime;
typedef struct { NSFTime from; NSFTime to; } NSFSchedule;
typedef struct {
    BOOL active; BOOL enabled; BOOL sunSchedulePermitted; int mode;
    NSFSchedule schedule; unsigned long long disableFlags; BOOL available;
    char pad[64];
} NSFStatus;

@interface CBBlueLightClient : NSObject
- (BOOL)setEnabled:(BOOL)e;
- (BOOL)getBlueLightStatus:(NSFStatus *)s;
@end

static CBBlueLightClient *client;
static BOOL wasEnabled = NO;
static NSUInteger generation = 0;
static BOOL pending = NO;

static BOOL isEnabled(void) {
    NSFStatus s; memset(&s, 0, sizeof s);
    if (![client getBlueLightStatus:&s]) return NO;
    return s.enabled;
}

static void snapshot(void) { if (isEnabled()) wasEnabled = YES; }

static void scheduleReapply(void) {
    NSUInteger g = ++generation; pending = YES;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        if (g != generation) return;               // debounce bursts of events
        if (wasEnabled || isEnabled()) {
            NSLog(@"nsfix: re-applying Night Shift");
            [client setEnabled:NO];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
                [client setEnabled:YES];
            });
        }
        wasEnabled = NO; pending = NO;
    });
}

static void displayCB(CGDirectDisplayID d, CGDisplayChangeSummaryFlags f, void *u) {
    if (f & kCGDisplayBeginConfigurationFlag) snapshot();
    else scheduleReapply();
}

int main(void) {
    @autoreleasepool {
        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"] load];
        client = [[NSClassFromString(@"CBBlueLightClient") alloc] init];
        if (!client) { NSLog(@"nsfix: CBBlueLightClient unavailable"); return 1; }

        CGDisplayRegisterReconfigurationCallback(displayCB, NULL);
        NSNotificationCenter *wc = [[NSWorkspace sharedWorkspace] notificationCenter];
        for (NSString *n in @[NSWorkspaceScreensDidSleepNotification, NSWorkspaceWillSleepNotification])
            [wc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *x){ snapshot(); }];
        for (NSString *n in @[NSWorkspaceScreensDidWakeNotification, NSWorkspaceDidWakeNotification, NSWorkspaceSessionDidBecomeActiveNotification])
            [wc addObserverForName:n object:nil queue:nil usingBlock:^(NSNotification *x){ scheduleReapply(); }];

        // periodic snapshot so we know the state right before an abrupt change
        [NSTimer scheduledTimerWithTimeInterval:30 repeats:YES block:^(NSTimer *t){ if (!pending) wasEnabled = isEnabled(); }];
        NSLog(@"nsfix: running");
        [[NSRunLoop mainRunLoop] run];
    }
    return 0;
}
