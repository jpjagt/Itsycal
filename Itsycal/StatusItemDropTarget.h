//
//  StatusItemDropTarget.h
//  Itsycal
//
//  Lets the user drop images, text, and text clippings on the
//  menubar icon. A transparent overlay filling the status item
//  button accepts the drags; clicks are forwarded to the button
//  underneath so it still toggles the Itsycal window.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface StatusItemDropTarget : NSView

// Adds the overlay to the status item's button. dropHandler is
// called with the dragging pasteboard when the user drops; it
// returns YES if the drop was accepted.
- (instancetype)initWithStatusItem:(NSStatusItem *)statusItem dropHandler:(BOOL (^)(NSPasteboard *pboard))dropHandler;

@end

NS_ASSUME_NONNULL_END
