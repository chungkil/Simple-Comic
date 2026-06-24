/*
Copyright (c) 2006-2009 Dancing Tortoise Software

	Permission is hereby granted, free of charge, to any person
	obtaining a copy of this software and associated documentation
	files (the "Software"), to deal in the Software without
	restriction, including without limitation the rights to use,
	copy, modify, merge, publish, distribute, sublicense, and/or
	sell copies of the Software, and to permit persons to whom the
	Software is furnished to do so, subject to the following
	conditions:

	The above copyright notice and this permission notice shall be
	included in all copies or substantial portions of the Software.

	THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
	EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
	OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
	NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
	HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
	WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
	FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
	OTHER DEALINGS IN THE SOFTWARE.

	Simple Comic
	main.m
 */

#import <Cocoa/Cocoa.h>
#import <Carbon/Carbon.h>

/*  Translate a key event's physical keyCode to the character it would produce on
    the current ASCII-capable keyboard layout (i.e. the Latin letter under the
    key), ignoring modifiers.  Returns nil if it can't be determined. */
static NSString * SCASCIICharacterForKeyEvent(NSEvent * event)
{
    TISInputSourceRef source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource();
    if(!source)
    {
        return nil;
    }

    NSString * result = nil;
    CFDataRef layoutData = (CFDataRef)TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData);
    if(layoutData)
    {
        const UCKeyboardLayout * layout = (const UCKeyboardLayout *)CFDataGetBytePtr(layoutData);
        UInt32 deadKeyState = 0;
        UniChar buffer[4];
        UniCharCount actualLength = 0;
        OSStatus status = UCKeyTranslate(layout,
                                         [event keyCode],
                                         kUCKeyActionDown,
                                         0,                       /* no modifiers: base letter */
                                         LMGetKbdType(),
                                         kUCKeyTranslateNoDeadKeysBit,
                                         &deadKeyState,
                                         sizeof(buffer) / sizeof(buffer[0]),
                                         &actualLength,
                                         buffer);
        if(status == noErr && actualLength > 0)
        {
            result = [NSString stringWithCharacters: buffer length: actualLength];
        }
    }

    CFRelease(source);
    return result;
}


/*  Simple Comic's menu shortcuts (⌘C Capture Page, ⌘Q Quit, ⌘O Open, …) are
    plain Latin-letter key equivalents.  Under a non-Latin input source such as
    Hangul, -[NSEvent charactersIgnoringModifiers] returns the composed jamo
    (e.g. "ㅊ" for the C key), so AppKit's menu matching never matches the Latin
    equivalent and the shortcut silently does nothing (the event falls through to
    -keyDown:).  We re-run main-menu key-equivalent matching with the key's Latin
    character so the shortcuts work regardless of the active input source. */
@interface SCApplication : NSApplication @end

@implementation SCApplication

- (void)sendEvent:(NSEvent *)event
{
    if([event type] == NSEventTypeKeyDown && ([event modifierFlags] & NSEventModifierFlagCommand))
    {
        NSString * latin = SCASCIICharacterForKeyEvent(event);
        if([latin length] > 0 && ![latin isEqualToString: [event charactersIgnoringModifiers]])
        {
            NSEvent * latinEvent = [NSEvent keyEventWithType: NSEventTypeKeyDown
                                                    location: [event locationInWindow]
                                               modifierFlags: [event modifierFlags]
                                                   timestamp: [event timestamp]
                                                windowNumber: [event windowNumber]
                                                     context: nil
                                                  characters: latin
                                 charactersIgnoringModifiers: latin
                                                   isARepeat: [event isARepeat]
                                                     keyCode: [event keyCode]];
            if([[self mainMenu] performKeyEquivalent: latinEvent])
            {
                return;
            }
        }
    }

    [super sendEvent: event];
}

@end


int main(int argc, char *argv[])
{
    /* Install SCApplication as the shared app instance before NSApplicationMain
       so it is used instead of the Info.plist principal class. */
    [SCApplication sharedApplication];
    return NSApplicationMain(argc,  (const char **) argv);
}
