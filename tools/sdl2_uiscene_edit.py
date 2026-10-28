#!/usr/bin/env python3
"""Adds UIScene life cycle support to SDL2's UIKit backend (iOS 13+).

Apps built with recent iOS SDKs refuse to launch unless they adopt UIScene.
SDL3 supports it; SDL2 never did, so this backports the essentials:
the app delegate also acts as the window scene delegate, SDL_main starts when
the first application scene connects, and windows (including message box
windows) are created inside that scene. The interface orientation is read from
the scene instead of the deprecated status bar API.

Usage: sdl2_uiscene_edit.py <path to SDL2 source>   (idempotent)
"""
import os
import sys

root = sys.argv[1]
MARK = "UIScene life cycle"


def edit(rel, pairs):
    path = os.path.join(root, rel)
    with open(path) as f:
        s = f.read()
    for old, new in pairs:
        if s.count(old) != 1:
            raise SystemExit(f"{rel}: expected exactly one match for:\n{old}")
        s = s.replace(old, new)
    with open(path, "w") as f:
        f.write(s)


uikit = "src/video/uikit/"
with open(os.path.join(root, uikit + "SDL_uikitappdelegate.m")) as f:
    if MARK in f.read():
        print("SDL2 already has the UIScene changes")
        sys.exit(0)

# --- SDL_uikitvideo.h: scene and orientation helpers --------------------------
edit(uikit + "SDL_uikitvideo.h", [(
"""CGRect UIKit_ComputeViewFrame(SDL_Window *window, UIScreen *screen);

#endif /* __OBJC__ */""",
"""CGRect UIKit_ComputeViewFrame(SDL_Window *window, UIScreen *screen);

/* UIScene life cycle support: the window scene showing the given screen
 * (nil for any), preferring the foreground active application scene. */
UIWindowScene *UIKit_GetWindowSceneForScreen(UIScreen *screen) API_AVAILABLE(ios(13.0), tvos(13.0));

#if !TARGET_OS_TV
/* The current interface orientation, from the window scene when possible. */
UIInterfaceOrientation UIKit_GetInterfaceOrientation(void);
#endif

#endif /* __OBJC__ */""")])

# --- SDL_uikitvideo.m: implement the helpers, use them ------------------------
edit(uikit + "SDL_uikitvideo.m", [
("""    orient = [UIApplication sharedApplication].statusBarOrientation;""",
 """    orient = UIKit_GetInterfaceOrientation();"""),
("""void UIKit_ForceUpdateHomeIndicator(void)""",
 """UIWindowScene *UIKit_GetWindowSceneForScreen(UIScreen *screen)
{
    UIWindowScene *inactive = nil;
    UIWindowScene *fallback = nil;
    BOOL wantApplicationRole = (screen == nil || screen == [UIScreen mainScreen]);

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        UIWindowScene *windowScene;
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        windowScene = (UIWindowScene *)scene;
        if (wantApplicationRole &&
            ![windowScene.session.role isEqualToString:UIWindowSceneSessionRoleApplication]) {
            continue;
        }
        if (screen != nil && windowScene.screen != screen) {
            continue;
        }
        if (windowScene.activationState == UISceneActivationStateForegroundActive) {
            return windowScene;
        }
        if (windowScene.activationState == UISceneActivationStateForegroundInactive && inactive == nil) {
            inactive = windowScene;
        }
        if (fallback == nil) {
            fallback = windowScene;
        }
    }
#pragma clang diagnostic pop

    if (inactive != nil) {
        return inactive;
    }
    if (fallback != nil) {
        return fallback;
    }
    if (screen != nil) {
        return UIKit_GetWindowSceneForScreen(nil);
    }
    return nil;
}

#if !TARGET_OS_TV
UIInterfaceOrientation UIKit_GetInterfaceOrientation(void)
{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (@available(iOS 13.0, *)) {
        UIWindowScene *scene = UIKit_GetWindowSceneForScreen([UIScreen mainScreen]);
        if (scene != nil && scene.interfaceOrientation != UIInterfaceOrientationUnknown) {
            return scene.interfaceOrientation;
        }
    }
    return [UIApplication sharedApplication].statusBarOrientation;
#pragma clang diagnostic pop
}
#endif

void UIKit_ForceUpdateHomeIndicator(void)"""),
])

# --- SDL_uikitmodes.m: orientation from the scene -----------------------------
edit(uikit + "SDL_uikitmodes.m", [
('#include "SDL_uikitmodes.h"\n', '#include "SDL_uikitmodes.h"\n#include "SDL_uikitvideo.h"\n'),
("""        return UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);""",
 """        return UIInterfaceOrientationIsLandscape(UIKit_GetInterfaceOrientation());"""),
("""    BOOL isLandscape = UIInterfaceOrientationIsLandscape([UIApplication sharedApplication].statusBarOrientation);""",
 """    UIInterfaceOrientation interfaceOrientation = UIKit_GetInterfaceOrientation();
    BOOL isLandscape = UIInterfaceOrientationIsLandscape(interfaceOrientation);"""),
("""        switch ([UIApplication sharedApplication].statusBarOrientation) {""",
 """        switch (interfaceOrientation) {"""),
])

# --- SDL_uikitwindow.m: create windows inside the scene -----------------------
edit(uikit + "SDL_uikitwindow.m", [(
"""        uiwindow = [[SDL_uikitwindow alloc] initWithFrame:data.uiscreen.bounds];

        /* put the window on an external display if appropriate. */
        if (data.uiscreen != [UIScreen mainScreen]) {
            [uiwindow setScreen:data.uiscreen];
        }""",
"""        uiwindow = nil;
        if (@available(iOS 13.0, tvOS 13.0, *)) {
            /* With the UIScene life cycle a window must belong to a scene,
             * otherwise it is never shown. */
            UIWindowScene *scene = UIKit_GetWindowSceneForScreen(data.uiscreen);
            if (scene != nil) {
                uiwindow = [[SDL_uikitwindow alloc] initWithWindowScene:scene];
            }
        }
        if (uiwindow == nil) {
            uiwindow = [[SDL_uikitwindow alloc] initWithFrame:data.uiscreen.bounds];

            /* put the window on an external display if appropriate. */
            if (data.uiscreen != [UIScreen mainScreen]) {
                [uiwindow setScreen:data.uiscreen];
            }
        }""")])

# --- SDL_uikitmessagebox.m: alert window inside the scene ---------------------
edit(uikit + "SDL_uikitmessagebox.m", [(
"""        alertwindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];""",
"""        if (@available(iOS 13.0, tvOS 13.0, *)) {
            UIWindowScene *scene = UIKit_GetWindowSceneForScreen([UIScreen mainScreen]);
            if (scene != nil) {
                alertwindow = [[UIWindow alloc] initWithWindowScene:scene];
            }
        }
        if (alertwindow == nil) {
            alertwindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
        }""")])

# --- SDL_uikitappdelegate.h: the delegate is also the scene delegate ----------
edit(uikit + "SDL_uikitappdelegate.h", [(
"""@interface SDLUIKitDelegate : NSObject<UIApplicationDelegate>""",
"""/* Also the window scene delegate, for the UIScene life cycle (iOS 13+). */
@interface SDLUIKitDelegate : NSObject<UIApplicationDelegate, UIWindowSceneDelegate>""")])

# --- SDL_uikitappdelegate.m: start SDL_main from the scene --------------------
edit(uikit + "SDL_uikitappdelegate.m", [
("""static SDL_main_func forward_main;""",
 """static SDL_main_func forward_main;
/* Whether SDL_main has been started; it must only run once. */
static BOOL SDL_main_started = NO;"""),
("""@implementation SDLUIKitDelegate {
    UIWindow *launchWindow;
}""",
 """/* UIScene life cycle: whether a scene is the app's own (not an external display). */
static BOOL UIKit_IsApplicationScene(UIScene *scene) API_AVAILABLE(ios(13.0), tvos(13.0));
static BOOL UIKit_IsApplicationScene(UIScene *scene)
{
    return [scene isKindOfClass:[UIWindowScene class]] &&
           [scene.session.role isEqualToString:UIWindowSceneSessionRoleApplication];
}

@implementation SDLUIKitDelegate {
    UIWindow *launchWindow;
}"""),
("""- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSBundle *bundle = [NSBundle mainBundle];
""",
 """- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
    NSBundle *bundle = [NSBundle mainBundle];

    if (@available(iOS 13.0, tvOS 13.0, *)) {
        /* Apps built with recent SDKs must use the UIScene life cycle, so
         * SDL_main starts when the application's window scene connects (see
         * scene:willConnectToSession:options:) and the system launch screen
         * stays up until then. */
        [[NSFileManager defaultManager] changeCurrentDirectoryPath:[bundle resourcePath]];
        SDL_AddHintCallback(SDL_HINT_IDLE_TIMER_DISABLED,
                            SDL_IdleTimerDisabledChanged, NULL);
        return YES;
    }
"""),
("""- (UIWindow *)window
{""",
 """- (UISceneConfiguration *)application:(UIApplication *)application configurationForConnectingSceneSession:(UISceneSession *)connectingSceneSession options:(UISceneConnectionOptions *)options API_AVAILABLE(ios(13.0), tvos(13.0))
{
    UISceneConfiguration *config = [[UISceneConfiguration alloc] initWithName:@"SDL" sessionRole:connectingSceneSession.role];
    config.delegateClass = [self class];
    return config;
}

- (void)scene:(UIScene *)scene willConnectToSession:(UISceneSession *)session options:(UISceneConnectionOptions *)connectionOptions API_AVAILABLE(ios(13.0), tvos(13.0))
{
    if (!UIKit_IsApplicationScene(scene) || SDL_main_started) {
        return;
    }
    SDL_main_started = YES;
    SDL_SetMainReady();
    [self performSelector:@selector(postFinishLaunch) withObject:nil afterDelay:0.0];
}

- (void)sceneDidBecomeActive:(UIScene *)scene API_AVAILABLE(ios(13.0), tvos(13.0))
{
    if (UIKit_IsApplicationScene(scene)) {
        SDL_OnApplicationDidBecomeActive();
    }
}

- (void)sceneWillResignActive:(UIScene *)scene API_AVAILABLE(ios(13.0), tvos(13.0))
{
    if (UIKit_IsApplicationScene(scene)) {
        SDL_OnApplicationWillResignActive();
    }
}

- (void)sceneWillEnterForeground:(UIScene *)scene API_AVAILABLE(ios(13.0), tvos(13.0))
{
    if (UIKit_IsApplicationScene(scene)) {
        SDL_OnApplicationWillEnterForeground();
    }
}

- (void)sceneDidEnterBackground:(UIScene *)scene API_AVAILABLE(ios(13.0), tvos(13.0))
{
    if (UIKit_IsApplicationScene(scene)) {
        SDL_OnApplicationDidEnterBackground();
    }
}

- (void)scene:(UIScene *)scene openURLContexts:(NSSet<UIOpenURLContext *> *)URLContexts API_AVAILABLE(ios(13.0), tvos(13.0))
{
    for (UIOpenURLContext *context in URLContexts) {
        [self sendDropFileForURL:context.URL];
    }
}

- (UIWindow *)window
{"""),
])
print("Added UIScene life cycle support to SDL2")
