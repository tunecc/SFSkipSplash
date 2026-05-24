#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import <objc/runtime.h>

static NSString * const SFSSLogPrefix = @"[SFSkipSplash]";

static BOOL SFSSIsSFExpressProcess(void) {
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    return [bundleID isEqualToString:@"com.sf-express.waybillcn"];
}

static void SFSSLog(NSString *format, ...) {
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    NSLog(@"%@ %@", SFSSLogPrefix, message);
}

static BOOL SFSSPerformNoArgSelector(id target, SEL selector) {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return NO;
    }

    void (*sendMessage)(id, SEL) = (void (*)(id, SEL))objc_msgSend;
    sendMessage(target, selector);
    return YES;
}

static BOOL SFSSSetBoolPropertyIfPossible(id target, SEL selector, BOOL value) {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return NO;
    }

    void (*sendMessage)(id, SEL, BOOL) = (void (*)(id, SEL, BOOL))objc_msgSend;
    sendMessage(target, selector, value);
    return YES;
}

static BOOL SFSSSetIntPropertyIfPossible(id target, SEL selector, int value) {
    if (!target || !selector || ![target respondsToSelector:selector]) {
        return NO;
    }

    void (*sendMessage)(id, SEL, int) = (void (*)(id, SEL, int))objc_msgSend;
    sendMessage(target, selector, value);
    return YES;
}

static void SFSSCloseSplashObject(id target, NSString *reason) {
    if (!target) {
        return;
    }

    SFSSLog(@"close requested: %@ target=%@", reason, NSStringFromClass([target class]));

    SEL stateSelectors[] = {
        @selector(setSkip:),
        @selector(setSplashClosed:),
        @selector(setIsTiggerAutoCloseSplash:)
    };

    for (NSUInteger i = 0; i < sizeof(stateSelectors) / sizeof(stateSelectors[0]); i++) {
        SFSSSetBoolPropertyIfPossible(target, stateSelectors[i], YES);
    }

    SFSSSetIntPropertyIfPossible(target, @selector(setCountDownNumber:), 0);
    SFSSPerformNoArgSelector(target, @selector(invalidCountDownTimer));

    SEL closeSelectors[] = {
        @selector(onSkipButotnClicked),
        @selector(countDownBtnAction),
        @selector(closeBtnAction),
        @selector(dismiss),
        @selector(doCloseSplashscreen),
        @selector(closeAppSplashAndAdForIsShowAdfail),
        @selector(closeAppSplashAndAdForIsShowAdSuc),
        @selector(onAppSplashClose),
        @selector(onAppSplashClose:)
    };

    for (NSUInteger i = 0; i < sizeof(closeSelectors) / sizeof(closeSelectors[0]); i++) {
        SEL selector = closeSelectors[i];
        if (selector == @selector(onAppSplashClose:)) {
            if ([target respondsToSelector:selector]) {
                void (*sendMessage)(id, SEL, id) = (void (*)(id, SEL, id))objc_msgSend;
                sendMessage(target, selector, nil);
                SFSSLog(@"called %@", NSStringFromSelector(selector));
                return;
            }
            continue;
        }

        if (SFSSPerformNoArgSelector(target, selector)) {
            SFSSLog(@"called %@", NSStringFromSelector(selector));
            return;
        }
    }
}

static void SFSSCloseKnownSplashInstances(NSString *reason) {
    NSArray<NSString *> *classNames = @[
        @"JPUSHInAppFullView",
        @"JPUSHInAppModalView",
        @"JPUSHInAppBannerView",
        @"DCADManager",
        @"DCH5ScreenAdvertising",
        @"DCSplashAdViewController",
        @"DCADLaunch",
        @"DCH5ScreenAdvertisingBrowser"
    ];

    for (NSString *className in classNames) {
        Class cls = NSClassFromString(className);
        if (!cls) {
            continue;
        }

        SEL sharedSelectors[] = {
            @selector(sharedInstance),
            @selector(sharedManager),
            @selector(defaultManager),
            @selector(getLaunchAD)
        };

        for (NSUInteger i = 0; i < sizeof(sharedSelectors) / sizeof(sharedSelectors[0]); i++) {
            SEL selector = sharedSelectors[i];
            if (![cls respondsToSelector:selector]) {
                continue;
            }

            id (*sendMessage)(Class, SEL) = (id (*)(Class, SEL))objc_msgSend;
            id instance = sendMessage(cls, selector);
            if (instance) {
                SFSSCloseSplashObject(instance, reason);
            }
        }
    }
}

%hook DCH5ScreenAdvertising

- (void)loadSplashView {
    SFSSLog(@"DCH5ScreenAdvertising loadSplashView skipped");
    SFSSCloseSplashObject(self, @"loadSplashView");
}

- (BOOL)canCloseSplash {
    SFSSLog(@"DCH5ScreenAdvertising canCloseSplash -> YES");
    return YES;
}

- (void)doCloseSplashscreen {
    SFSSLog(@"DCH5ScreenAdvertising doCloseSplashscreen");
    %orig;
}

- (void)closeAppSplashAndAdForIsShowAdfail {
    SFSSLog(@"DCH5ScreenAdvertising close fail path");
    %orig;
}

- (void)closeAppSplashAndAdForIsShowAdSuc {
    SFSSLog(@"DCH5ScreenAdvertising close success path");
    %orig;
}

- (void)interruptCloseSplash {
    SFSSLog(@"DCH5ScreenAdvertising interruptCloseSplash forced close");
    SFSSCloseSplashObject(self, @"interruptCloseSplash");
}

- (void)interruptCloseSplashForADNotShowOver {
    SFSSLog(@"DCH5ScreenAdvertising interruptCloseSplashForADNotShowOver forced close");
    SFSSCloseSplashObject(self, @"interruptCloseSplashForADNotShowOver");
}

%end

%hook DCSplashAdViewController

- (void)viewDidAppear:(BOOL)animated {
    %orig;
    SFSSLog(@"DCSplashAdViewController viewDidAppear forced skip");
    SFSSCloseSplashObject(self, @"viewDidAppear");
}

- (void)countDownBtnAction {
    SFSSLog(@"DCSplashAdViewController countDownBtnAction");
    %orig;
}

- (void)onSkipButotnClicked {
    SFSSLog(@"DCSplashAdViewController onSkipButotnClicked");
    %orig;
}

- (void)startCountdown {
    SFSSLog(@"DCSplashAdViewController startCountdown skipped");
    SFSSCloseSplashObject(self, @"startCountdown");
}

- (void)startCountdown:(long long)arg1 {
    SFSSLog(@"DCSplashAdViewController startCountdown: skipped");
    SFSSCloseSplashObject(self, @"startCountdown:");
}

%end

%hook DCADManager

- (void)requestAd {
    SFSSLog(@"DCADManager requestAd skipped");
    SFSSCloseSplashObject(self, @"DCADManager requestAd");
}

- (BOOL)selectAdAndShow:(BOOL)arg1 {
    SFSSLog(@"DCADManager selectAdAndShow: -> NO");
    SFSSCloseSplashObject(self, @"DCADManager selectAdAndShow:");
    return NO;
}

- (void)selectAdAndShowForForeground:(id)arg1 {
    SFSSLog(@"DCADManager selectAdAndShowForForeground: skipped");
    SFSSCloseSplashObject(self, @"DCADManager selectAdAndShowForForeground:");
}

- (BOOL)selectAdAndShowForSerial:(id)arg1 {
    SFSSLog(@"DCADManager selectAdAndShowForSerial: -> NO");
    SFSSCloseSplashObject(self, @"DCADManager selectAdAndShowForSerial:");
    return NO;
}

- (void)createAdViewController:(id)arg1 {
    SFSSLog(@"DCADManager createAdViewController: skipped");
    SFSSCloseSplashObject(self, @"DCADManager createAdViewController:");
}

- (id)getADViewController {
    SFSSLog(@"DCADManager getADViewController -> nil");
    return nil;
}

- (void)displayDCloudAd:(id)arg1 {
    SFSSLog(@"DCADManager displayDCloudAd: skipped");
    SFSSCloseSplashObject(self, @"DCADManager displayDCloudAd:");
}

- (void)displayThirdAD:(id)arg1 {
    SFSSLog(@"DCADManager displayThirdAD: skipped");
    SFSSCloseSplashObject(self, @"DCADManager displayThirdAD:");
}

- (void)notifyDelegateShowViewController:(id)arg1 {
    SFSSLog(@"DCADManager notifyDelegateShowViewController: skipped");
    SFSSCloseSplashObject(self, @"DCADManager notifyDelegateShowViewController:");
}

- (void)notifyDelegateCloseViewController:(id)arg1 {
    SFSSLog(@"DCADManager notifyDelegateCloseViewController:");
    %orig;
}

- (BOOL)advScreenWillClose:(int)arg1 {
    SFSSLog(@"DCADManager advScreenWillClose: -> YES");
    SFSSCloseSplashObject(self, @"DCADManager advScreenWillClose:");
    return YES;
}

- (void)advScreenCanShow:(id)arg1 {
    SFSSLog(@"DCADManager advScreenCanShow: skipped");
    SFSSCloseSplashObject(self, @"DCADManager advScreenCanShow:");
}

- (BOOL)interruptCloseSplash {
    SFSSLog(@"DCADManager interruptCloseSplash -> YES");
    SFSSCloseSplashObject(self, @"DCADManager interruptCloseSplash");
    return YES;
}

- (BOOL)interruptCloseSplashForADNotShowOver {
    SFSSLog(@"DCADManager interruptCloseSplashForADNotShowOver -> YES");
    SFSSCloseSplashObject(self, @"DCADManager interruptCloseSplashForADNotShowOver");
    return YES;
}

- (void)closeAppSplashAndAdForIsShowAdfail {
    SFSSLog(@"DCADManager close fail path");
    %orig;
}

- (void)closeAppSplashAndAdForIsShowAdSuc {
    SFSSLog(@"DCADManager close success path");
    %orig;
}

- (void)comCloseAppSplashAndAd {
    SFSSLog(@"DCADManager comCloseAppSplashAndAd");
    %orig;
}

- (void)close5PlusSplash {
    SFSSLog(@"DCADManager close5PlusSplash");
    %orig;
}

- (void)handleSplashMiniTimeout {
    SFSSLog(@"DCADManager handleSplashMiniTimeout forced close");
    SFSSCloseSplashObject(self, @"DCADManager handleSplashMiniTimeout");
}

- (void)splashAdDidLoad:(id)arg1 {
    SFSSLog(@"DCADManager splashAdDidLoad: forced close");
    SFSSCloseSplashObject(self, @"DCADManager splashAdDidLoad:");
}

- (void)splashAdWillVisible:(id)arg1 {
    SFSSLog(@"DCADManager splashAdWillVisible: forced close");
    SFSSCloseSplashObject(self, @"DCADManager splashAdWillVisible:");
}

- (void)splashAdDidClose:(id)arg1 {
    SFSSLog(@"DCADManager splashAdDidClose:");
    %orig;
}

- (void)splashAd:(id)arg1 didFailWithError:(id)arg2 {
    SFSSLog(@"DCADManager splashAd:didFailWithError:");
    %orig;
}

%end

%hook DCADLaunch

- (void)initLaunchAd {
    SFSSLog(@"DCADLaunch initLaunchAd skipped");
    SFSSCloseSplashObject(self, @"initLaunchAd");
}

- (void)requestAd {
    SFSSLog(@"DCADLaunch requestAd skipped");
    SFSSCloseSplashObject(self, @"requestAd");
}

- (BOOL)selectAdAndShow:(BOOL)arg1 {
    SFSSLog(@"DCADLaunch selectAdAndShow: skipped");
    SFSSCloseSplashObject(self, @"selectAdAndShow:");
    return NO;
}

- (void)selectAdAndShowForForeground:(id)arg1 {
    SFSSLog(@"DCADLaunch selectAdAndShowForForeground: skipped");
    SFSSCloseSplashObject(self, @"selectAdAndShowForForeground:");
}

- (BOOL)selectAdAndShowForSerial:(id)arg1 {
    SFSSLog(@"DCADLaunch selectAdAndShowForSerial: skipped");
    SFSSCloseSplashObject(self, @"selectAdAndShowForSerial:");
    return NO;
}

- (void)splashAdDidLoad:(id)arg1 {
    SFSSLog(@"DCADLaunch splashAdDidLoad: forced close");
    SFSSCloseSplashObject(self, @"splashAdDidLoad:");
}

- (void)splashAdWillVisible:(id)arg1 {
    SFSSLog(@"DCADLaunch splashAdWillVisible: forced close");
    SFSSCloseSplashObject(self, @"splashAdWillVisible:");
}

- (void)splashAdDidClose:(id)arg1 {
    SFSSLog(@"DCADLaunch splashAdDidClose:");
    %orig;
}

- (void)splashAd:(id)arg1 didFailWithError:(id)arg2 {
    SFSSLog(@"DCADLaunch splashAd:didFailWithError:");
    %orig;
}

- (BOOL)isAdEnable {
    SFSSLog(@"DCADLaunch isAdEnable -> NO");
    return NO;
}

- (BOOL)isAdRequestSuccess {
    SFSSLog(@"DCADLaunch isAdRequestSuccess -> NO");
    return NO;
}

%end

%hook JPUSHInAppFullView

- (id)initWithConfig:(id)arg1 delegate:(id)arg2 {
    id result = %orig;
    SFSSLog(@"JPUSHInAppFullView initWithConfig:delegate: auto dismiss");
    SFSSCloseSplashObject(result, @"JPUSH initWithConfig:delegate:");
    return result;
}

- (void)showInView:(id)arg1 {
    SFSSLog(@"JPUSHInAppFullView showInView: skipped");
    SFSSCloseSplashObject(self, @"JPUSH showInView:");
}

- (BOOL)initFullMessageViewLayout:(id)arg1 {
    SFSSLog(@"JPUSHInAppFullView initFullMessageViewLayout: -> NO");
    SFSSCloseSplashObject(self, @"JPUSH initFullMessageViewLayout:");
    return NO;
}

- (void)configUI {
    SFSSLog(@"JPUSHInAppFullView configUI skipped");
    SFSSCloseSplashObject(self, @"JPUSH configUI");
}

- (void)countDown {
    SFSSLog(@"JPUSHInAppFullView countDown forced dismiss");
    SFSSCloseSplashObject(self, @"JPUSH countDown");
}

- (void)countDownBtnAction {
    SFSSLog(@"JPUSHInAppFullView countDownBtnAction");
    %orig;
}

- (void)closeBtnAction {
    SFSSLog(@"JPUSHInAppFullView closeBtnAction");
    %orig;
}

- (void)dismiss {
    SFSSLog(@"JPUSHInAppFullView dismiss");
    %orig;
}

%end

%hook JPUSHInAppModalView

- (void)showInView:(id)arg1 {
    SFSSLog(@"JPUSHInAppModalView showInView: skipped");
    SFSSCloseSplashObject(self, @"JPUSH modal showInView:");
}

- (void)configUI {
    SFSSLog(@"JPUSHInAppModalView configUI skipped");
    SFSSCloseSplashObject(self, @"JPUSH modal configUI");
}

- (void)closeBtnAction {
    SFSSLog(@"JPUSHInAppModalView closeBtnAction");
    %orig;
}

- (void)dismiss {
    SFSSLog(@"JPUSHInAppModalView dismiss");
    %orig;
}

%end

%hook JPUSHInAppBannerView

- (void)showInView:(id)arg1 {
    SFSSLog(@"JPUSHInAppBannerView showInView: skipped");
    SFSSCloseSplashObject(self, @"JPUSH banner showInView:");
}

- (void)configUI {
    SFSSLog(@"JPUSHInAppBannerView configUI skipped");
    SFSSCloseSplashObject(self, @"JPUSH banner configUI");
}

- (void)dismiss {
    SFSSLog(@"JPUSHInAppBannerView dismiss");
    %orig;
}

%end

%hook DCUniSkipButton

- (void)showSkipButton {
    SFSSLog(@"DCUniSkipButton showSkipButton -> auto close known splash");
    %orig;
    SFSSCloseKnownSplashInstances(@"showSkipButton");
}

- (void)showSikpButton {
    SFSSLog(@"DCUniSkipButton showSikpButton -> auto close known splash");
    %orig;
    SFSSCloseKnownSplashInstances(@"showSikpButton");
}

%end

%ctor {
    @autoreleasepool {
        if (!SFSSIsSFExpressProcess()) {
            return;
        }

        SFSSLog(@"loaded in %@", [[NSBundle mainBundle] bundleIdentifier]);
    }
}
