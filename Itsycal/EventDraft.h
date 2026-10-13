//
//  EventDraft.h
//  Itsycal
//
//  A proposed new event, extracted from dropped or pasted
//  content. EventViewController uses it to prefill its form.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface EventDraft : NSObject

// YES if the content looked like an event. If NO, the other
// properties are best guesses and may all be nil.
@property (nonatomic) BOOL recognized;

@property (nonatomic, copy, nullable) NSString *title;
@property (nonatomic, copy, nullable) NSString *location;
@property (nonatomic, copy, nullable) NSString *url;
@property (nonatomic, copy, nullable) NSDate *startDate;
@property (nonatomic, copy, nullable) NSDate *endDate;
@property (nonatomic) BOOL allDay;

// The text the draft was extracted from (OCR text for images).
@property (nonatomic, copy, nullable) NSString *sourceText;

@end

NS_ASSUME_NONNULL_END
