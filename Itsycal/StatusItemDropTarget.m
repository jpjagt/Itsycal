//
//  StatusItemDropTarget.m
//  Itsycal
//

#import "StatusItemDropTarget.h"
#import "EventExtractor.h"

@implementation StatusItemDropTarget
{
    BOOL (^_dropHandler)(NSPasteboard *);
}

- (instancetype)initWithStatusItem:(NSStatusItem *)statusItem dropHandler:(BOOL (^)(NSPasteboard *))dropHandler
{
    NSStatusBarButton *button = statusItem.button;
    self = [super initWithFrame:button.bounds];
    if (self) {
        _dropHandler = [dropHandler copy];
        self.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self registerForDraggedTypes:[EventExtractor readablePasteboardTypes]];
        [button addSubview:self];
    }
    return self;
}

// Let the status item button handle clicks.
- (void)mouseDown:(NSEvent *)event
{
    [self.superview mouseDown:event];
}

- (void)rightMouseDown:(NSEvent *)event
{
    [self.superview rightMouseDown:event];
}

- (void)setHovering:(BOOL)hovering
{
    // The status item doesn't highlight (see -createStatusItem),
    // so dim it to show it will accept the drop.
    self.superview.alphaValue = hovering ? 0.5 : 1;
}

- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender
{
    if (![EventExtractor canReadPasteboard:sender.draggingPasteboard]) {
        return NSDragOperationNone;
    }
    [self setHovering:YES];
    return NSDragOperationCopy;
}

- (void)draggingExited:(id<NSDraggingInfo>)sender
{
    [self setHovering:NO];
}

- (void)draggingEnded:(id<NSDraggingInfo>)sender
{
    [self setHovering:NO];
}

- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender
{
    [self setHovering:NO];
    if (_dropHandler(sender.draggingPasteboard)) return YES;
    NSBeep();
    return NO;
}

@end
