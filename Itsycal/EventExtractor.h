//
//  EventExtractor.h
//  Itsycal
//
//  Turns dropped or pasted content (an image, text, or a text
//  clipping) into an EventDraft.
//
//  Images are OCR'd on-device with Vision. Code finds candidate
//  values in the text (dates and times, addresses and links with
//  NSDataDetector; lines for titles and locations), then one
//  TypeSafe (Jev) request picks which candidate plays which role.
//  Because Jev only ever chooses among spans found in the text,
//  every prefilled value is copied from the source; it can't be
//  invented. Date arithmetic stays in code.
//
//  Without an API key, or if the request fails, a simple
//  heuristic fills what it can.
//

#import <Cocoa/Cocoa.h>
#import "EventDraft.h"

NS_ASSUME_NONNULL_BEGIN

typedef void (^EventExtractorCompletion)(EventDraft *draft);

// NSUserDefaults key for the TypeSafe API key. If unset, the
// TYPESAFE_API_KEY environment variable is used.
extern NSString * const kTypeSafeAPIKey;

@interface EventExtractor : NSObject

// Pasteboard types to register for drag and drop.
+ (NSArray<NSPasteboardType> *)readablePasteboardTypes;

// YES if the pasteboard holds an image, text, or a text file.
+ (BOOL)canReadPasteboard:(NSPasteboard *)pboard;

// Reads the pasteboard immediately (call it while the drag or
// paste is in progress), then extracts asynchronously.
// Returns NO if there was nothing usable on the pasteboard.
// The completion block is called on the main queue.
+ (BOOL)extractFromPasteboard:(NSPasteboard *)pboard completion:(EventExtractorCompletion)completion;

+ (void)extractFromImage:(NSImage *)image completion:(EventExtractorCompletion)completion;
+ (void)extractFromText:(NSString *)text completion:(EventExtractorCompletion)completion;

@end

NS_ASSUME_NONNULL_END
