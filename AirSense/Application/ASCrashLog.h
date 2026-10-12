// ASCrashLog — Lightweight uncaught-exception + Unix-signal logger.
// Captures crash metadata (name, reason, call stack) and records the most recent
// crash to NSUserDefaults so a debug-oriented settings panel can surface it.
// Intentionally dependency-free: no third-party SDK, no network — just a guard
// installed at the end of application launch.

#import <Foundation/Foundation.h>

@interface ASCrashLog : NSObject

+ (instancetype)shared;

/// Installs the global exception & signal handlers. Safe to call more than once.
- (void)install;

/// Most recent crash summary as recorded by the previous app session.
@property (nonatomic, readonly, copy) NSString *lastCrashReason;

/// Call stack strings from the last crash, joined by newlines.
@property (nonatomic, readonly, copy) NSString *lastCrashCallStack;

@end