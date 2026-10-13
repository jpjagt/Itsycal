//
//  EventViewController.h
//  Itsycal
//
//  Created by Sanjay Madan on 2/25/15.
//  Copyright (c) 2015 mowglii.com. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class EventCenter, EventDraft;

@interface EventViewController : NSViewController <NSTextFieldDelegate, NSTextViewDelegate>

@property (nonatomic, weak) EventCenter *ec;
@property (nonatomic, weak) NSPopover *enclosingPopover;
@property (nonatomic, weak) NSCalendar *cal;
@property (nonatomic) NSDate *calSelectedDate;

// Show that an event is being read from dropped or pasted
// content, then prefill the form with what was found.
- (void)showReadingDraft;
- (void)applyDraft:(EventDraft *)draft;

@end
