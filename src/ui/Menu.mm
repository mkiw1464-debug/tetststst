#import "Menu.h"
#import "../features/Aimbot.h"
#import "../features/ESP.h"
#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import <CoreGraphics/CoreGraphics.h>

// ─── Globals ──────────────────────────────────────────────────────────────────
static bool g_Streamproof = false;
static bool g_SaveConfig  = false;
static int  currentPage   = 0;

static UIWindow *menuWindow  = nil;
static UIView   *menuView    = nil;
static bool      menuVisible = false;
UIView          *drawView    = nil;  // extern — used in main.mm

// ─── Tap state ────────────────────────────────────────────────────────────────
static int              tapCount = 0;
static NSTimeInterval   lastTap  = 0;

// ─── Persistence helpers ─────────────────────────────────────────────────────
static void SaveConfig() {
    if (!g_SaveConfig) return;
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    [ud setBool:g_Aimbot.enabled    forKey:@"cfg_aimbot_on"];
    [ud setBool:g_Aimbot.silent     forKey:@"cfg_silent_on"];
    [ud setBool:g_Aimbot.showFov    forKey:@"cfg_fov_vis"];
    [ud setFloat:g_Aimbot.fov       forKey:@"cfg_fov_val"];
    [ud setInteger:g_Aimbot.targetBone forKey:@"cfg_bone"];
    [ud setBool:g_ESP.enabled       forKey:@"cfg_esp_on"];
    [ud setBool:g_ESP.showName      forKey:@"cfg_esp_name"];
    [ud setBool:g_ESP.showBox       forKey:@"cfg_esp_box"];
    [ud setBool:g_ESP.showLine      forKey:@"cfg_esp_line"];
    [ud setBool:g_ESP.showHP        forKey:@"cfg_esp_hp"];
    [ud setBool:g_Streamproof       forKey:@"cfg_streamproof"];
    [ud synchronize];
}

static void LoadConfig() {
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    if (![ud objectForKey:@"cfg_aimbot_on"]) return; // no saved config
    g_Aimbot.enabled    = [ud boolForKey:@"cfg_aimbot_on"];
    g_Aimbot.silent     = [ud boolForKey:@"cfg_silent_on"];
    g_Aimbot.showFov    = [ud boolForKey:@"cfg_fov_vis"];
    g_Aimbot.fov        = [ud floatForKey:@"cfg_fov_val"];
    g_Aimbot.targetBone = (int)[ud integerForKey:@"cfg_bone"];
    g_ESP.enabled       = [ud boolForKey:@"cfg_esp_on"];
    g_ESP.showName      = [ud boolForKey:@"cfg_esp_name"];
    g_ESP.showBox       = [ud boolForKey:@"cfg_esp_box"];
    g_ESP.showLine      = [ud boolForKey:@"cfg_esp_line"];
    g_ESP.showHP        = [ud boolForKey:@"cfg_esp_hp"];
    g_Streamproof       = [ud boolForKey:@"cfg_streamproof"];
}

// ─── ESP + FOV draw view ──────────────────────────────────────────────────────
@interface FFDrawView : UIView @end
@implementation FFDrawView
- (void)drawRect:(CGRect)r {
    CGContextRef ctx = UIGraphicsGetCurrentContext();
    if (!ctx) return;
    ESPRender(ctx);
    if (g_Aimbot.showFov) {
        float sz_w = (float)self.bounds.size.width;
        float sz_h = (float)self.bounds.size.height;
        float r2 = g_Aimbot.fov;
        CGContextSetRGBStrokeColor(ctx, 1.f, 1.f, 1.f, 0.55f);
        CGContextSetLineWidth(ctx, 1.2f);
        CGContextAddEllipseInRect(ctx,
            CGRectMake(sz_w * 0.5f - r2, sz_h * 0.5f - r2, r2 * 2.f, r2 * 2.f));
        CGContextStrokePath(ctx);
    }
}
@end

// ─── Toggle factory ───────────────────────────────────────────────────────────
@interface FFMenuHandler : NSObject
+ (instancetype)shared;
// Aimbot
- (void)toggleAimbot:(UISwitch*)s;
- (void)toggleSilent:(UISwitch*)s;
- (void)toggleFovVisual:(UISwitch*)s;
- (void)onBoneChange:(UISegmentedControl*)s;
- (void)onFovSlide:(UISlider*)s;
// ESP
- (void)toggleESP:(UISwitch*)s;
- (void)toggleESPName:(UISwitch*)s;
- (void)toggleESPBox:(UISwitch*)s;
- (void)toggleESPLine:(UISwitch*)s;
- (void)toggleESPHP:(UISwitch*)s;
// Settings
- (void)toggleStreamproof:(UISwitch*)s;
- (void)toggleSaveConfig:(UISwitch*)s;
// Tab / close
- (void)switchPage:(UISegmentedControl*)s;
- (void)closeMenu;
@end

@implementation FFMenuHandler
+ (instancetype)shared {
    static FFMenuHandler *h;
    static dispatch_once_t t;
    dispatch_once(&t, ^{ h = [FFMenuHandler new]; });
    return h;
}
- (void)toggleAimbot:(UISwitch*)s    { g_Aimbot.enabled    = s.on; SaveConfig(); }
- (void)toggleSilent:(UISwitch*)s    { g_Aimbot.silent     = s.on; SaveConfig(); }
- (void)toggleFovVisual:(UISwitch*)s { g_Aimbot.showFov    = s.on; SaveConfig(); }
- (void)onBoneChange:(UISegmentedControl*)s {
    int boneMap[] = {0, 1, 6, 19};
    g_Aimbot.targetBone = boneMap[s.selectedSegmentIndex]; SaveConfig();
}
- (void)onFovSlide:(UISlider*)s      { g_Aimbot.fov = s.value; }
- (void)toggleESP:(UISwitch*)s       { g_ESP.enabled  = s.on; SaveConfig(); }
- (void)toggleESPName:(UISwitch*)s   { g_ESP.showName = s.on; SaveConfig(); }
- (void)toggleESPBox:(UISwitch*)s    { g_ESP.showBox  = s.on; SaveConfig(); }
- (void)toggleESPLine:(UISwitch*)s   { g_ESP.showLine = s.on; SaveConfig(); }
- (void)toggleESPHP:(UISwitch*)s     { g_ESP.showHP   = s.on; SaveConfig(); }
- (void)toggleStreamproof:(UISwitch*)s { g_Streamproof = s.on; SaveConfig(); }
- (void)toggleSaveConfig:(UISwitch*)s  {
    g_SaveConfig = s.on;
    if (g_SaveConfig) SaveConfig();
}
- (void)switchPage:(UISegmentedControl*)s {
    currentPage = (int)s.selectedSegmentIndex;
    // Refresh content — handled by rebuilding page view
    extern void RefreshPage(int);
    RefreshPage(currentPage);
}
- (void)closeMenu { ToggleMenu(); }
@end

// ─── Page content scroll view tag ─────────────────────────────────────────────
#define kScrollTag 9900

static UIView *BuildAimbotPage(CGFloat mw, CGFloat contentH) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,contentH)];
    FFMenuHandler *h = [FFMenuHandler shared];
    float y = 12.f;
    UIColor *white = UIColor.whiteColor;

    auto addRow = [&](NSString *label, UIControl *ctrl) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y+4, mw-80, 22)];
        l.text = label; l.textColor = white;
        l.font = [UIFont systemFontOfSize:13.f]; [v addSubview:l];
        ctrl.frame = CGRectMake(mw-70, y, ctrl.frame.size.width, ctrl.frame.size.height);
        [v addSubview:ctrl]; y += 44.f;
    };

    UISwitch *swAimbot = [UISwitch new];
    swAimbot.on = g_Aimbot.enabled;
    swAimbot.onTintColor = [UIColor colorWithRed:.4f green:.4f blue:1.f alpha:1.f];
    [swAimbot addTarget:h action:@selector(toggleAimbot:) forControlEvents:UIControlEventValueChanged];
    addRow(@"Aimbot", swAimbot);

    // Bone selector
    UILabel *boneLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, y, 120, 22)];
    boneLabel.text = @"Target Bone"; boneLabel.textColor = white;
    boneLabel.font = [UIFont systemFontOfSize:13.f]; [v addSubview:boneLabel]; y += 26.f;
    UISegmentedControl *bone = [[UISegmentedControl alloc]
        initWithItems:@[@"Head", @"Neck", @"Body", @"Leg"]];
    bone.frame = CGRectMake(10, y, mw-20, 28);
    bone.selectedSegmentIndex = 0;
    bone.selectedSegmentTintColor = [UIColor colorWithRed:.5f green:.5f blue:1.f alpha:.9f];
    [bone addTarget:h action:@selector(onBoneChange:) forControlEvents:UIControlEventValueChanged];
    [v addSubview:bone]; y += 40.f;

    // FOV slider
    UILabel *fovLabel = [[UILabel alloc] initWithFrame:CGRectMake(14, y, 180, 22)];
    fovLabel.text = [NSString stringWithFormat:@"AimFov: %.0f", g_Aimbot.fov];
    fovLabel.textColor = white; fovLabel.font = [UIFont systemFontOfSize:13.f];
    [v addSubview:fovLabel]; y += 24.f;
    UISlider *fovSl = [[UISlider alloc] initWithFrame:CGRectMake(10, y, mw-20, 28)];
    fovSl.minimumValue = 0; fovSl.maximumValue = 200; fovSl.value = g_Aimbot.fov;
    fovSl.minimumTrackTintColor = [UIColor colorWithRed:.5f green:.5f blue:1.f alpha:1.f];
    [fovSl addTarget:h action:@selector(onFovSlide:) forControlEvents:UIControlEventValueChanged];
    [v addSubview:fovSl]; y += 40.f;

    UISwitch *swFov = [UISwitch new];
    swFov.on = g_Aimbot.showFov;
    swFov.onTintColor = [UIColor colorWithRed:.4f green:.4f blue:1.f alpha:1.f];
    [swFov addTarget:h action:@selector(toggleFovVisual:) forControlEvents:UIControlEventValueChanged];
    addRow(@"Show FOV Visual", swFov);

    UISwitch *swSilent = [UISwitch new];
    swSilent.on = g_Aimbot.silent;
    swSilent.onTintColor = [UIColor colorWithRed:.4f green:.4f blue:1.f alpha:1.f];
    [swSilent addTarget:h action:@selector(toggleSilent:) forControlEvents:UIControlEventValueChanged];
    addRow(@"Aim Silent", swSilent);

    return v;
}

static UIView *BuildESPPage(CGFloat mw, CGFloat contentH) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,contentH)];
    FFMenuHandler *h = [FFMenuHandler shared];
    UIColor *tc = [UIColor colorWithRed:.4f green:.4f blue:1.f alpha:1.f];

    struct Row { NSString *label; SEL action; BOOL state; };
    Row rows[] = {
        {@"ESP",       @selector(toggleESP:),     (BOOL)g_ESP.enabled},
        {@"Esp Name",  @selector(toggleESPName:),  (BOOL)g_ESP.showName},
        {@"Esp Box",   @selector(toggleESPBox:),   (BOOL)g_ESP.showBox},
        {@"Esp Line",  @selector(toggleESPLine:),  (BOOL)g_ESP.showLine},
        {@"Health Bar",@selector(toggleESPHP:),    (BOOL)g_ESP.showHP},
    };
    float y = 12.f;
    for (auto &r : rows) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y+6, mw-80, 22)];
        l.text = r.label; l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:13.f]; [v addSubview:l];
        UISwitch *sw = [UISwitch new]; sw.on = r.state; sw.onTintColor = tc;
        sw.frame = CGRectMake(mw-70, y, 51, 31);
        [sw addTarget:h action:r.action forControlEvents:UIControlEventValueChanged];
        [v addSubview:sw]; y += 44.f;
    }
    return v;
}

static UIView *BuildSettingsPage(CGFloat mw, CGFloat contentH) {
    UIView *v = [[UIView alloc] initWithFrame:CGRectMake(0,0,mw,contentH)];
    FFMenuHandler *h = [FFMenuHandler shared];
    UIColor *tc = [UIColor colorWithRed:.4f green:.4f blue:1.f alpha:1.f];
    float y = 12.f;

    auto addRow2 = [&](NSString *label, SEL action, BOOL state) {
        UILabel *l = [[UILabel alloc] initWithFrame:CGRectMake(14, y+6, mw-80, 22)];
        l.text = label; l.textColor = UIColor.whiteColor;
        l.font = [UIFont systemFontOfSize:13.f]; [v addSubview:l];
        UISwitch *sw = [UISwitch new]; sw.on = state; sw.onTintColor = tc;
        sw.frame = CGRectMake(mw-70, y, 51, 31);
        [sw addTarget:h action:action forControlEvents:UIControlEventValueChanged];
        [v addSubview:sw]; y += 44.f;
    };

    addRow2(@"Streamproof",  @selector(toggleStreamproof:), (BOOL)g_Streamproof);
    addRow2(@"Save Config",  @selector(toggleSaveConfig:),  (BOOL)g_SaveConfig);

    UILabel *ver = [[UILabel alloc] initWithFrame:CGRectMake(14, contentH-28, mw-28, 20)];
    ver.text = @"FFNET iOS V1.0.0 Beta";
    ver.textColor = [UIColor colorWithWhite:1.f alpha:0.4f];
    ver.font = [UIFont systemFontOfSize:10.f]; [v addSubview:ver];
    return v;
}

static UIScrollView *ContentScroll() {
    return (UIScrollView*)[menuView viewWithTag:kScrollTag];
}

void RefreshPage(int page) {
    UIScrollView *sc = ContentScroll();
    if (!sc) return;
    for (UIView *sub in sc.subviews) [sub removeFromSuperview];
    CGFloat mw = menuView.bounds.size.width;
    CGFloat contentH = sc.bounds.size.height;
    UIView *pg = nil;
    if (page == 0)      pg = BuildAimbotPage(mw, contentH);
    else if (page == 1) pg = BuildESPPage(mw, contentH);
    else                pg = BuildSettingsPage(mw, contentH);
    [sc addSubview:pg];
    sc.contentSize = pg.bounds.size;
}

// ─── Build menu ───────────────────────────────────────────────────────────────
void BuildMenu() {
    LoadConfig();
    CGSize screen = UIScreen.mainScreen.bounds.size;
    CGFloat mw = 300.f, mh = 390.f;
    CGFloat mx = (screen.width  - mw) * 0.5f;
    CGFloat my = (screen.height - mh) * 0.5f;

    menuWindow = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    menuWindow.windowLevel = UIWindowLevelStatusBar + 200.f;
    menuWindow.backgroundColor = UIColor.clearColor;
    menuWindow.hidden = YES;

    menuView = [[UIView alloc] initWithFrame:CGRectMake(mx, my, mw, mh)];
    menuView.layer.cornerRadius  = 18.f;
    menuView.clipsToBounds       = YES;
    menuView.layer.borderColor   = [UIColor colorWithWhite:1.f alpha:0.12f].CGColor;
    menuView.layer.borderWidth   = 1.f;

    // Glassmorphism blur background
    UIBlurEffect *blur = [UIBlurEffect
        effectWithStyle:UIBlurEffectStyleSystemUltraThinMaterialDark];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.frame = CGRectMake(0, 0, mw, mh);
    [menuView addSubview:blurView];

    // Grey tint overlay
    UIView *tint = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, mh)];
    tint.backgroundColor = [UIColor colorWithWhite:0.18f alpha:0.38f];
    [menuView addSubview:tint];

    // Title bar
    UIView *bar = [[UIView alloc] initWithFrame:CGRectMake(0, 0, mw, 44.f)];
    bar.backgroundColor = [UIColor colorWithWhite:0.12f alpha:0.6f];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(14, 11, mw-60, 22)];
    title.text = @"FFNET iOS  •  V1.0.0 Beta";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont boldSystemFontOfSize:13.f];
    [bar addSubview:title];

    UIButton *closeBtn = [UIButton buttonWithType:UIButtonTypeSystem];
    closeBtn.frame = CGRectMake(mw-38, 8, 30, 30);
    [closeBtn setTitle:@"✕" forState:UIControlStateNormal];
    [closeBtn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
    closeBtn.titleLabel.font = [UIFont systemFontOfSize:16.f];
    [closeBtn addTarget:[FFMenuHandler shared] action:@selector(closeMenu)
        forControlEvents:UIControlEventTouchUpInside];
    [bar addSubview:closeBtn];
    [menuView addSubview:bar];

    // Tab bar
    UISegmentedControl *tabs = [[UISegmentedControl alloc]
        initWithItems:@[@"Aimbot", @"ESP", @"Settings"]];
    tabs.frame = CGRectMake(10, 50, mw-20, 30);
    tabs.selectedSegmentIndex = 0;
    tabs.backgroundColor = [UIColor colorWithWhite:0.2f alpha:0.45f];
    tabs.selectedSegmentTintColor =
        [UIColor colorWithRed:.45f green:.45f blue:1.f alpha:.9f];
    [tabs addTarget:[FFMenuHandler shared] action:@selector(switchPage:)
        forControlEvents:UIControlEventValueChanged];
    [menuView addSubview:tabs];

    // Content scroll
    CGFloat scrollY = 88.f;
    UIScrollView *sc = [[UIScrollView alloc]
        initWithFrame:CGRectMake(0, scrollY, mw, mh - scrollY)];
    sc.tag = kScrollTag;
    sc.showsVerticalScrollIndicator = YES;
    [menuView addSubview:sc];

    // Load first page
    UIView *pg = BuildAimbotPage(mw, mh - scrollY);
    [sc addSubview:pg];
    sc.contentSize = pg.bounds.size;

    [menuWindow addSubview:menuView];
}

// ─── Streamproof — mark overlay as secure so capture APIs skip it ─────────────
static void ApplyStreamproof() {
    if (!g_Streamproof) return;
    // Embed a hidden secure text field — iOS renders its layer outside capture
    UITextField *sf = [[UITextField alloc] initWithFrame:CGRectZero];
    sf.secureTextEntry = YES;
    [menuView addSubview:sf];
    [sf becomeFirstResponder];
    [sf resignFirstResponder];
    [sf removeFromSuperview];
}

void ToggleMenu() {
    menuVisible = !menuVisible;
    menuWindow.hidden = !menuVisible;
    if (menuVisible) ApplyStreamproof();
}

void HandleTap() {
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - lastTap > 1.2) tapCount = 0;
    lastTap = now;
    if (++tapCount >= 3) {
        tapCount = 0;
        dispatch_async(dispatch_get_main_queue(), ^{ ToggleMenu(); });
    }
}

// ─── Init ─────────────────────────────────────────────────────────────────────
void InitMenu() {
    dispatch_async(dispatch_get_main_queue(), ^{
        BuildMenu();

        UIWindow *kw = nil;
        for (UIWindowScene *sc in UIApplication.sharedApplication.connectedScenes) {
            if ([sc isKindOfClass:[UIWindowScene class]])
                for (UIWindow *w in sc.windows)
                    if (w.isKeyWindow) { kw = w; break; }
        }
        if (!kw) kw = UIApplication.sharedApplication.windows.firstObject;

        // 3-tap gesture
        UITapGestureRecognizer *tap = [[UITapGestureRecognizer alloc]
            initWithTarget:[FFMenuHandler shared]
                    action:@selector(handleMenuTap)];
        // We intercept via our own HandleTap instead
        tap.numberOfTapsRequired = 3;
        [kw addGestureRecognizer:tap];

        // ESP draw view
        drawView = [[FFDrawView alloc] initWithFrame:UIScreen.mainScreen.bounds];
        drawView.backgroundColor = UIColor.clearColor;
        drawView.userInteractionEnabled = NO;
        [kw addSubview:drawView];

        // Bring menu window to front
        [menuWindow makeKeyAndVisible];
        menuWindow.hidden = YES;
    });
}

// ─── Tap handler extension ────────────────────────────────────────────────────
@implementation FFMenuHandler (TapHandle)
- (void)handleMenuTap {
    HandleTap();
}
@end
