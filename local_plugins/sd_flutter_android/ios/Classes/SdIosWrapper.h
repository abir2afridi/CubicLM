#import <Foundation/Foundation.h>

typedef void (^SdProgressBlock)(int step, int totalSteps);

@interface SdIosWrapper : NSObject

@property (nonatomic, copy) SdProgressBlock onProgress;

/// Returns "true" on success, or an error message string on failure.
- (NSString *)loadModel:(NSString *)path;
- (NSData *)generateImage:(NSString *)prompt steps:(int)steps;
- (void)unloadModel;

@end
