// Re-applies Night Shift after display reconfiguration / screen wake (macOS bug workaround)
// v2: runs as NSApplication (reliable workspace notifications), polls display
// configuration every 10 s as a fallback, decides by *current* Night Shift state
// and re-applies in several waves (displays can take a while to settle).
// v3: re-evaluates the sunset schedule instead of forcing Night Shift on,
// so it never turns orange in daylight after sleeping through sunrise.
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
static NSString *lastFingerprint = nil;

static BOOL isEnabled(void) {
    NSFStatus s; memset(&s, 0, sizeof s);
    if (![client getBlueLightStatus:&s]) return NO;
    return s.enabled;
}

// Online displays + whether the main one is asleep: changes on plug/unplug/sleep/wake
static NSString *displayFingerprint(void) {
    CGDirectDisplayID ids[16]; uint32_t n = 0;
    CGGetOnlineDisplayList(16, ids, &n);
    NSMutableString *f = [NSMutableString string];
    for (uint32_t i = 0; i < n; i++)
        [f appendFormat:@"%u%s,", ids[i], CGDisplayIsAsleep(ids[i]) ? "z" : ""];
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
    // waves: 2 s, 8 s, 20 s after the last event of a burst
    for (NSNumber *sec in @[@2, @8, @20]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, sec.doubleValue * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            if (g != generation) return;            // a newer burst superseded us
            reapplyOnce([NSString stringWithFormat:@"%@ +%@s", why, sec]);
            if (sec.intValue == 20) recentlyEnabled = NO;
        });
    }
}

static void displayCB(CGDirectDisplayID d, CGDisplayChangeSummaryFlags f, void *u) {
    if (f & kCGDisplayBeginConfigurationFlag) { if (isEnabled()) recentlyEnabled = YES; return; }
    dispatch_async(dispatch_get_main_queue(), ^{ scheduleReapply(@"display reconfig"); });
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
                scheduleReapply(x.name);
            }];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSApplicationDidChangeScreenParametersNotification
            object:nil queue:[NSOperationQueue mainQueue] usingBlock:^(NSNotification *x){ scheduleReapply(@"screen params"); }];

        // Fallback poll: catches changes whose notifications never arrive (e.g. unplug while screen is off)
        lastFingerprint = displayFingerprint();
        NSTimer *t = [NSTimer timerWithTimeInterval:10 repeats:YES block:^(NSTimer *tm){
            NSString *fp = displayFingerprint();
            if (![fp isEqualToString:lastFingerprint]) {
                lastFingerprint = fp;
                scheduleReapply([NSString stringWithFormat:@"poll: displays now %@", fp]);
            }
        }];
        t.tolerance = 1;
        [[NSRunLoop mainRunLoop] addTimer:t forMode:NSRunLoopCommonModes];

        NSLog(@"nsfix v3: running (displays %@)", lastFingerprint);
        [NSApp run];
    }
    return 0;
}
