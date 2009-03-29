//
//  TFPerformanceMonitorController.h
//  Touché
//
//  Created by Georg Kaindl on 28/3/09.
//
//  Copyright (C) 2009 Georg Kaindl
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

#import "TFPerformanceTimer.h"


@interface TFPerformanceMonitorController : NSWindowController {
	IBOutlet NSTableView*		_measurementsTableView;
	IBOutlet NSTableView*		_taskTableView;
	
	TFPerformanceMeasureID		measureID;
	
	NSDictionary*				_measurements;
	NSTimer*					_updateTimer;
	NSLock*						_updateLock;
	
	double						_cpuPercent;
	unsigned int				_realMemBytes, _virtualMemBytes;
}

@property (nonatomic, assign) TFPerformanceMeasureID measureID;

- (id)init;
- (void)dealloc;

- (void)showWindow:(id)sender;

#pragma mark -
#pragma mark NSTableDataSource informal protocol

- (NSInteger)numberOfRowsInTableView:(NSTableView *)aTableView;
- (id)tableView:(NSTableView *)aTableView objectValueForTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex;

#pragma mark -
#pragma mark NSTableView delegate

- (BOOL)tableView:(NSTableView *)aTableView shouldSelectRow:(NSInteger)rowIndex;

#pragma mark -
#pragma mark NSWindow delegate

- (void)windowWillClose:(NSNotification *)notification;

@end
