//
//  TFBlobTrackingView.h
//  Touché
//
//  Created by Georg Kaindl on 19/12/07.
//
//  Copyright (C) 2007 Georg Kaindl
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

#import <Cocoa/Cocoa.h>

#import "TFTrackingPipelineView.h"

@interface TFBlobTrackingView : TFTrackingPipelineView {
	NSArray*		blobs;
	BOOL			_delegateHasBlobsForTimestamp;
}

@property (retain) NSArray* blobs;

- (void)setDelegate:(id)newDelegate;

@end

@interface NSObject (TFBlobTrackingViewDelegate)
- (NSArray*)blobTrackingView:(TFBlobTrackingView*)trackingView cameraBlobsForTimestamp:(const CVTimeStamp*)timeStamp;
@end