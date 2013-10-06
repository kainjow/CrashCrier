//
//  Created by Kevin Wojniak on 7/1/13.
//  Copyright (c) 2013 Kevin Wojniak. All rights reserved.
//

#import "AppDelegate.h"

@interface AppDelegate (Private)
- (void)processCrash:(NSURL *)url;
@end

static void eventStreamCallback(ConstFSEventStreamRef streamRef, void *clientCallBackInfo, size_t numEvents, void *eventPaths, const FSEventStreamEventFlags eventFlags[], const FSEventStreamEventId eventIds[])
{
    NSArray *paths = (__bridge NSArray*)eventPaths;
    for (size_t i = 0; i < paths.count; ++i) {
        if (eventFlags[i] & kFSEventStreamEventFlagItemCreated) {
            NSURL *url = [NSURL fileURLWithPath:paths[i]];
            NSNumber *isHidden = nil;
            (void)[url getResourceValue:&isHidden forKey:NSURLIsHiddenKey error:nil];
            // Ignore the hidden binary plist crash reports that get created
            if (![isHidden boolValue]) {
                AppDelegate *appDelegate = (__bridge AppDelegate*)clientCallBackInfo;
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    [appDelegate processCrash:url];
                });
            }
        }
    }
}

@implementation AppDelegate

- (id)init
{
    if ((self = [super init]) != nil) {
        FSEventStreamContext ctx;
        bzero(&ctx, sizeof(ctx));
        ctx.info = (__bridge void*)self;
        
        NSArray *paths = @[
            [@"~/Library/Logs/DiagnosticReports/" stringByStandardizingPath],
            @"/Library/Logs/DiagnosticReports/",
        ];
        FSEventStreamCreateFlags flags = kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents;
        FSEventStreamRef stream = FSEventStreamCreate(kCFAllocatorDefault, eventStreamCallback, &ctx, (__bridge CFArrayRef)paths, kFSEventStreamEventIdSinceNow, 1.0, flags);
        FSEventStreamScheduleWithRunLoop(stream, CFRunLoopGetMain(), kCFRunLoopDefaultMode);
        if (!FSEventStreamStart(stream)) {
            NSLog(@"Couldn't started stream");
        }
    }
    return self;
}

- (void)processCrash:(NSURL *)url
{
    NSString *text = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:nil];
    if (text) {
        NSRegularExpressionOptions options = NSRegularExpressionCaseInsensitive | NSRegularExpressionDotMatchesLineSeparators;
        NSError *err = nil;
        NSString *pattern = @"^Process:\\s+(.+?)\\s+\\[\\d*]\n.*Path:\\s+(.+?)\n.*Exception Type:\\s+(.+?)\n";
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:options error:&err];
        if (err) {
            NSLog(@"%@", err);
        }
        NSTextCheckingResult *result = [regex firstMatchInString:text options:0 range:NSMakeRange(0, [text length])];
        if (result) {
            @try {
                NSRange nameRange = [result rangeAtIndex:1];
                NSRange pathRange = [result rangeAtIndex:2];
                NSRange typeRange = [result rangeAtIndex:3];
                NSString *processName = [text substringWithRange:nameRange];
                NSString *path = [text substringWithRange:pathRange];
                NSString *exceptionType = [text substringWithRange:typeRange];
                NSUserNotification *userNotif = [[NSUserNotification alloc] init];
                userNotif.title = [NSString stringWithFormat:NSLocalizedString(@"%@ crashed", ""), processName];
                userNotif.subtitle = exceptionType;
                userNotif.informativeText = path;
                userNotif.userInfo = @{@"path" : [url path]};
                NSUserNotificationCenter *userNotifCenter = [NSUserNotificationCenter defaultUserNotificationCenter];
                userNotifCenter.delegate = self;
                [userNotifCenter deliverNotification:userNotif];
            } @catch (NSException *ex) {
                NSLog(@"%@", ex);
            }
        }
    }
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didActivateNotification:(NSUserNotification *)notification
{
    NSURL *url = [NSURL fileURLWithPath:notification.userInfo[@"path"]];
    (void)[[NSWorkspace sharedWorkspace] openURL:url];
}

- (void)userNotificationCenter:(NSUserNotificationCenter *)center didDeliverNotification:(NSUserNotification *)notification
{
    [center removeDeliveredNotification:notification];
}

@end

int main(int argc, const char * argv[])
{
    @autoreleasepool {
        (void)[NSApplication sharedApplication];
        AppDelegate *app = [[AppDelegate alloc] init];
        [NSApp setDelegate:app];
        [NSApp run];
        return EXIT_SUCCESS;
    }
}
