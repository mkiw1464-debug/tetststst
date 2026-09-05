#import "Bypass.h"
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/runtime.h>
#import <dlfcn.h>
#import <mach/mach.h>
#import <mach-o/dyld.h>
#import <sys/sysctl.h>
#include "../../fishhook/fishhook.h"
#include "../utils/Memory.h"

// ─── BYPASS 1: Spoof Device Fingerprint (IDFV) ───────────────────────────────
// Garena bans by device IDFV. We return a stable fake UUID stored in
// NSUserDefaults (no SecKeychain — iOS-compatible).

static NSUUID *fakeidfv = nil;

static NSUUID *swizzled_identifierForVendor(id self, SEL _cmd) {
    if (!fakeidfv) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        NSString *stored = [ud objectForKey:@"ffnet_idfv_v2"];
        if (stored) {
            fakeidfv = [[NSUUID alloc] initWithUUIDString:stored];
        }
        if (!fakeidfv) {
            fakeidfv = [NSUUID UUID];
            [ud setObject:[fakeidfv UUIDString] forKey:@"ffnet_idfv_v2"];
            [ud synchronize];
        }
    }
    return fakeidfv;
}

static void SpoofIdfv() {
    Method orig = class_getInstanceMethod([UIDevice class],
                    @selector(identifierForVendor));
    if (orig)
        method_setImplementation(orig, (IMP)swizzled_identifierForVendor);
}

// ─── BYPASS 2: Hide dylib from dyld image list ───────────────────────────────
// Garena scans _dyld_get_image_name for unknown paths.

static const char *(*orig_dyld_get_image_name)(uint32_t) = nullptr;

static const char *fake_dyld_get_image_name(uint32_t idx) {
    const char *name = orig_dyld_get_image_name(idx);
    if (name && (strstr(name, "FFNET") || strstr(name, "ffnet")))
        return "";
    return name;
}

static void HideFromDyldImageList() {
    struct rebinding r[] = {
        {"_dyld_get_image_name",
         (void*)fake_dyld_get_image_name,
         (void**)&orig_dyld_get_image_name}
    };
    rebind_symbols(r, 1);
}

// ─── BYPASS 3: NOP CRC integrity check ───────────────────────────────────────
// Scan for the CRC comparison branch and patch it.
// Uses vm_protect to make memory writable first.

static void PatchCRCCheck() {
    const uint8_t pattern[] = {0x85, 0xC0, 0x0F, 0x84}; // test eax,eax + je
    uintptr_t base  = GetImageBase();
    uintptr_t limit = base + 0x8000000; // scan 128MB max
    uintptr_t found = 0;

    for (uintptr_t i = base; i < limit - sizeof(pattern); i++) {
        if (memcmp((void*)i, pattern, sizeof(pattern)) == 0) {
            found = i;
            break;
        }
    }
    if (!found) return;

    // Patch je → jmp (0x0F 0x84 → 0x0F 0x85)
    kern_return_t kr = vm_protect(mach_task_self(), found + 2, 2,
                                  FALSE,
                                  VM_PROT_READ | VM_PROT_WRITE | VM_PROT_EXECUTE);
    if (kr == KERN_SUCCESS) {
        uint8_t patch[] = {0x0F, 0x85};
        memcpy((void*)(found + 2), patch, 2);
    }
}

// ─── BYPASS 4: Block antiban / report API calls ───────────────────────────────

static NSURLSessionDataTask *(*orig_dataTask)(id, SEL, NSURLRequest*, id) = nullptr;

static NSURLSessionDataTask *fake_dataTask(id self, SEL cmd,
                                            NSURLRequest *req,
                                            id completion) {
    NSString *url = req.URL.absoluteString;
    if (!url) return orig_dataTask(self, cmd, req, completion);

    NSArray *blocked = @[
        @"garena.com/antiban",
        @"garena.com/report",
        @"garena.com/integrity",
        @"garena.com/cheatdetect",
        @"freefire.garena.com/report"
    ];
    for (NSString *b in blocked) {
        if ([url containsString:b]) {
            if (completion) {
                // Call completion with empty success data
                void(^cb)(NSData*, NSURLResponse*, NSError*) =
                    (void(^)(NSData*, NSURLResponse*, NSError*))completion;
                dispatch_async(dispatch_get_main_queue(), ^{
                    cb([NSData data], nil, nil);
                });
            }
            return nil;
        }
    }
    return orig_dataTask(self, cmd, req, completion);
}

static void HookAntibanAPI() {
    Class cls = NSClassFromString(@"NSURLSession");
    SEL sel = @selector(dataTaskWithRequest:completionHandler:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    orig_dataTask = (NSURLSessionDataTask*(*)(id,SEL,NSURLRequest*,id))
                     method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_dataTask);
}

// ─── BYPASS 5: Spoof bundle ID ────────────────────────────────────────────────

static NSString *(*orig_bundleID)(id, SEL) = nullptr;

static NSString *fake_bundleID(id self, SEL cmd) {
    return @"com.dts.freefireth";
}

static void SpoofBundleID() {
    Class cls = NSClassFromString(@"NSBundle");
    SEL sel = @selector(bundleIdentifier);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    orig_bundleID = (NSString*(*)(id,SEL))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_bundleID);
}

// ─── BYPASS 6: Block jailbreak / sideload path checks ────────────────────────

static BOOL (*orig_fileExists)(id, SEL, NSString*) = nullptr;

static BOOL fake_fileExists(id self, SEL cmd, NSString *path) {
    static NSArray *jbPaths = nil;
    if (!jbPaths) {
        jbPaths = @[
            @"/Applications/Cydia.app",
            @"/usr/sbin/sshd",
            @"/bin/bash",
            @"/private/var/lib/apt",
            @"/etc/apt",
            @"/.bootstrapped",
            @"/var/jb",
            @"/var/mobile/Library/Application Support/AppSync",
            @"/usr/lib/libhooker.dylib",
            @"/usr/lib/substitute-loader.dylib"
        ];
    }
    for (NSString *p in jbPaths)
        if ([path hasPrefix:p]) return NO;
    return orig_fileExists(self, cmd, path);
}

static void PatchFileExistsCheck() {
    Class cls = NSClassFromString(@"NSFileManager");
    SEL sel = @selector(fileExistsAtPath:);
    Method m = class_getInstanceMethod(cls, sel);
    if (!m) return;
    orig_fileExists = (BOOL(*)(id,SEL,NSString*))method_getImplementation(m);
    method_setImplementation(m, (IMP)fake_fileExists);
}

// ─── BYPASS 7: Login token cache ─────────────────────────────────────────────

static void BypassLoginToken() {
    NSUserDefaults *d = [NSUserDefaults standardUserDefaults];
    NSString *cached = [d objectForKey:@"ffnet_session_v2"];
    if (cached)
        [d setObject:cached forKey:@"garena_auth_token"];
}

// ─── BYPASS 8: Timing evasion (unique) ───────────────────────────────────────
// Delays telemetry hook by 600ms — outside Garena WAF 500ms window.
// 3 consecutive flags needed for ban. Timing break = chain never completes.

static void TimingEvasion() {
    dispatch_queue_t q = dispatch_get_global_queue(
        DISPATCH_QUEUE_PRIORITY_LOW, 0);
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 600 * NSEC_PER_MSEC), q, ^{
        HookAntibanAPI();
    });
}

// ─── PUBLIC API ──────────────────────────────────────────────────────────────

void InitAllBypasses() {
    SpoofIdfv();
    HideFromDyldImageList();
    PatchCRCCheck();
    TimingEvasion();
    SpoofBundleID();
    PatchFileExistsCheck();
    BypassLoginToken();
}

void BypassAntiBan()          { HookAntibanAPI(); }
void BypassAntiCheat()        { PatchCRCCheck(); }
void BypassLogin()            { BypassLoginToken(); }
void BypassLobby()            { BypassLoginToken(); }
void BypassReport()           { HookAntibanAPI(); }
void BypassBlacklist()        { SpoofIdfv(); SpoofBundleID(); }
void BypassThirdPartyInstall(){ SpoofBundleID(); PatchFileExistsCheck(); }
void PatchIntegrityCheck()    { PatchCRCCheck(); }
void SpoofDeviceFingerprint() { SpoofIdfv(); }
void HideLibraryFromTaskList(){ HideFromDyldImageList(); }
void PatchJailbreakDetection(){ PatchFileExistsCheck(); }
