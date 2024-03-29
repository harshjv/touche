//
//  TFTouchTestController.h
//  Touché
//
//  Created by Georg Kaindl on 26/4/08.
//
//  Copyright (C) 2008 Georg Kaindl
//
//  This file is part of Touché.
//
//  Touché is free software: you can redistribute it and/or modify
//  it under the terms of the GNU Lesser General Public License as
//  published by the Free Software Foundation, either version 3 of
//  the License, or (at your option) any later version.
//
//  Touché is distributed in the hope that it will be useful,
//  but WITHOUT ANY WARRANTY; without even the implied warranty of
//  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//  GNU Lesser General Public License for more details.
//
//  You should have received a copy of the GNU Lesser General Public
//  License along with Touché. If not, see <http://www.gnu.org/licenses/>.
//
//

#import <Cocoa/Cocoa.h>

#import "TFFullscreenController.h"

@class TFDOTrackingClient;
@class TFTouchView;

@interface TFTouchTestController : TFFullscreenController {
	BOOL						isRunning;
	id							delegate;

	IBOutlet TFTouchView*		_touchView;
	TFDOTrackingClient*			_trackingClient;
	NSMutableArray*				_freeColors;
	NSMutableDictionary*		_touchesAndColors;
}

@property (readonly) BOOL isRunning;
@property (nonatomic, assign) id delegate;

- (void)startTest;

@end

@interface NSObject (TFTouchTestControllerDelegate)
- (void)touchTestEndedByUser:(TFTouchTestController*)controller;
- (void)touchTestController:(TFTouchTestController*)controller failedWithError:(NSError*)error;
@end