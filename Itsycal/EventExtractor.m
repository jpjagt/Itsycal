//
//  EventExtractor.m
//  Itsycal
//

#import "EventExtractor.h"
#import <Vision/Vision.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <os/log.h>

NSString * const kTypeSafeAPIKey = @"TypeSafeAPIKey";

static NSString * const kTypeSafeEndpoint = @"https://api.typesafe.ai/v1/systemone";
static NSString * const kTypeSafeModel = @"jev-latest";

// Choice option meaning "none of these candidates".
static NSString * const kNone = @"none";

// Keep requests small: Jev does best with focused state.
static const NSUInteger kMaxTextLength = 6000;
static const NSUInteger kMaxLineCandidates = 60;
static const NSUInteger kMaxLineLength = 150;

// Threshold for Jev's "is this an event?" (noul) answer.
static const double kIsEventThreshold = 0.35;

#pragma mark -
#pragma mark Candidates

// Values found in the text by code. Jev picks among these.
@interface EventCandidates : NSObject
@property (nonatomic) NSString *text;
// Span text -> NSTextCheckingResult. Ordered keys in *Spans.
@property (nonatomic) NSMutableArray<NSString *> *dateSpans;
@property (nonatomic) NSMutableDictionary<NSString *, NSTextCheckingResult *> *dates;
@property (nonatomic) NSMutableArray<NSString *> *addressSpans;
@property (nonatomic) NSMutableArray<NSString *> *links;
@property (nonatomic) NSMutableArray<NSString *> *lines;
@end

@implementation EventCandidates
@end

static void AddUnique(NSMutableArray<NSString *> *array, NSString *s)
{
    if (s.length && ![array containsObject:s]) [array addObject:s];
}

static NSString *CollapseWhitespace(NSString *s)
{
    NSArray *parts = [s componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    parts = [parts filteredArrayUsingPredicate:[NSPredicate predicateWithFormat:@"length > 0"]];
    return [parts componentsJoinedByString:@" "];
}

static EventCandidates *FindCandidates(NSString *text)
{
    EventCandidates *c = [EventCandidates new];
    c.text = text;
    c.dateSpans = [NSMutableArray new];
    c.dates = [NSMutableDictionary new];
    c.addressSpans = [NSMutableArray new];
    c.links = [NSMutableArray new];
    c.lines = [NSMutableArray new];

    NSDataDetector *detector = [NSDataDetector dataDetectorWithTypes:NSTextCheckingTypeDate | NSTextCheckingTypeAddress | NSTextCheckingTypeLink error:NULL];

    // Detect in the original text and again with newlines
    // flattened, so a date and a time on adjacent lines
    // ("Fri, Oct 17" / "7:00 PM") also form one candidate.
    // Over-finding is fine; Jev picks the one that fits.
    NSString *flattened = CollapseWhitespace(text);
    for (NSString *source in @[text, flattened]) {
        [detector enumerateMatchesInString:source options:0 range:NSMakeRange(0, source.length) usingBlock:^(NSTextCheckingResult *result, NSMatchingFlags flags, BOOL *stop) {
            NSString *span = CollapseWhitespace([source substringWithRange:result.range]);
            if (result.resultType == NSTextCheckingTypeDate && result.date) {
                if (!c.dates[span]) {
                    c.dates[span] = result;
                    [c.dateSpans addObject:span];
                }
            }
            else if (result.resultType == NSTextCheckingTypeAddress) {
                AddUnique(c.addressSpans, span);
            }
            else if (result.resultType == NSTextCheckingTypeLink && result.URL) {
                if (![result.URL.scheme isEqualToString:@"mailto"]) {
                    AddUnique(c.links, result.URL.absoluteString);
                }
            }
        }];
    }

    // Lines (and sentences of long lines) are title and
    // location candidates.
    [text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
        line = CollapseWhitespace(line);
        if (line.length < 2) return;
        if (line.length <= 60) {
            AddUnique(c.lines, line);
            return;
        }
        [line enumerateSubstringsInRange:NSMakeRange(0, line.length) options:NSStringEnumerationBySentences usingBlock:^(NSString *sentence, NSRange r, NSRange er, BOOL *stop2) {
            sentence = CollapseWhitespace(sentence);
            if (sentence.length < 2) return;
            if (sentence.length > kMaxLineLength) {
                sentence = [sentence substringToIndex:kMaxLineLength];
            }
            AddUnique(c.lines, sentence);
        }];
    }];
    if (c.lines.count > kMaxLineCandidates) {
        [c.lines removeObjectsInRange:NSMakeRange(kMaxLineCandidates, c.lines.count - kMaxLineCandidates)];
    }
    return c;
}

#pragma mark -
#pragma mark Assembling a draft

static NSString *TrimSeparators(NSString *s)
{
    NSMutableCharacterSet *set = [NSMutableCharacterSet whitespaceAndNewlineCharacterSet];
    [set addCharactersInString:@"-–—,;:|@·•()[]"];
    return [s stringByTrimmingCharactersInSet:set];
}

// "Dinner with Sam — Fri Oct 17, 7pm" -> "Dinner with Sam"
static NSString *CleanTitle(NSString *line, NSArray<NSString *> *spansToRemove)
{
    NSString *title = line;
    for (NSString *span in spansToRemove) {
        if (span.length) {
            title = [title stringByReplacingOccurrencesOfString:span withString:@" " options:NSCaseInsensitiveSearch range:NSMakeRange(0, title.length)];
        }
    }
    title = CollapseWhitespace(title);
    // ...and orphaned punctuation: "Party - , bring snacks" -> "Party, bring snacks"
    title = [title stringByReplacingOccurrencesOfString:@"\\s[-–—|]\\s" withString:@" " options:NSRegularExpressionSearch range:NSMakeRange(0, title.length)];
    title = [title stringByReplacingOccurrencesOfString:@"\\s+([,;:])" withString:@"$1" options:NSRegularExpressionSearch range:NSMakeRange(0, title.length)];
    title = TrimSeparators(title);
    // Removing a date can leave a dangling word behind:
    // "Dinner with Sam on ?" -> "Dinner with Sam"
    NSRegularExpression *dangling = [NSRegularExpression regularExpressionWithPattern:@"(\\s+(on|at|from|until|till|to|by|for|this|next|in|starting))+[\\s?!.]*$" options:NSRegularExpressionCaseInsensitive error:NULL];
    title = [dangling stringByReplacingMatchesInString:title options:0 range:NSMakeRange(0, title.length) withTemplate:@""];
    title = TrimSeparators(title);
    // Don't strip it down to nothing (or to a fragment).
    if (title.length < 3) title = TrimSeparators(line);
    return title;
}

// "Location: Blue Bottle, 66 Mint St" -> "Blue Bottle, 66 Mint St"
static NSString *CleanLocation(NSString *line)
{
    NSRegularExpression *label = [NSRegularExpression regularExpressionWithPattern:@"^\\s*(location|where|venue|address|place|room|📍)\\s*[:\\-–]?\\s*" options:NSRegularExpressionCaseInsensitive error:NULL];
    NSString *loc = [label stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0, line.length) withTemplate:@""];
    loc = TrimSeparators(loc);
    if ([loc hasSuffix:@"."]) loc = [loc substringToIndex:loc.length - 1];
    return loc.length ? loc : line;
}

static NSString *Pick(NSDictionary *answers, NSString *key)
{
    NSString *choice = answers[key][@"choice"];
    if (![choice isKindOfClass:[NSString class]] || [choice isEqualToString:kNone]) return nil;
    return choice;
}

static double Noul(NSDictionary *answers, NSString *key, double fallback)
{
    NSNumber *n = answers[key][@"noul"];
    return [n isKindOfClass:[NSNumber class]] ? n.doubleValue : fallback;
}

// The day of `daySpan` at the time of day of `timeSpan`.
static NSDate *Combine(NSTextCheckingResult *day, NSTextCheckingResult *time, NSCalendar *cal)
{
    NSDateComponents *dc = [cal components:NSCalendarUnitYear | NSCalendarUnitMonth | NSCalendarUnitDay fromDate:day.date];
    NSDateComponents *tc = [cal components:NSCalendarUnitHour | NSCalendarUnitMinute fromDate:time.date];
    dc.hour = tc.hour;
    dc.minute = tc.minute;
    return [cal dateFromComponents:dc];
}

// Jev picks which spans give the event's day, start time, and
// end time; code does the date arithmetic. Jev reads dates as
// text, so it never compares or computes them.
static EventDraft *AssembleDraft(EventCandidates *c, NSString *titleLine, NSString *locationLine, NSString *link, NSString *daySpan, NSString *startTimeSpan, NSString *endTimeSpan, BOOL recognized)
{
    EventDraft *draft = [EventDraft new];
    draft.sourceText = c.text;
    draft.recognized = recognized;
    if (!recognized) return draft;

    NSCalendar *cal = [NSCalendar currentCalendar];
    NSTextCheckingResult *day = daySpan ? c.dates[daySpan] : nil;
    NSTextCheckingResult *startTime = startTimeSpan ? c.dates[startTimeSpan] : nil;
    NSTextCheckingResult *endTime = endTimeSpan ? c.dates[endTimeSpan] : nil;
    // A time with no day ("8 PM") is today; a day with no time
    // of day is an all-day event.
    if (!day) day = startTime;

    if (day && startTime) {
        draft.startDate = Combine(day, startTime, cal);
        if (endTime && endTime != startTime) {
            draft.endDate = Combine(day, endTime, cal);
            // "10 PM – 1 AM" ends the next day.
            if ([draft.endDate compare:draft.startDate] != NSOrderedDescending) {
                draft.endDate = [cal dateByAddingUnit:NSCalendarUnitDay value:1 toDate:draft.endDate options:0];
            }
        }
        else if (startTime.duration > 0) {
            // A range like "3–5pm" is one span with a duration.
            draft.endDate = [draft.startDate dateByAddingTimeInterval:startTime.duration];
        }
    }
    else if (day) {
        draft.allDay = YES;
        draft.startDate = [cal startOfDayForDate:day.date];
        if (day.duration >= 86400) {
            // "Oct 22–24": last day of the range.
            draft.endDate = [cal startOfDayForDate:[day.date dateByAddingTimeInterval:day.duration]];
        }
    }

    if (titleLine) {
        NSMutableArray *remove = [NSMutableArray new];
        for (NSString *span in @[daySpan ?: @"", startTimeSpan ?: @"", endTimeSpan ?: @""]) {
            if (span.length) [remove addObject:span];
        }
        // Only strip the location out of the title if the title
        // isn't the location line itself.
        if (locationLine && ![locationLine isEqualToString:titleLine]) {
            [remove addObject:CleanLocation(locationLine)];
        }
        draft.title = CleanTitle(titleLine, remove);
    }
    if (locationLine) draft.location = CleanLocation(locationLine);
    draft.url = link;
    return draft;
}

// Used without an API key, or when the request fails.
static EventDraft *HeuristicDraft(EventCandidates *c)
{
    NSString *startSpan = c.dateSpans.firstObject;
    NSString *titleLine = nil;
    for (NSString *line in c.lines) {
        if (![line isEqualToString:startSpan]) { titleLine = line; break; }
    }
    return AssembleDraft(c, titleLine, c.addressSpans.firstObject, c.links.firstObject, startSpan, startSpan, nil, startSpan != nil);
}

#pragma mark -
#pragma mark TypeSafe request

static NSDictionary *ChoiceQuestion(NSString *instructions, NSArray<NSString *> *options, NSString *noneDescription)
{
    NSMutableDictionary *criteria = [NSMutableDictionary new];
    for (NSString *option in options) criteria[option] = [NSNull null];
    criteria[kNone] = noneDescription;
    return @{@"type": @"choice", @"instructions": instructions, @"criteria": criteria};
}

static NSDictionary *Questions(EventCandidates *c)
{
    NSMutableDictionary *q = [NSMutableDictionary new];

    q[@"is_event"] = @{
        @"type": @"noul",
        @"instructions": @"Does `text` describe a specific event, meeting, appointment, reservation, deadline, or plan that someone could put on their calendar?",
        @"criteria": @{
            @"true": @"The text announces, invites to, confirms, or arranges something happening at a particular date or time.",
            @"false": @"The text is not about something scheduled, e.g. general information, an article, or code."
        }
    };

    if (c.dateSpans.count) {
        q[@"day"] = ChoiceQuestion(@"Which of these expressions from `text` names the day (date or weekday) the event happens on?", c.dateSpans, @"`text` doesn't name the day the event happens on.");
        q[@"start_time"] = ChoiceQuestion(@"Which of these expressions from `text` gives the time of day the event starts (e.g. \"7pm\", \"at 14:00\", \"show 8:00 PM\")? If there are several (e.g. doors and show), pick when the main event starts.", c.dateSpans, @"`text` gives no time of day for the event (e.g. only a date, or it lasts all day).");
        q[@"end_time"] = ChoiceQuestion(@"Which of these expressions from `text` gives the time of day the event ends?", c.dateSpans, @"`text` gives no separate end time for the event.");
    }

    if (c.lines.count) {
        q[@"title"] = ChoiceQuestion(@"Which of these lines from `text` best names the event, i.e. would make the best short title for it in a calendar? Prefer a line saying what the event is (e.g. a name, an activity, or who it's with) over a date, an address, or chatter.", c.lines, @"None of these lines names the event.");
    }

    NSMutableArray *places = [c.addressSpans mutableCopy];
    for (NSString *line in c.lines) AddUnique(places, line);
    if (places.count) {
        q[@"location"] = ChoiceQuestion(@"Which of these from `text` says where the event takes place (a venue, street address, room, or video call)?", places, @"`text` doesn't say where the event takes place.");
    }

    if (c.links.count) {
        q[@"url"] = ChoiceQuestion(@"Which of these links from `text` is for the event itself, e.g. its video call, tickets, booking, or event page?", c.links, @"None of these links is for the event.");
    }
    return q;
}

static NSString *APIKey(void)
{
    NSString *key = [[NSUserDefaults standardUserDefaults] stringForKey:kTypeSafeAPIKey];
    if (!key.length) key = NSProcessInfo.processInfo.environment[@"TYPESAFE_API_KEY"];
    return key.length ? key : nil;
}

static void AskTypeSafe(EventCandidates *c, void (^completion)(EventDraft *draft))
{
    NSString *apiKey = APIKey();
    if (!apiKey) {
        os_log(OS_LOG_DEFAULT, "EventExtractor: no TypeSafe API key; using heuristics");
        completion(HeuristicDraft(c));
        return;
    }

    NSDictionary *body = @{
        @"model": kTypeSafeModel,
        @"state": @{@"text": c.text},
        @"questions": Questions(c),
    };
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kTypeSafeEndpoint]];
    req.HTTPMethod = @"POST";
    req.timeoutInterval = 20;
    [req setValue:[@"Bearer " stringByAppendingString:apiKey] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    req.HTTPBody = [NSJSONSerialization dataWithJSONObject:body options:0 error:NULL];

    [[[NSURLSession sharedSession] dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
        NSDictionary *answers = [json isKindOfClass:[NSDictionary class]] ? json[@"answers"] : nil;
        if (error || status != 200 || ![answers isKindOfClass:[NSDictionary class]]) {
            os_log_error(OS_LOG_DEFAULT, "EventExtractor: TypeSafe request failed (%ld): %{public}@ %{public}@", (long)status, error, data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : @"");
            completion(HeuristicDraft(c));
            return;
        }
        BOOL recognized = Noul(answers, @"is_event", 0) >= kIsEventThreshold;
        completion(AssembleDraft(c, Pick(answers, @"title"), Pick(answers, @"location"), Pick(answers, @"url"), Pick(answers, @"day"), Pick(answers, @"start_time"), Pick(answers, @"end_time"), recognized));
    }] resume];
}

#pragma mark -
#pragma mark OCR

static NSString *RecognizeText(NSImage *image)
{
    CGImageRef cgImage = [image CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cgImage) return nil;
    VNRecognizeTextRequest *request = [VNRecognizeTextRequest new];
    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    NSError *error = nil;
    if (![handler performRequests:@[request] error:&error]) {
        os_log_error(OS_LOG_DEFAULT, "EventExtractor: OCR failed: %{public}@", error);
        return nil;
    }
    NSMutableArray *lines = [NSMutableArray new];
    for (VNRecognizedTextObservation *obs in request.results) {
        NSString *s = [obs topCandidates:1].firstObject.string;
        if (s.length) [lines addObject:s];
    }
    return [lines componentsJoinedByString:@"\n"];
}

#pragma mark -
#pragma mark Pasteboard

// A .textClipping file is a plist with the text under UTI-Data.
static NSString *TextFromClippingFile(NSURL *url)
{
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (!data) return nil;
    NSDictionary *plist = [NSPropertyListSerialization propertyListWithData:data options:0 format:NULL error:NULL];
    NSDictionary *utiData = [plist isKindOfClass:[NSDictionary class]] ? plist[@"UTI-Data"] : nil;
    if (![utiData isKindOfClass:[NSDictionary class]]) return nil;
    for (NSString *type in @[@"public.utf8-plain-text", @"public.plain-text"]) {
        id value = utiData[type];
        if ([value isKindOfClass:[NSString class]]) return value;
        if ([value isKindOfClass:[NSData class]]) return [[NSString alloc] initWithData:value encoding:NSUTF8StringEncoding];
    }
    return nil;
}

static NSString *TextFromFile(NSURL *url)
{
    if ([url.pathExtension.lowercaseString isEqualToString:@"textclipping"]) {
        return TextFromClippingFile(url);
    }
    UTType *type = [UTType typeWithFilenameExtension:url.pathExtension];
    if (type && [type conformsToType:UTTypePlainText]) {
        return [NSString stringWithContentsOfURL:url usedEncoding:NULL error:NULL];
    }
    return nil;
}

@implementation EventExtractor

+ (NSArray<NSPasteboardType> *)readablePasteboardTypes
{
    NSMutableArray *types = [[NSImage imageTypes] mutableCopy];
    [types addObjectsFromArray:@[NSPasteboardTypeFileURL, NSPasteboardTypeString]];
    return types;
}

+ (BOOL)canReadPasteboard:(NSPasteboard *)pboard
{
    if ([NSImage canInitWithPasteboard:pboard]) return YES;
    if ([pboard canReadObjectForClasses:@[[NSString class]] options:nil]) return YES;
    // A file URL that isn't an image: only text files are readable,
    // but checking that means reading it. Accept and check on drop.
    return [pboard canReadObjectForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
}

+ (BOOL)extractFromPasteboard:(NSPasteboard *)pboard completion:(EventExtractorCompletion)completion
{
    // Text files and clippings dragged from Finder.
    NSArray<NSURL *> *urls = [pboard readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
    for (NSURL *url in urls) {
        NSString *text = TextFromFile(url);
        if (text.length) {
            [self extractFromText:text completion:completion];
            return YES;
        }
    }
    // Images (screenshots, image files, images from a browser).
    // Prefer an image to text: a browser image drag also carries
    // its URL as a string.
    NSImage *image = [[pboard readObjectsForClasses:@[[NSImage class]] options:nil] firstObject];
    if (image) {
        [self extractFromImage:image completion:completion];
        return YES;
    }
    NSString *text = [[pboard readObjectsForClasses:@[[NSString class]] options:nil] firstObject];
    if (text.length) {
        [self extractFromText:text completion:completion];
        return YES;
    }
    return NO;
}

+ (void)extractFromImage:(NSImage *)image completion:(EventExtractorCompletion)completion
{
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSString *text = RecognizeText(image);
        [self extractFromText:text ?: @"" completion:completion];
    });
}

+ (void)extractFromText:(NSString *)text completion:(EventExtractorCompletion)completion
{
    if (text.length > kMaxTextLength) text = [text substringToIndex:kMaxTextLength];
    void (^finish)(EventDraft *) = ^(EventDraft *draft) {
        os_log(OS_LOG_DEFAULT, "EventExtractor: %{public}@", draft);
        dispatch_async(dispatch_get_main_queue(), ^{ completion(draft); });
    };
    NSString *trimmed = [text stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (!trimmed.length) {
        EventDraft *draft = [EventDraft new];
        draft.sourceText = text;
        finish(draft);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        AskTypeSafe(FindCandidates(trimmed), finish);
    });
}

@end
