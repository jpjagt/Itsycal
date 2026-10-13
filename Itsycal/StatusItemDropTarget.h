//
//  StatusItemDropTarget.h
//  Itsycal
//
//  Lets the user drop images, text, and text clippings on the
//  menubar icon. It becomes the delegate of the status item's
//  window, which forwards NSDraggingDestination messages to it.
//

#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface StatusItemDropTarget : NSObject <NSWindowDelegate>

// Called with the dragging pasteboard when the user drops.
// Return YES if the drop was accepted.
- (instancetype)initWithStatusItem:(NSStatusItem *)statusItem dropHandler:(BOOL (^)(NSPasteboard *pboard))dropHandler;

@end

NS_ASSUME_NONNULL_END
