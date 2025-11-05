//
//  Generated file. Do not edit.
//

// clang-format off

#import "GeneratedPluginRegistrant.h"

#if __has_include(<battery_plus/FPPBatteryPlusPlugin.h>)
#import <battery_plus/FPPBatteryPlusPlugin.h>
#else
@import battery_plus;
#endif

#if __has_include(<device_info_plus/FPPDeviceInfoPlusPlugin.h>)
#import <device_info_plus/FPPDeviceInfoPlusPlugin.h>
#else
@import device_info_plus;
#endif

#if __has_include(<file_picker/FilePickerPlugin.h>)
#import <file_picker/FilePickerPlugin.h>
#else
@import file_picker;
#endif

#if __has_include(<flutter_background_service_ios/FlutterBackgroundServicePlugin.h>)
#import <flutter_background_service_ios/FlutterBackgroundServicePlugin.h>
#else
@import flutter_background_service_ios;
#endif

#if __has_include(<google_mlkit_commons/GoogleMlKitCommonsPlugin.h>)
#import <google_mlkit_commons/GoogleMlKitCommonsPlugin.h>
#else
@import google_mlkit_commons;
#endif

#if __has_include(<google_mlkit_face_detection/GoogleMlKitFaceDetectionPlugin.h>)
#import <google_mlkit_face_detection/GoogleMlKitFaceDetectionPlugin.h>
#else
@import google_mlkit_face_detection;
#endif

#if __has_include(<google_mlkit_object_detection/GoogleMlKitObjectDetectionPlugin.h>)
#import <google_mlkit_object_detection/GoogleMlKitObjectDetectionPlugin.h>
#else
@import google_mlkit_object_detection;
#endif

#if __has_include(<image_cropper/FLTImageCropperPlugin.h>)
#import <image_cropper/FLTImageCropperPlugin.h>
#else
@import image_cropper;
#endif

#if __has_include(<package_info_plus/FPPPackageInfoPlusPlugin.h>)
#import <package_info_plus/FPPPackageInfoPlusPlugin.h>
#else
@import package_info_plus;
#endif

#if __has_include(<path_provider_foundation/PathProviderPlugin.h>)
#import <path_provider_foundation/PathProviderPlugin.h>
#else
@import path_provider_foundation;
#endif

#if __has_include(<permission_handler_apple/PermissionHandlerPlugin.h>)
#import <permission_handler_apple/PermissionHandlerPlugin.h>
#else
@import permission_handler_apple;
#endif

#if __has_include(<shared_preferences_foundation/SharedPreferencesPlugin.h>)
#import <shared_preferences_foundation/SharedPreferencesPlugin.h>
#else
@import shared_preferences_foundation;
#endif

#if __has_include(<sqflite_darwin/SqflitePlugin.h>)
#import <sqflite_darwin/SqflitePlugin.h>
#else
@import sqflite_darwin;
#endif

#if __has_include(<url_launcher_ios/URLLauncherPlugin.h>)
#import <url_launcher_ios/URLLauncherPlugin.h>
#else
@import url_launcher_ios;
#endif

#if __has_include(<workmanager_apple/WorkmanagerPlugin.h>)
#import <workmanager_apple/WorkmanagerPlugin.h>
#else
@import workmanager_apple;
#endif

@implementation GeneratedPluginRegistrant

+ (void)registerWithRegistry:(NSObject<FlutterPluginRegistry>*)registry {
  [FPPBatteryPlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPBatteryPlusPlugin"]];
  [FPPDeviceInfoPlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPDeviceInfoPlusPlugin"]];
  [FilePickerPlugin registerWithRegistrar:[registry registrarForPlugin:@"FilePickerPlugin"]];
  [FlutterBackgroundServicePlugin registerWithRegistrar:[registry registrarForPlugin:@"FlutterBackgroundServicePlugin"]];
  [GoogleMlKitCommonsPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitCommonsPlugin"]];
  [GoogleMlKitFaceDetectionPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitFaceDetectionPlugin"]];
  [GoogleMlKitObjectDetectionPlugin registerWithRegistrar:[registry registrarForPlugin:@"GoogleMlKitObjectDetectionPlugin"]];
  [FLTImageCropperPlugin registerWithRegistrar:[registry registrarForPlugin:@"FLTImageCropperPlugin"]];
  [FPPPackageInfoPlusPlugin registerWithRegistrar:[registry registrarForPlugin:@"FPPPackageInfoPlusPlugin"]];
  [PathProviderPlugin registerWithRegistrar:[registry registrarForPlugin:@"PathProviderPlugin"]];
  [PermissionHandlerPlugin registerWithRegistrar:[registry registrarForPlugin:@"PermissionHandlerPlugin"]];
  [SharedPreferencesPlugin registerWithRegistrar:[registry registrarForPlugin:@"SharedPreferencesPlugin"]];
  [SqflitePlugin registerWithRegistrar:[registry registrarForPlugin:@"SqflitePlugin"]];
  [URLLauncherPlugin registerWithRegistrar:[registry registrarForPlugin:@"URLLauncherPlugin"]];
  [WorkmanagerPlugin registerWithRegistrar:[registry registrarForPlugin:@"WorkmanagerPlugin"]];
}

@end
