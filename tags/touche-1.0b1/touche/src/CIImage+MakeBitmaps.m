//
//  CIImage+MakeBitmaps.m
//  Touché
//
//  Created by Georg Kaindl on 15/12/07.
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
//  Based on code by: http://www.geekspiff.com/unlinkedCrap/ciImageToBitmap.html

#import "CIImage+MakeBitmaps.h"

@interface CIImage (MakeBitmapsExtensionsPrivate)
- (void*)_createBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
				   workingColorSpace:(CGColorSpaceRef)workingColorSpace
						  bitmapInfo:(CGBitmapInfo)bitmapInfo
					   bytesPerPixel:(NSUInteger)bytesPerPixel
							rowBytes:(size_t *)rowBytes
							  buffer:(void*)buffer
						 renderOnCPU:(BOOL)renderOnCPU;
@end

@implementation CIImage (MakeBitmapsExtensions)

+ (CGColorSpaceRef)screenColorSpace
{
	CMProfileRef systemProfile = NULL;
	OSStatus status = CMGetSystemProfile(&systemProfile);
	
	if (noErr != status)
		return nil;
		
	CGColorSpaceRef colorSpace = CGColorSpaceCreateWithPlatformColorSpace(systemProfile);
	
	CMCloseProfile(systemProfile);
	
	return colorSpace;
}

- (size_t)optimalRowBytesForWidth:(size_t)width bytesPerPixel:(size_t)bytesPerPixel
{
	size_t rowBytes = width * bytesPerPixel;

	// Widen rowBytes out to a integer multiple of 16 bytes
	rowBytes = (rowBytes + 15) & ~15;

	// Make sure we are not an even power of 2 wide. 
	// Will loop a few times for rowBytes <= 16.
	while(0 == (rowBytes & (rowBytes - 1)))
		rowBytes += 16;

	return rowBytes;
}

- (UInt32*)createPremultipliedRGBA8888BitmapWithColorSpace:(CGColorSpaceRef)colorSpace
												  rowBytes:(size_t *)rowBytes
													buffer:(void*)buffer
{
	// per default, we render on the CPU, since getting the pixel data back from the GPU is pretty expensive
	return [self createPremultipliedRGBA8888BitmapWithColorSpace:colorSpace
														rowBytes:rowBytes
														  buffer:buffer
													 renderOnCPU:YES];
}

- (UInt32*)createPremultipliedRGBA8888BitmapWithColorSpace:(CGColorSpaceRef)colorSpace
												  rowBytes:(size_t *)rowBytes
													buffer:(void*)buffer
											   renderOnCPU:(BOOL)renderOnCPU
{
	return [self createPremultipliedRGBA8888BitmapWithColorSpace:colorSpace
											   workingColorSpace:nil
														rowBytes:rowBytes
														  buffer:buffer
													 renderOnCPU:renderOnCPU];
}

- (UInt32*)createPremultipliedRGBA8888BitmapWithColorSpace:(CGColorSpaceRef)colorSpace
										 workingColorSpace:(CGColorSpaceRef)workingColorSpace
												  rowBytes:(size_t *)rowBytes
													buffer:(void*)buffer
											   renderOnCPU:(BOOL)renderOnCPU
{       		
	BOOL shouldReleaseColorSpace = NO;
	
	if (nil == colorSpace) {
		colorSpace = [[self class] screenColorSpace];
		shouldReleaseColorSpace = YES;
	}
	
	CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Host;

	UInt32* rv = (UInt32*)[self _createBitmapWithColorSpace:colorSpace
										  workingColorSpace:workingColorSpace
												 bitmapInfo:bitmapInfo
											  bytesPerPixel:4
												   rowBytes:rowBytes
													 buffer:buffer
												renderOnCPU:renderOnCPU];
	
	if (shouldReleaseColorSpace)
		CGColorSpaceRelease(colorSpace);
	
	return rv;
}

- (float*)createPremultipliedRGBAFFFFBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
												  rowBytes:(size_t *)rowBytes
													buffer:(void*)buffer
{
	// per default, we render on the CPU, since getting the pixel data back from the GPU is pretty expensive
	return [self createPremultipliedRGBAFFFFBitmapWithColorSpace:colorSpace
														rowBytes:rowBytes
														  buffer:buffer
													 renderOnCPU:YES];
}

- (float*)createPremultipliedRGBAFFFFBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
												  rowBytes:(size_t *)rowBytes
													buffer:(void*)buffer
											   renderOnCPU:(BOOL)renderOnCPU
{
	return [self createPremultipliedRGBAFFFFBitmapWithColorSpace:colorSpace
											   workingColorSpace:nil
														rowBytes:rowBytes
														  buffer:buffer
													 renderOnCPU:renderOnCPU];
}

- (float*)createPremultipliedRGBAFFFFBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
										 workingColorSpace:(CGColorSpaceRef)workingColorSpace
												  rowBytes:(size_t *)rowBytes
													buffer:(void*)buffer
											   renderOnCPU:(BOOL)renderOnCPU
{       		
	BOOL shouldReleaseColorSpace = NO;
	
	if (nil == colorSpace) {
		colorSpace = [[self class] screenColorSpace];
		shouldReleaseColorSpace = YES;
	}
	
	CGBitmapInfo bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Host | kCGBitmapFloatComponents;
	
	float* rv = (float*)[self _createBitmapWithColorSpace:colorSpace
										workingColorSpace:workingColorSpace
											   bitmapInfo:bitmapInfo
											bytesPerPixel:16
												 rowBytes:rowBytes
												   buffer:buffer
											  renderOnCPU:renderOnCPU];
	
	if (shouldReleaseColorSpace)
		CGColorSpaceRelease(colorSpace);
	
	return rv;
}

- (UInt8*)createGrayscaleBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
									 rowBytes:(size_t *)rowBytes
									   buffer:(void*)buffer
{
	// per default, we render on the CPU, since getting the pixel data back from the GPU is pretty expensive
	return [self createGrayscaleBitmapWithColorSpace:colorSpace
											rowBytes:rowBytes
											  buffer:buffer
										 renderOnCPU:YES];
}

- (UInt8*)createGrayscaleBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
									 rowBytes:(size_t *)rowBytes
									   buffer:(void*)buffer
								  renderOnCPU:(BOOL)renderOnCPU
{
	return [self createGrayscaleBitmapWithColorSpace:colorSpace
								   workingColorSpace:nil
											rowBytes:rowBytes
											  buffer:buffer
										 renderOnCPU:renderOnCPU];
}

- (UInt8*)createGrayscaleBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
							workingColorSpace:(CGColorSpaceRef)workingColorSpace
									 rowBytes:(size_t *)rowBytes
									   buffer:(void*)buffer
								  renderOnCPU:(BOOL)renderOnCPU
{
	BOOL shouldReleaseColorSpace = NO;
	
	if (nil == colorSpace) {
		colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
		shouldReleaseColorSpace = YES;
	}
	
	CGBitmapInfo bitmapInfo = kCGImageAlphaNone;
	
	UInt8* rv = (UInt8*)[self _createBitmapWithColorSpace:colorSpace
										workingColorSpace:workingColorSpace
											   bitmapInfo:bitmapInfo
											bytesPerPixel:1
												 rowBytes:rowBytes
												   buffer:buffer
											  renderOnCPU:renderOnCPU];
	
	if (shouldReleaseColorSpace)
		CGColorSpaceRelease(colorSpace);
	
	return rv;
}

- (void*)_createBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
				   workingColorSpace:(CGColorSpaceRef)workingColorSpace
						  bitmapInfo:(CGBitmapInfo)bitmapInfo
					   bytesPerPixel:(NSUInteger)bytesPerPixel
							rowBytes:(size_t *)rowBytes
							  buffer:(void*)buffer
						 renderOnCPU:(BOOL)renderOnCPU
{
	BOOL shouldReleaseWorkingColorSpace = NO;
	
	if (nil == workingColorSpace) {
		workingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		shouldReleaseWorkingColorSpace = YES;
	}

	CGRect extent = [self extent];
	CGRect zeroRect = {CGPointZero, extent.size};
	
	if (CGRectIsInfinite(extent) || colorSpace == nil)
		return NULL;
	
	size_t destWidth = (size_t)extent.size.width;
	size_t destHeight = (size_t)extent.size.height;
	
	CGContextRef cgContext = NULL;
	CIContext* ciContext = nil;
	size_t bitsPerComponent = (bitmapInfo & kCGBitmapFloatComponents) ? 32 : 8;
	size_t bytesPerRow;
	
	if (NULL != rowBytes && *rowBytes > 0)
		bytesPerRow = *rowBytes;
	else
		bytesPerRow = [self optimalRowBytesForWidth:destWidth bytesPerPixel:bytesPerPixel];
	
	void *bitmapData;
	if (NULL != buffer)
		bitmapData = buffer;
	else
		bitmapData = malloc(bytesPerRow*destHeight); /* caller has to free the memory if it's no longer needed! */
	
	if (NULL == bitmapData)
		return NULL;
	
	cgContext = CGBitmapContextCreate(bitmapData, destWidth, destHeight, bitsPerComponent, bytesPerRow, colorSpace, bitmapInfo);
	if (nil == cgContext)
		return NULL;
	
	NSDictionary *options = [NSDictionary dictionaryWithObjectsAndKeys: 
							 (id)colorSpace,     kCIContextOutputColorSpace, 
							 (id)workingColorSpace, kCIContextWorkingColorSpace,
							 [NSNumber numberWithBool:renderOnCPU], kCIContextUseSoftwareRenderer,
							 nil];
	
	ciContext = [CIContext contextWithCGContext:cgContext options:options];
	
	if (nil == ciContext)
		return NULL;
	
	CGContextClearRect(cgContext, zeroRect);
	[ciContext drawImage:self atPoint: CGPointZero fromRect:extent];
	CGContextFlush(cgContext);
	
	if (NULL != rowBytes)
		*rowBytes = CGBitmapContextGetBytesPerRow(cgContext);
	
	CGContextRelease(cgContext);
	
	if (shouldReleaseWorkingColorSpace)
		CGColorSpaceRelease(workingColorSpace);
	
	return bitmapData;
}

@end