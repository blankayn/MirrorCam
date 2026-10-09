#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN
/// Changes dispatch only inside MirrorCam. No Substrate or external dylib is loaded.
FOUNDATION_EXPORT NSString *MCIrisInstallHooks(void);
FOUNDATION_EXPORT void MCIrisRestoreHooks(void);
/// Returns an exception/rejection message, or nil on success.
FOUNDATION_EXPORT NSString * _Nullable MCSetLivePhotoEnabled(AVCapturePhotoOutput *output, BOOL enabled);
FOUNDATION_EXPORT NSString * _Nullable MCCaptureNativeLivePhoto(AVCapturePhotoOutput *output,
    AVCapturePhotoSettings *settings, id<AVCapturePhotoCaptureDelegate> delegate);
NS_ASSUME_NONNULL_END
