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

#import <Accelerate/Accelerate.h>
#import <mach/mach.h>
#import <mach/mach_time.h>

typedef enum {
	CIImageInternalOutputPixelFormatARGB8,
	CIImageInternalOutputPixelFormatRGBA8,
	CIImageInternalOutputPixelFormatRGBAF,
	CIImageInternalOutputPixelFormatRGB8,
	CIImageInternalOutputPixelFormatGray8
} CIImageInternalOutputPixelFormat;

typedef enum {
	CIImageInternalBitmapCreationMethodBitmapContextBackedCIContext = 0,
	CIImageInternalBitmapCreationMethodCIContextRender,
	CIImageInternalBitmapCreationMethodUndetermined
} CIImageInternalBitmapCreationMethod;

#define CIImageInternalBitmapCreationMethodMin	(CIImageInternalBitmapCreationMethodBitmapContextBackedCIContext)
#define	CIImageInternalBitmapCreationMethodMax	(CIImageInternalBitmapCreationMethodCIContextRender)
#define CIImageInternalBitmapCreationMethodCnt	(CIImageInternalBitmapCreationMethodMax - CIImageInternalBitmapCreationMethodMin + 1)
#define CIImageInternalBitmapCreationMethodDefault	(CIImageInternalBitmapCreationMethodCIContextRender)

#define DYNAMIC_METHOD_SELECTION_SAMPLE_COUNT	(5)

#define MAX_INTERNAL_DATA_SCRATCH_SPACE		(4)

typedef struct CIImageBitmapsInternalData {
	size_t								width, height;

	CGColorSpaceRef						colorSpace, ciOutputColorSpace, ciWorkingColorSpace;
	CGContextRef						cgContext;
	CIContext*							ciContext;
	BOOL								renderOnCPU;
	
	CIImageInternalOutputPixelFormat	internalOutputPixelFormat;
	CGBitmapInfo						bitmapInfo;
	NSUInteger							bytesPerPixel;
	size_t								rowBytes;
	void*								outputBuffer;
	
	CIImageInternalBitmapCreationMethod	chosenCreationMethod;

	void* scratchSpace[MAX_INTERNAL_DATA_SCRATCH_SPACE];
	int scratchRowBytes[MAX_INTERNAL_DATA_SCRATCH_SPACE];
	
	uint64_t measuredNanosPerMethod[CIImageInternalBitmapCreationMethodCnt];
	unsigned measurementsPerMethodCount[CIImageInternalBitmapCreationMethodCnt];
} CIImageBitmapsInternalData;

#define RELEASE_CF_MEMBER(c)	do { if (NULL != (c)) { CFRelease((c)); (c) = NULL; } } while (0)

// quick way to make a CIImageBitmapData struct (like NSMakeRange(), for example)
inline CIImageBitmapData _CIImagePrivateMakeBitmapData(void* data,
													   size_t width,
													   size_t height,
													   size_t rowBytes);

// common initialization stuff for all bitmap creation context types
CIImageBitmapsInternalData* _CIImagePrivateInitializeBitmapCreationContext(CIImage* image);

// common initialization stuff for all bitmap creation context types
void* _CIImagePrivateFinalizeBitmapCreationContext(CIImageBitmapsInternalData* context,
												   CIImage* image,
												   BOOL renderOnCPU);

// returns the optimal rowBytes for a pixel buffer with respect to memory alignment
size_t _CIImagePrivateOptimalRowBytesForWidthAndBytesPerPixel(size_t width, size_t bytesPerPixel);

// returns non-zero on success, zero on error
int _CIImagePrivateConvertInternalPixelFormats(void* dest,
											   int destRowBytes,
											   CIImageBitmapsInternalData* internalData,
											   int width,
											   int height,
											   CIImageInternalOutputPixelFormat destFormat,
											   CIFormat srcFormat);

// get the amount of nanoseconds since the system was started (used to determine the fastest
// rendering method dynamically)
uint64_t _CIImagePrivateGetCurrentNanoseconds();

@interface CIImage (MakeBitmapsExtensionsPrivate)
- (void*)_createBitmapWithColorSpace:(CGColorSpaceRef)colorSpace
				  ciOutputColorSpace:(CGColorSpaceRef)ciOutputColorSpace
				 ciWorkingColorSpace:(CGColorSpaceRef)ciWorkingColorSpace
			  finalOutputPixelFormat:(CIImageInternalOutputPixelFormat)foPixelFormat
						  bitmapInfo:(CGBitmapInfo)bitmapInfo
					   bytesPerPixel:(NSUInteger)bytesPerPixel
							rowBytes:(size_t*)rowBytes
							  buffer:(void*)buffer
					cgContextPointer:(CGContextRef*)cgContextPointer
					ciContextPointer:(CIContext**)ciContextPointer
						 renderOnCPU:(BOOL)renderOnCPU
						internalData:(void**)internalData;
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
	
	return (CGColorSpaceRef)[(id)colorSpace autorelease];
}

- (CIImageBitmapData)bitmapDataWithBitmapCreationContext:(void*)pContext
{
	uint64_t beforeTime;
	BOOL measurePerformance = NO;
	CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
	CIImageInternalBitmapCreationMethod method = context->chosenCreationMethod;
	CIImageBitmapData bitmapData = _CIImagePrivateMakeBitmapData(NULL, 0, 0, 0);
	CGRect extent = [self extent];
	
	if (NULL == context || CGRectIsInfinite(extent))
		goto errorReturn;
	
	if (CIImageInternalBitmapCreationMethodUndetermined == method) {
		measurePerformance = YES;
	
		uint64_t minNanos = UINT64_MAX;
		int minIndex = CIImageInternalBitmapCreationMethodMin;
		int i = CIImageInternalBitmapCreationMethodMin;
		for (i; i<=CIImageInternalBitmapCreationMethodMax; i++)
			if (context->measurementsPerMethodCount[i] < DYNAMIC_METHOD_SELECTION_SAMPLE_COUNT) {
				method = i;
				goto methodDetermined;
			} else if (context->measuredNanosPerMethod[i] < minNanos) {
				minNanos = context->measuredNanosPerMethod[i];
				minIndex = i;
			}
		
		// if we're here, we have enough samples for all rendering methods. now determine the fastest one.
		context->chosenCreationMethod = minIndex;
		method = minIndex;
	}
	
methodDetermined:
	
	if (measurePerformance)
		beforeTime = _CIImagePrivateGetCurrentNanoseconds(); 
	
	switch (method) {
		case CIImageInternalBitmapCreationMethodBitmapContextBackedCIContext: {
			CGContextSaveGState(context->cgContext);
			[(context->ciContext) drawImage:self
									atPoint:CGPointZero
								   fromRect:extent];
			CGContextFlush(context->cgContext);
			CGContextRestoreGState(context->cgContext);
			
			context->rowBytes = CGBitmapContextGetBytesPerRow(context->cgContext);
			
			break;
		}
		
		case CIImageInternalBitmapCreationMethodCIContextRender: {
			CIFormat renderFormat = kCIFormatRGBAf;
			int renderRowBytes = context->rowBytes;
			void* renderBuffer = context->outputBuffer;
			
			switch(context->internalOutputPixelFormat) {
				case CIImageInternalOutputPixelFormatRGB8:
					renderFormat = kCIFormatARGB8;
					renderRowBytes = context->scratchRowBytes[0];
					renderBuffer = context->scratchSpace[0];
					break;
				case CIImageInternalOutputPixelFormatGray8:
					renderFormat = kCIFormatARGB8;
					renderRowBytes = context->scratchRowBytes[0];
					renderBuffer = context->scratchSpace[0];
					break;
				case CIImageInternalOutputPixelFormatARGB8:
					renderFormat = kCIFormatARGB8;
					renderRowBytes = context->rowBytes;
					renderBuffer = context->outputBuffer;
					break;
				case CIImageInternalOutputPixelFormatRGBA8:
					renderFormat = kCIFormatARGB8;
					renderRowBytes = context->scratchRowBytes[0];
					renderBuffer = context->scratchSpace[0];
					break;
				case CIImageInternalOutputPixelFormatRGBAF:
					renderFormat = kCIFormatRGBAf;
					renderRowBytes = context->rowBytes;
					renderBuffer = context->outputBuffer;
					break;
				default:
					break;
			}
			
			[(context->ciContext) render:self
								toBitmap:renderBuffer
								rowBytes:renderRowBytes
								  bounds:extent
								  format:renderFormat
							  colorSpace:nil];
			
			switch (context->internalOutputPixelFormat) {
				case CIImageInternalOutputPixelFormatGray8:
					_CIImagePrivateConvertInternalPixelFormats(context->outputBuffer,
															   context->rowBytes,
															   context,
															   context->width,
															   context->height,
															   CIImageInternalOutputPixelFormatGray8,
															   kCIFormatARGB8);
					break;
				case CIImageInternalOutputPixelFormatRGBA8:
					_CIImagePrivateConvertInternalPixelFormats(context->outputBuffer,
															   context->rowBytes,
															   context,
															   context->width,
															   context->height,
															   CIImageInternalOutputPixelFormatRGBA8,
															   kCIFormatARGB8);
					break;
				case CIImageInternalOutputPixelFormatRGB8:
					_CIImagePrivateConvertInternalPixelFormats(context->outputBuffer,
															   context->rowBytes,
															   context,
															   context->width,
															   context->height,
															   CIImageInternalOutputPixelFormatRGB8,
															   kCIFormatARGB8);
					break;
				default:
					break;
			}
				
			break;
		}
		
		default:
			goto errorReturn;
			break;
	}
	
	if (measurePerformance) {
		uint64_t time = _CIImagePrivateGetCurrentNanoseconds() - beforeTime;
		context->measuredNanosPerMethod[method] = (context->measuredNanosPerMethod[method] >> 1) + (time >> 1);
		context->measurementsPerMethodCount[method] += 1;
	}
	
	bitmapData = _CIImagePrivateMakeBitmapData(context->outputBuffer,
											   context->width,
											   context->height,
											   context->rowBytes);
	
errorReturn:
	return bitmapData;
}

@end

void* CIImageBitmapsCreateContextForPremultipliedARGB8(CIImage* image, BOOL renderOnCPU)
{
	CIImageBitmapsInternalData* context =  _CIImagePrivateInitializeBitmapCreationContext(image);
	
	if (NULL != context) {
		context->colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		context->internalOutputPixelFormat = CIImageInternalOutputPixelFormatARGB8;
		context->bitmapInfo = kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Host;
		context->bytesPerPixel = 4;
	}
	
	return _CIImagePrivateFinalizeBitmapCreationContext(context, image, renderOnCPU);
}

void* CIImageBitmapsCreateContextForPremultipliedRGBA8(CIImage* image, BOOL renderOnCPU)
{
	CIImageBitmapsInternalData* context =  _CIImagePrivateInitializeBitmapCreationContext(image);
	
	if (NULL != context) {
		context->colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		context->internalOutputPixelFormat = CIImageInternalOutputPixelFormatRGBA8;
		context->bitmapInfo = kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Host;
		context->bytesPerPixel = 4;
	}
	
	return _CIImagePrivateFinalizeBitmapCreationContext(context, image, renderOnCPU);
}

void* CIImageBitmapsCreateContextForPremultipliedRGBAf(CIImage* image, BOOL renderOnCPU)
{
	CIImageBitmapsInternalData* context =  _CIImagePrivateInitializeBitmapCreationContext(image);
	
	if (NULL != context) {
		context->colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		context->internalOutputPixelFormat = CIImageInternalOutputPixelFormatRGBAF;
		context->bitmapInfo =  kCGImageAlphaPremultipliedLast | kCGBitmapByteOrder32Host | kCGBitmapFloatComponents;
		context->bytesPerPixel = 16;
	}
	
	return _CIImagePrivateFinalizeBitmapCreationContext(context, image, renderOnCPU);
}

void* CIImageBitmapsCreateContextForRGB8(CIImage* image, BOOL renderOnCPU) {
	CIImageBitmapsInternalData* context =  _CIImagePrivateInitializeBitmapCreationContext(image);
	
	if (NULL != context) {
		context->colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
		context->internalOutputPixelFormat = CIImageInternalOutputPixelFormatRGB8;
		context->bitmapInfo = kCGImageAlphaNone | kCGBitmapByteOrder32Host;
		context->bytesPerPixel = 3;
	}
	
	return _CIImagePrivateFinalizeBitmapCreationContext(context, image, renderOnCPU);
}

void* CIImageBitmapsCreateContextForGrayscale8(CIImage* image, BOOL renderOnCPU)
{
	CIImageBitmapsInternalData* context =  _CIImagePrivateInitializeBitmapCreationContext(image);
	
	if (NULL != context) {
		context->colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericGray);
		context->internalOutputPixelFormat = CIImageInternalOutputPixelFormatGray8;
		context->bitmapInfo = kCGImageAlphaNone;
		context->bytesPerPixel = 1;
	}
	
	return _CIImagePrivateFinalizeBitmapCreationContext(context, image, renderOnCPU);
}

void CIImageBitmapsReleaseContext(void* pContext)
{
	if (NULL != pContext) {
		CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
		
		RELEASE_CF_MEMBER(context->colorSpace);
		RELEASE_CF_MEMBER(context->ciOutputColorSpace);
		RELEASE_CF_MEMBER(context->ciWorkingColorSpace);
		RELEASE_CF_MEMBER(context->cgContext);
		
		[context->ciContext release];
		context->ciContext = nil;
		
		free(context->outputBuffer);
		
		int i;
		for (i=0; i<MAX_INTERNAL_DATA_SCRATCH_SPACE; i++)
			if (NULL != context->scratchSpace[i]) {
				free(context->scratchSpace[i]);
				context->scratchSpace[i] = NULL;
				context->scratchRowBytes[i] = 0;
			}
		
		free(context);
	}
}

void CIImageBitmapsSetContextDeterminesFastestRenderingDynamically(void* pContext, BOOL determineDynamically)
{
	CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
	
	if (determineDynamically)
		context->chosenCreationMethod = CIImageInternalBitmapCreationMethodUndetermined;
	else
		context->chosenCreationMethod = CIImageInternalBitmapCreationMethodDefault;
}

inline BOOL CIImageBitmapsContextMatchesBitmapSize(void* pContext, CGSize size)
{
	CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
	return ((size_t)size.width == context->width && (size_t)size.height == context->height);
}

inline BOOL CIImageBitmapsContextRendersOnCPU(void* pContext)
{
	CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
	return context->renderOnCPU;
}

inline CIImageBitmapData CIImageBitmapsCurrentBitmapDataForContext(void* pContext)
{
	CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
	return _CIImagePrivateMakeBitmapData(context->outputBuffer,
										 context->width,
										 context->height,
										 context->rowBytes);
}

inline CGColorSpaceRef CIImageBitmapsCIOutputColorSpaceForContext(void* pContext)
{
	CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
	return context->ciOutputColorSpace;
}

inline CGColorSpaceRef CIImageBitmapsCIWorkingColorSpaceForContext(void* pContext)
{
	CIImageBitmapsInternalData* context = (CIImageBitmapsInternalData*)pContext;
	return context->ciWorkingColorSpace;
}

inline CIImageBitmapData _CIImagePrivateMakeBitmapData(void* data,
													   size_t width,
													   size_t height,
													   size_t rowBytes)
{
	CIImageBitmapData bitmapData = { data, width, height, rowBytes };
	return bitmapData;
}

CIImageBitmapsInternalData* _CIImagePrivateInitializeBitmapCreationContext(CIImage* image)
{
	if (nil == image || CGRectIsInfinite([image extent]))
		return NULL;
	
	CIImageBitmapsInternalData* context =
		(CIImageBitmapsInternalData*)malloc(sizeof(CIImageBitmapsInternalData));
	
	if (NULL != context)	
		memset(context, 0, sizeof(CIImageBitmapsInternalData));
	
	return context;
}

void* _CIImagePrivateFinalizeBitmapCreationContext(CIImageBitmapsInternalData* context,
												   CIImage* image,
												   BOOL renderOnCPU)
{
	if (NULL == context)
		return NULL;
	
	CGRect extent = [image extent];
	
	context->width = extent.size.width;
	context->height = extent.size.height;
	
	context->rowBytes = _CIImagePrivateOptimalRowBytesForWidthAndBytesPerPixel(context->width, context->bytesPerPixel);
	context->outputBuffer = malloc(context->rowBytes * context->height);
	
	context->renderOnCPU = renderOnCPU;
	context->chosenCreationMethod = CIImageInternalBitmapCreationMethodDefault;
	
	// no color matching
	context->ciWorkingColorSpace = (CGColorSpaceRef)[[NSNull null] retain];
	context->ciOutputColorSpace = (CGColorSpaceRef)[[NSNull null] retain];
	
	switch (context->internalOutputPixelFormat) {
		case CIImageInternalOutputPixelFormatGray8: {
			unsigned sRowBytes = _CIImagePrivateOptimalRowBytesForWidthAndBytesPerPixel(context->width, 4);
			
			context->scratchRowBytes[0] = sRowBytes;
			context->scratchSpace[0] = malloc(sRowBytes * context->height);
			
			context->scratchRowBytes[1] = sRowBytes;
			context->scratchSpace[1] = malloc(sRowBytes * context->height);
			
			break;
		}
		
		case CIImageInternalOutputPixelFormatRGB8:
		case CIImageInternalOutputPixelFormatRGBA8: {
			unsigned sRowBytes = _CIImagePrivateOptimalRowBytesForWidthAndBytesPerPixel(context->width, 4);
		
			context->scratchRowBytes[0] = sRowBytes;
			context->scratchSpace[0] = malloc(sRowBytes * context->height);
		
			break;
		}
		
		default:
			break;
	}
	
	// create the CGBitmapContext
	context->cgContext = CGBitmapContextCreate(context->outputBuffer,
											   context->width,
											   context->height,
											   ((context->bitmapInfo & kCGBitmapFloatComponents) ? 32 : 8),
											   context->rowBytes,
											   context->colorSpace,
											   context->bitmapInfo);
	
	if (NULL == context->cgContext)
		goto errorReturn;
	
	CGContextSetInterpolationQuality(context->cgContext, kCGInterpolationNone);
	
	// create the CIContext
	NSDictionary* options = [NSDictionary dictionaryWithObjectsAndKeys:
							 (id)context->ciOutputColorSpace, kCIContextOutputColorSpace, 
							 (id)context->ciWorkingColorSpace, kCIContextWorkingColorSpace,
							 [NSNumber numberWithBool:context->renderOnCPU], kCIContextUseSoftwareRenderer,
							 nil];
	
	context->ciContext = [[CIContext contextWithCGContext:context->cgContext
												  options:options] retain];
	
	if (NULL == context->ciContext)
		goto errorReturn;
	
	return (void*)context;
	
errorReturn:
	CIImageBitmapsReleaseContext((void*)context);
	
	return NULL;
}

size_t _CIImagePrivateOptimalRowBytesForWidthAndBytesPerPixel(size_t width, size_t bytesPerPixel)
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

int _CIImagePrivateConvertInternalPixelFormats(void* dest,
											   int destRowBytes,
											   CIImageBitmapsInternalData* internalData,
											   int width,
											   int height,
											   CIImageInternalOutputPixelFormat destFormat,
											   CIFormat srcFormat)
{
	int success = 0;
	
	if (NULL != dest && NULL != internalData) {
		if (CIImageInternalOutputPixelFormatGray8 == destFormat &&
			kCIFormatARGB8 == srcFormat) {			
			vImage_Buffer intermediateBuf, srcBuf, destBuf;
			
			intermediateBuf.data = internalData->scratchSpace[1];
			intermediateBuf.width = width;
			intermediateBuf.height = height;
			intermediateBuf.rowBytes = internalData->scratchRowBytes[1];
			
			srcBuf.data = internalData->scratchSpace[0];
			srcBuf.width = width;
			srcBuf.height = height;
			srcBuf.rowBytes = internalData->scratchRowBytes[0];
			
			destBuf.data = dest;
			destBuf.width = width;
			destBuf.height = height;
			destBuf.rowBytes = destRowBytes;
			
			// these constants are derived from the NTSC RGB->Luminance conversion
			int16_t matrix[] = { 0,   0, 0, 0,
								 0, 308, 0, 0,
								 0, 609, 0, 0,
								 0,  82, 0, 0 };
			
			vImageMatrixMultiply_ARGB8888(&srcBuf, &intermediateBuf, matrix, 100, NULL, NULL, 0);
			
			const void* srcBufArray[] = { (void*)((char*)intermediateBuf.data + 1) };
			const vImage_Buffer* destBufArray[] = { &destBuf };
			
			vImageConvert_ChunkyToPlanar8(srcBufArray,
										  destBufArray,
										  1,
										  4,
										  width,
										  height,
										  intermediateBuf.rowBytes,
										  0);
			success = 1;
		} else if (CIImageInternalOutputPixelFormatRGBA8 == destFormat &&
				   kCIFormatARGB8 == srcFormat) {
			vImage_Buffer srcBuf, destBuf;
			
			destBuf.data = dest;
			destBuf.width = width;
			destBuf.height = height;
			destBuf.rowBytes = destRowBytes;
			
			srcBuf.data = internalData->scratchSpace[0];
			srcBuf.width = width;
			srcBuf.height = height;
			srcBuf.rowBytes = internalData->scratchRowBytes[0];
			
			uint8_t permuteMap[] = { 1, 2, 3, 0 };
			vImagePermuteChannels_ARGB8888(&srcBuf, &destBuf, permuteMap, 0);
			
			success = 1;
		} else if (CIImageInternalOutputPixelFormatRGB8 == destFormat &&
				   kCIFormatARGB8 == srcFormat) {
			vImage_Buffer srcBuf, destBuf;
			
			destBuf.data = dest;
			destBuf.width = width;
			destBuf.height = height;
			destBuf.rowBytes = destRowBytes;
			
			srcBuf.data = internalData->scratchSpace[0];
			srcBuf.width = width;
			srcBuf.height = height;
			srcBuf.rowBytes = internalData->scratchRowBytes[0];
			
			vImageConvert_ARGB8888toRGB888(&srcBuf, &destBuf, 0);
			
			success = 1;
		}
	}
	
	return success;
}

uint64_t _CIImagePrivateGetCurrentNanoseconds()
{
	static mach_timebase_info_data_t timeBase;

	if (0 == timeBase.denom)
		(void)mach_timebase_info(&timeBase);
	
	uint64_t now = mach_absolute_time();
	
	return now * (timeBase.numer / timeBase.denom);
}
