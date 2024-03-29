//
//	CFRunLoop replacement stuff
//
//  Created by Georg Kaindl on 25/2/09.
//
//  Copyright (C) 2009 Georg Kaindl
//
//  This file is part of Touchsmart TUIO.
//
//  Touchsmart TUIO is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as
//  published by the Free Software Foundation, either version 3 of
//  the License, or (at your option) any later version.
//
//  Touchsmart TUIO is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Lesser General Public License for more details.
//
//  You should have received a copy of the GNU Lesser General Public
//  License along with Touchsmart TUIO. If not, see <http://www.gnu.org/licenses/>.
//

#import <Cocoa/Cocoa.h>

#import <AppKit/Win32EventInputSource.h>
#import <Foundation/NSHandleMonitor_win32.h>

typedef NSInputSource NSRunLoopSource;

void CFRunLoopAddSource(CFRunLoopRef self, CFRunLoopSourceRef source, CFStringRef mode)
{
	// unfortunately, cocotron's implementation of NSRunLoop is buggy with multiple threads,
	// so we always need to schedule on the main runloop.
	[[NSRunLoop mainRunLoop] addInputSource:(NSInputSource*)source forMode:NSDefaultRunLoopMode];
	
	// note: whenever we're calling this, it's to add this only one source to a threads
	// runloop. Since this doesn't work, running the runloop would return immediately, causing
	// the thread's "while" loop to consume a lot of CPU. Therefore, we "infinite loop" with a
	// sleep in between here, just to check for our thread being canceled, and return only
	// then. It's another ugly work-around that cocotron needs, unfortunately.
	while (![[NSThread currentThread] isCancelled])
		[NSThread sleepForTimeInterval:1.0];
}

Boolean CFRunLoopSourceIsValid(CFRunLoopSourceRef self)
{
	return [(NSInputSource*)self isValid];
}

void CFRunLoopSourceInvalidate(CFRunLoopSourceRef self)
{
	[(NSInputSource*)self invalidate];
	
	// again, we use the main runloop (see CFRunLoopAddSource)
	[[NSRunLoop mainRunLoop] removeInputSource:(NSInputSource*)self forMode:NSDefaultRunLoopMode];
}