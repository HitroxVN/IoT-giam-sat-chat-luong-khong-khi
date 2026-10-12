// ASCrashLog — Global handler for uncaught NSExceptions and fatal Unix signals.
// Records a compact summary so Settings can surface it under "Diagnostics".
// Written defensively: the on-crash path only uses write(2) — no Objective-C
// allocation, to avoid a second abort before the crash is persisted.

#import "Application/ASCrashLog.h"
#include <signal.h>
#include <execinfo.h>
#include <unistd.h>

static const char * const kCrashLogPath = "/var/mobile/Library/Preferences/com.airsense.crashlog";

static void captureStackTrace(char *out, size_t maxLen)
{
    void *frames[32];
    int count = backtrace(frames, 32);
    if (count < 2) { out[0] = '\0'; return; }

    char **symbols = backtrace_symbols(frames, count);
    if (!symbols) { out[0] = '\0'; return; }

    size_t written = 0;
    out[0] = '\0';
    for (int i = 1; i < count && written < maxLen - 1; i++) {  // skip frame 0: the handler itself
        size_t len = strnlen(symbols[i], maxLen - 1 - written);
        if (len == 0) continue;
        memcpy(out + written, symbols[i], len);
        written += len;
        if (written < maxLen - 1) out[written++] = '\n';
        out[written] = '\0';
    }
    free(symbols);
}

static void writeCrash(const char *reason, const char *callStack)
{
    size_t rLen = strnlen(reason, 255);
    size_t sLen = callStack ? strnlen(callStack, 511) : 0;
    size_t total = rLen + sLen;

    char buf[1024];
    if (total >= sizeof(buf)) sLen = (sizeof(buf) - 1) - rLen;

    memcpy(buf, reason, rLen);
    if (sLen) memcpy(buf + rLen, callStack, sLen);
    buf[rLen + sLen] = '\0';

    int fd = open(kCrashLogPath, O_WRONLY | O_CREAT | O_TRUNC, 0644);
    if (fd >= 0) {
        write(fd, buf, rLen + sLen);
        close(fd);
    }
}

static void signalHandler(int sig)
{
    char stack[512], reason[128];
    captureStackTrace(stack, sizeof(stack));
    snprintf(reason, sizeof(reason), "POSIX signal %d (%s)", sig, strsignal(sig));
    writeCrash(reason, stack);

    signal(sig, SIG_DFL);
    raise(sig);
}

static void exceptionHandler(NSException *exception)
{
    char stack[512];
    captureStackTrace(stack, sizeof(stack));
    writeCrash(exception.reason.UTF8String ?: "<no reason>", stack);

    // Re-raise so the system crash reporter still logs a real abort.
    @throw exception;
}

@implementation ASCrashLog

+ (instancetype)shared
{
    static ASCrashLog *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[ASCrashLog alloc] init]; });
    return instance;
}

- (void)install
{
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSSetUncaughtExceptionHandler(&exceptionHandler);
        signal(SIGABRT, signalHandler);
        signal(SIGBUS,  signalHandler);
        signal(SIGFPE,  signalHandler);
        signal(SIGILL,  signalHandler);
        signal(SIGPIPE, signalHandler);
        signal(SIGSEGV, signalHandler);
        signal(SIGSYS,  signalHandler);
        signal(SIGTRAP, signalHandler);
    });
}

- (NSString *)lastCrashReason
{
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:[NSString stringWithUTF8String:kCrashLogPath]];
    if (data.length == 0) return nil;
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    // The persisted record is "reason\n<stack>"; surface just the headline.
    NSRange nl = [raw rangeOfString:@"\n"];
    return nl.location == NSNotFound ? raw : [raw substringToIndex:nl.location];
}

- (NSString *)lastCrashCallStack
{
    NSData *data = [[NSFileManager defaultManager] contentsAtPath:[NSString stringWithUTF8String:kCrashLogPath]];
    if (data.length == 0) return nil;
    NSString *raw = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    NSRange nl = [raw rangeOfString:@"\n"];
    return nl.location == NSNotFound
        ? raw
        : [raw substringFromIndex:MIN(nl.location + 1, raw.length)];
}

@end
