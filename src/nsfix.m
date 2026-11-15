// Re-applies Night Shift after display reconfiguration / screen wake (macOS bug workaround)
// v2: runs as NSApplication (reliable workspace notifications), polls display
// configuration every 10 s as a fallback, decides by *current* Night Shift state
// and re-applies in several waves (displays can take a while to settle).
// v3: re-evaluates the sunset schedule instead of forcing Night Shift on,
// so it never turns orange in daylight after sleeping through sunrise.
// v4: only reacts when the set of displays / their sleep state actually changes
// (Dock moves, resolution changes etc. no longer trigger a flicker) and uses
// two waves instead of three.
// v5: sleep/wake alone no longer triggers anything (that flickered on every
// lid open). Only a change in *which* displays are connected marks the state
// dirty; the re-apply then runs as soon as a display is awake (immediately,
// or at the next wake if the change happened while the screens were off).
// v6: a single off/on toggle (5 s after the last event) instead of two waves,
// and it also runs when an *external* monitor wakes up. Waking only the
// built-in display (e.g. opening the lid with nothing attached) does nothing.
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
- (BOOL)setMode:(int)m;
- (BOOL)getBlueLightStatus:(NSFStatus *)s;
@end

static CBBlueLightClient *client;
static BOOL recentlyEnabled = NO;     // Night Shift was on shortly before the event
static NSUInteger generation = 0;
static NSString *lastDisplaySet = nil;   // online display IDs, ignoring sleep state
static BOOL lastExternalAwake = NO;     // was an external display awake at the last check
static BOOL dirty = NO;                  // display set changed, re-apply still owed

static BOOL isEnabled(void) {
    NSFStatus s; memset(&s, 0, sizeof s);
    if (![client getBlueLightStatus:&s]) return NO;
    return s.enabled;
}

// Online display IDs: changes only on plug/unplug, not on sleep/wake
static NSString *displaySet(BOOL *anyAwake, BOOL *externalAwake) {
    CGDirectDisplayID ids[16]; uint32_t n = 0;
    CGGetOnlineDisplayList(16, ids, &n);
    NSMutableString *f = [NSMutableString string];
    BOOL awake = NO, extAwake = NO;
    for (uint32_t i = 0; i < n; i++) {
        [f appendFormat:@"%u,", ids[i]];
        if (!CGDisplayIsAsleep(ids[i])) {
            awake = YES;
            if (!CGDisplayIsBuiltin(ids[i])) extAwake = YES;
        }
    }
    if (anyAwake) *anyAwake = awake;
    if (externalAwake) *externalAwake = extAwake;
    return f;
}

static void reapplyOnce(NSString *why) {
    if (!(isEnabled() || recentlyEnabled)) return;   // user had it off -> leave it alone
    NSFStatus s; memset(&s, 0, sizeof s);
    [client getBlueLightStatus:&s];
    int mode = s.mode;

    if (mode != 0) {
        // Re-setting the schedule mode makes CoreBrightness re-evaluate the
        // sunset/sunrise (or custom) schedule itself. After a sleep across sunrise
        // the status can still say "on"; forcing setEnabled:YES would then turn
        // Night Shift on in daylight. Let the schedule decide instead.
        [client setMode:0];
        [client setMode:mode];
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
        if (!isEnabled()) {
            NSLog(@"nsfix: schedule says off (%@)", why);
            return;
        }
        // Schedule says on: toggle so the filter is actually applied to the panel
        NSLog(@"nsfix: re-applying Night Shift (%@)", why);
        [client setEnabled:NO];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 400 * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{
            [client setEnabled:YES];
        });
    });
}

static void scheduleReapply(NSString *why) {
    if (isEnabled()) recentlyEnabled = YES;
    NSUInteger g = ++generation;
    // one toggle, 5 s after the last event of a burst (displays need a moment to settle)
    for (NSNumber *sec in @[@5]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, sec.doubleValue * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (g != generation) return;            // a newer burst superseded us
            reapplyOnce([NSString stringWithFormat:@"%@ +%@s", why, sec]);
            recentlyEnabled = NO;
        });
    }
}

// Re-apply after a monitor was plugged/unplugged or an external monitor woke up,
// once a display is awake
static void reapplyIfDisplaysChanged(NSString *why) {
    BOOL awake = NO, extAwake = NO;
    NSString *set = displaySet(&awake, &extAwake);
    if (![set isEqualToString:lastDisplaySet]) {
        lastDisplaySet = set;
        dirty = YES;
        if (isEnabled()) recentlyEnabled = YES;
    }
    if (extAwake && !lastExternalAwake) dirty = YES;   // external monitor came back on
    lastExternalAwake = extAwake;
    if (dirty && awake) {
        dirty = NO;
        scheduleReapply([NSString stringWithFormat:@"%@: displays now %@", why, set]);
    }
}

static void displayCB(CGDirectDisplayID d, CGDisplayChangeSummaryFlags f, void *u) {
    if (f & kCGDisplayBeginConfigurationFlag) { if (isEnabled()) recentlyEnabled = YES; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ reapplyIfDisplaysChanged(@"display reconfig"); });
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyProhibited];

        [[NSBundle bundleWithPath:@"/System/Library/PrivateFrameworks/CoreBrightness.framework"] load];
        client = [[NSClassFromString(@"CBBlueLightClient") alloc] init];
        if (!client) { NSLog(@"nsfix: CBBlueLightClient unavailable"); return 1; }

        CGDisplayRegisterReconfigurationCallback(displayCB, NULL);

        NSNotificationCenter *wc = [[NSWorkspace sharedWorkspace] notificationCenter];
        for (NSString *n in @[NSWorkspaceScreensDidWakeNotification, NSWorkspaceDidWakeNotification,
                              NSWorkspaceSessionDidBecomeActiveNotification])
            [wc addObserverForName:n object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *x){
                // a pending change (e.g. unplugged while asleep) is applied once the screen is on
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 1 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
                    reapplyIfDisplaysChanged(x.name);
                });
            }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidChangeScreenParametersNotification
            object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *x){ reapplyIfDisplaysChanged(@"screen params"); }];

        // Fallback poll: catches changes whose notifications never arrive (e.g. unplug while screen is off)
        lastDisplaySet = displaySet(NULL, &lastExternalAwake);
        NSTimer *t = [NSTimer timerWithTimeInterval:10 repeats:YES block:^(NSTimer *tm){
            reapplyIfDisplaysChanged(@"poll");
        }];
        t.tolerance = 1;
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];

        NSLog(@"nsfix v6: running (displays %@)", lastDisplaySet);
        [NSApp run];
    }
    return 0;
}
