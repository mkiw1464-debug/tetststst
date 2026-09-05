#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "bypass/Bypass.h"
#import "bypass/AntiDebug.h"
#import "features/Aimbot.h"
#import "features/ESP.h"
#import "ui/Menu.h"

// ─── Game tick ────────────────────────────────────────────────────────────────
@interface FFTicker : NSObject
@property (nonatomic, strong) CADisplayLink *link;
- (void)tick:(CADisplayLink*)dl;
@end

@implementation FFTicker
- (void)tick:(CADisplayLink*)dl {
    ESPCollect();
    AimbotTick();
    if (drawView) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [drawView setNeedsDisplay];
        });
    }
}
@end

static FFTicker *g_Ticker = nil;

// ─── Constructor — called when dylib loads ────────────────────────────────────
__attribute__((constructor))
static void Initialize() {
    // Short delay so Free Fire finishes its own startup
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC),
                   dispatch_get_main_queue(), ^{

        InitAntiDebug();
        InitAllBypasses();
        InitMenu();

        // Start game tick via CADisplayLink (runs at screen refresh rate)
        g_Ticker = [FFTicker new];
        CADisplayLink *dl = [CADisplayLink
            displayLinkWithTarget:g_Ticker selector:@selector(tick:)];
        [dl addToRunLoop:[NSRunLoop mainRunLoop]
                 forMode:NSRunLoopCommonModes];
        g_Ticker.link = dl;

        NSLog(@"[FFNET] V1.0.0 Beta — loaded 6767");
    });
}
