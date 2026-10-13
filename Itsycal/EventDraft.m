//
//  EventDraft.m
//  Itsycal
//

#import "EventDraft.h"

@implementation EventDraft

- (NSString *)description
{
    return [NSString stringWithFormat:@"<EventDraft recognized=%d title=%@ location=%@ url=%@ start=%@ end=%@ allDay=%d>",
            self.recognized, self.title, self.location, self.url, self.startDate, self.endDate, self.allDay];
}

@end
