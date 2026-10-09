#import "IrisCompatibility.h"
#import <objc/runtime.h>
#import <string.h>

// Independently reimplemented from observed Iris12 0.0.2 behavior.
// The downloaded tweak binary is not bundled with this app.
typedef struct { __unsafe_unretained Class cls; SEL selector; IMP original; } MCHook;
static MCHook hooks[3];
static NSUInteger hookCount = 0;
static BOOL MCYes(id object, SEL selector) { return YES; }

NSString *MCIrisInstallHooks(void) {
    @synchronized ([AVCapturePhotoOutput class]) {
        if (hookCount != 0) { return @"Iris12 capability hooks are installed in MirrorCam."; }
        if (@available(iOS 13.0, *)) { return @"The Iris12 experiment is restricted to iOS 12."; }
        const char *classes[] = {"CAMCaptureCapabilities", "CAMCaptureCapabilities", "AVCaptureDeviceFormat"};
        const char *selectors[] = {"isBackIrisSupported", "isFrontIrisSupported", "isIrisSupported"};
        NSMutableArray<NSString *> *installed = [NSMutableArray array];
        for (NSUInteger i = 0; i < 3; i++) {
            Class cls = objc_getClass(classes[i]);
            SEL selector = sel_registerName(selectors[i]);
            Method method = cls ? class_getInstanceMethod(cls, selector) : NULL;
            if (!method || method_getNumberOfArguments(method) != 2) { continue; }
            char returnType[16] = {0};
            method_getReturnType(method, returnType, sizeof(returnType));
            // arm64 Objective-C BOOL is 'B'; older SDK methods may encode it as 'c'.
            if (strcmp(returnType, "B") != 0 && strcmp(returnType, "c") != 0) { continue; }
            hooks[hookCount++] = (MCHook){cls, selector, method_getImplementation(method)};
            class_replaceMethod(cls, selector, (IMP)MCYes, method_getTypeEncoding(method));
            [installed addObject:[NSString stringWithFormat:@"%s.%s", classes[i], selectors[i]]];
        }
        if (hookCount == 0) { return @"No compatible Iris12 capability methods were found. Software LIVE remains available."; }
        return [@"Hooked inside MirrorCam: " stringByAppendingString:[installed componentsJoinedByString:@", "]];
    }
}

void MCIrisRestoreHooks(void) {
    @synchronized ([AVCapturePhotoOutput class]) {
        for (NSUInteger i = 0; i < hookCount; i++) {
            Method method = class_getInstanceMethod(hooks[i].cls, hooks[i].selector);
            if (method) { class_replaceMethod(hooks[i].cls, hooks[i].selector, hooks[i].original, method_getTypeEncoding(method)); }
        }
        hookCount = 0;
    }
}

NSString *MCSetLivePhotoEnabled(AVCapturePhotoOutput *output, BOOL enabled) {
    @try {
        if (enabled && !output.livePhotoCaptureSupported) { return @"AVFoundation still reports native Live Photos unsupported."; }
        output.livePhotoCaptureEnabled = enabled;
        return enabled && !output.livePhotoCaptureEnabled ? @"AVFoundation did not enable native Live Photo capture." : nil;
    } @catch (NSException *exception) {
        return exception.reason ?: @"AVFoundation rejected native Live Photo configuration.";
    }
}

NSString *MCCaptureNativeLivePhoto(AVCapturePhotoOutput *output, AVCapturePhotoSettings *settings,
                                  id<AVCapturePhotoCaptureDelegate> delegate) {
    @try {
        [output capturePhotoWithSettings:settings delegate:delegate];
        return nil;
    } @catch (NSException *exception) {
        return exception.reason ?: @"AVFoundation rejected native Live Photo capture.";
    }
}
