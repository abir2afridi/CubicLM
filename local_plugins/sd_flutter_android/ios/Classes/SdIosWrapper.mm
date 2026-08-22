#import "SdIosWrapper.h"
#include "stable-diffusion.h"

static sd_ctx_t* g_sd_ctx = nullptr;
static SdProgressBlock g_progress_block = nil;
static NSMutableString *g_last_logs = nil;

static void ios_sd_progress_cb(int step, int steps, float time, void* data) {
    if (g_progress_block) {
        g_progress_block(step, steps);
    }
}

static void ios_sd_log_cb(sd_log_level_t level, const char* text, void* data) {
    NSString *line = [NSString stringWithUTF8String:text];
    NSLog(@"[SD-CPP] %@", line);
    if (g_last_logs) {
        [g_last_logs appendString:line];
        [g_last_logs appendString:@"\n"];
    }
}

@implementation SdIosWrapper

- (NSString *)loadModel:(NSString *)path {
    if (g_sd_ctx) {
        free_sd_ctx(g_sd_ctx);
        g_sd_ctx = nullptr;
    }

    g_last_logs = [NSMutableString string];

    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:path]) {
        NSString *err = [NSString stringWithFormat:@"Model file does NOT exist at path: %@", path];
        NSLog(@"[SD-iOS] ERROR: %@", err);
        return err;
    }

    NSError *err = nil;
    NSDictionary *attrs = [fm attributesOfItemAtPath:path error:&err];
    if (attrs) {
        NSLog(@"[SD-iOS] Model file exists, size: %llu bytes", [attrs fileSize]);
    } else {
        NSLog(@"[SD-iOS] WARNING: Cannot read file attributes: %@", err);
    }

    sd_set_log_callback(ios_sd_log_cb, NULL);

    sd_ctx_params_t params;
    sd_ctx_params_init(&params);
    params.model_path = [path UTF8String];
    params.n_threads = sd_get_num_physical_cores();
    params.free_params_immediately = false;  // Keep buffers alive between generations

    NSLog(@"[SD-iOS] Calling new_sd_ctx...");
    g_sd_ctx = new_sd_ctx(&params);

    if (!g_sd_ctx) {
        NSString *errorMsg = [NSString stringWithFormat:@"new_sd_ctx returned nullptr. Logs:\n%@", g_last_logs];
        NSLog(@"[SD-iOS] ERROR: %@", errorMsg);
        return errorMsg;
    }

    NSLog(@"[SD-iOS] SUCCESS: new_sd_ctx returned valid context");
    return @"true";
}

- (NSData *)generateImage:(NSString *)prompt steps:(int)steps {
    if (!g_sd_ctx) return nil;

    sd_img_gen_params_t params;
    sd_img_gen_params_init(&params);
    params.prompt = [prompt UTF8String];
    params.sample_params.sample_steps = steps;
    params.width = 512;
    params.height = 512;
    params.sample_params.sample_method = EULER_A_SAMPLE_METHOD;

    g_progress_block = self.onProgress;
    sd_set_progress_callback(ios_sd_progress_cb, NULL);

    sd_image_t* result = generate_image(g_sd_ctx, &params);

    g_progress_block = nil;
    sd_set_progress_callback(NULL, NULL);

    if (!result) return nil;

    size_t size = result->width * result->height * result->channel;
    NSData *data = [NSData dataWithBytes:result->data length:size];

    free(result->data);
    free(result);

    return data;
}

- (void)unloadModel {
    if (g_sd_ctx) {
        free_sd_ctx(g_sd_ctx);
        g_sd_ctx = nullptr;
    }
}

@end
