#import "Display.h"
#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

@interface NSObject (VirtualDisplay)
- (instancetype)initWithDescriptor:(id)descriptor;
- (instancetype)initWithWidth:(NSUInteger)width height:(NSUInteger)height refreshRate:(double)hz;
- (BOOL)applySettings:(id)settings;
- (CGDirectDisplayID)displayID;
@end

// CoreGraphics retains the display for the lifetime of this object.
static id retainedDisplay;
CGDirectDisplayID createQADisplay(void) {
    @try {
        id descriptor = [NSClassFromString(@"CGVirtualDisplayDescriptor") new];
        [descriptor setValue:@"Pacemark QA" forKey:@"name"];
        [descriptor setValue:@3024 forKey:@"maxPixelsWide"];
        [descriptor setValue:@1964 forKey:@"maxPixelsHigh"];
        [descriptor setValue:@(arc4random_uniform(0xffffff) + 1) forKey:@"serialNum"];
        [descriptor setValue:@0x5141 forKey:@"productID"];
        [descriptor setValue:@0xf0f0 forKey:@"vendorID"];
        [descriptor setValue:[NSValue valueWithSize:NSMakeSize(345, 224)] forKey:@"sizeInMillimeters"];
        [descriptor setValue:dispatch_get_main_queue() forKey:@"queue"];
        retainedDisplay = [[NSClassFromString(@"CGVirtualDisplay") alloc] initWithDescriptor:descriptor];
        id mode = [[NSClassFromString(@"CGVirtualDisplayMode") alloc] initWithWidth:1512 height:982 refreshRate:60];
        id settings = [NSClassFromString(@"CGVirtualDisplaySettings") new];
        [settings setValue:@1 forKey:@"hiDPI"];
        [settings setValue:@[mode] forKey:@"modes"];
        return [retainedDisplay applySettings:settings] ? [retainedDisplay displayID] : 0;
    } @catch (NSException *exception) {
        NSLog(@"QA display unavailable: %@", exception.reason);
        return 0;
    }
}
pid_t qaResponsiblePID(void) {
    pid_t (*responsible)(pid_t) = dlsym(RTLD_DEFAULT, "responsibility_get_pid_responsible_for_pid");
    return responsible ? responsible(getpid()) : getpid();
}
