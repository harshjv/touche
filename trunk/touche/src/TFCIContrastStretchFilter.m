//
//  TFCIContrastStretchFilter.m
//  Touche
//
//  Created by Georg Kaindl on 3/6/08.
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

#import "TFCIContrastStretchFilter.h"

#import "TFIncludes.h"
#import "CIImage+MakeBitmaps.h"

#define DEFAULT_SENSITIVITY	(0.01)
#define BOOST_BIAS	(0.0007f)

@implementation TFCIContrastStretchFilter

@synthesize isEnabled;
@synthesize evalMinMaxOnCPU;

static CIKernel*	tFCIContrastStretchFilterKernel = nil;
static CIKernel*	tFCIContrastStretchFilterEvalMinMaxOnCPUKernel = nil;
static CIKernel*	tFCIContrastStretchFilterBoostKernel = nil;

+ (void)initialize
{
	[CIFilter registerFilterName:@"TFCIContrastStretchFilter"
					 constructor:self
				 classAttributes:[NSDictionary dictionaryWithObjectsAndKeys:
								  TFLocalizedString(@"ContrastStretchFilterName", @"Contrast Stretch"),
								  kCIAttributeFilterDisplayName,
								  [NSArray arrayWithObjects:
								   kCICategoryVideo, kCICategoryStylize,
								   kCICategoryStillImage, kCICategoryNonSquarePixels,
								   nil], kCIAttributeFilterCategories,
								  nil]
	 ];
}

- (void)dealloc
{
	[_areaMaxFilter release];
	_areaMaxFilter = nil;
	
	[_areaMinFilter release];
	_areaMaxFilter = nil;
	
	CGColorSpaceRelease(_colorSpace);
	_colorSpace = nil;
	
	CGColorSpaceRelease(_workingColorSpace);
	_workingColorSpace = nil;
	
	if (NULL != _imgBuffer) {
		free(_imgBuffer);
		_imgBuffer = NULL;
	}
	
	[super dealloc];
}

- (id)init
{
	if (nil == (self = [super init])) {
		[self release];
		return nil;
	}
	
	if (nil == tFCIContrastStretchFilterKernel || nil == tFCIContrastStretchFilterEvalMinMaxOnCPUKernel) {
		NSString*	kernelCode = [NSString stringWithContentsOfFile:
								  [[NSBundle bundleForClass:[self class]]
								   pathForResource:@"TFCIContrastStretchFilter" ofType:@"cikernel"]];
		
		NSArray *kernels = [CIKernel kernelsWithString:kernelCode];
		
		tFCIContrastStretchFilterKernel = [[kernels objectAtIndex:0] retain];
		tFCIContrastStretchFilterEvalMinMaxOnCPUKernel = [[kernels objectAtIndex:1] retain];
		tFCIContrastStretchFilterBoostKernel = [[kernels objectAtIndex:2] retain];
	}
	
	_areaMaxFilter = [[CIFilter filterWithName:@"CIAreaMaximum"] retain];
	_areaMinFilter = [[CIFilter filterWithName:@"CIAreaMinimum"] retain];
	
	[_areaMaxFilter setDefaults];
	[_areaMinFilter setDefaults];
	
	_colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
	_workingColorSpace = CGColorSpaceCreateWithName(kCGColorSpaceGenericRGB);
	_rowBytes = 16;
	_imgBuffer = (float*)malloc(sizeof(float)*_rowBytes);
	
	isEnabled = NO;
	evalMinMaxOnCPU = YES;
	
	return self;
}

+ (CIFilter *)filterWithName:(NSString *)name
{
	CIFilter  *filter = [[self alloc] init];
	
	return [filter autorelease];
}

- (NSDictionary*)customAttributes
{
	return [NSDictionary dictionaryWithObjectsAndKeys:
			
			[NSDictionary dictionaryWithObjectsAndKeys:
			 [NSNumber numberWithDouble:0.000001],	kCIAttributeMin,
			 [NSNumber numberWithDouble:1.8],		kCIAttributeMax,
			 [NSNumber numberWithDouble:0.000001],	kCIAttributeSliderMin,
			 [NSNumber numberWithDouble:1.8],		kCIAttributeSliderMax,
			 [NSNumber numberWithDouble:DEFAULT_SENSITIVITY],	kCIAttributeDefault,
			 kCIAttributeTypeScalar,			kCIAttributeType,
			 nil],								@"inputStretchMinIntensityDistance",
			
			[NSDictionary dictionaryWithObjectsAndKeys:
			 [CIImage class],					kCIAttributeClass,
			 nil],								@"inputImage",
			
			[NSDictionary dictionaryWithObjectsAndKeys:
			 [NSNumber numberWithDouble:1.0],	kCIAttributeMin,
			 [NSNumber numberWithDouble:30.0],	kCIAttributeMax,
			 [NSNumber numberWithDouble:1.0],	kCIAttributeSliderMin,
			 [NSNumber numberWithDouble:30.0],	kCIAttributeSliderMax,
			 [NSNumber numberWithDouble:1.0],	kCIAttributeDefault,
			 kCIAttributeTypeScalar,			kCIAttributeType,
			 nil],								@"inputBoostStrength",
			
			[NSDictionary dictionaryWithObjectsAndKeys:
			 [NSNumber numberWithFloat:TFCIContrastStretchFilterOpTypeMin],	kCIAttributeMin,
			 [NSNumber numberWithFloat:TFCIContrastStretchFilterOpTypeMax],	kCIAttributeMax,
			 [NSNumber numberWithFloat:TFCIContrastStretchFilterOpTypeMin],	kCIAttributeSliderMin,
			 [NSNumber numberWithFloat:TFCIContrastStretchFilterOpTypeMax],	kCIAttributeSliderMax,
			 [NSNumber numberWithFloat:TFCIContrastStretchFilterOpTypeStretch],	kCIAttributeDefault,
			 kCIAttributeTypeInteger,			kCIAttributeType,
			 nil],								@"inputOpType",
			
			nil];
}

- (CIImage*)outputImage
{
	if (!isEnabled)
		return inputImage;

	CIImage* outImg = nil;
	CISampler* src = [CISampler samplerWithImage:inputImage options:
					  [NSDictionary dictionaryWithObjectsAndKeys:kCISamplerFilterNearest, kCISamplerFilterMode, nil]];
	
	switch ([inputOpType intValue]) {
		case TFCIContrastStretchFilterOpTypeStretch: {
			// we do not need to set inputExtent: the default is the complete image
			[_areaMaxFilter setValue:inputImage forKey:@"inputImage"];
			[_areaMinFilter setValue:inputImage forKey:@"inputImage"];
			
			CIImage* maxImg = [_areaMaxFilter valueForKey:@"outputImage"];
			CIImage* minImg = [_areaMinFilter valueForKey:@"outputImage"];
			
			if (!evalMinMaxOnCPU) {
				CISampler* maxSampler = [CISampler samplerWithImage:maxImg options:
								 [NSDictionary dictionaryWithObjectsAndKeys:kCISamplerFilterNearest, kCISamplerFilterMode,
										kCISamplerWrapClamp, kCISamplerWrapMode,
										nil]];
				
				CISampler* minSampler = [CISampler samplerWithImage:minImg options:
										 [NSDictionary dictionaryWithObjectsAndKeys:kCISamplerFilterNearest, kCISamplerFilterMode,
										  kCISamplerWrapClamp, kCISamplerWrapMode,
										  nil]];
				
				outImg = [self apply:tFCIContrastStretchFilterKernel, src, maxSampler, minSampler, inputStretchMinIntensityDistance,
									kCIApplyOptionDefinition, [src definition], nil];
			} else {			
				_imgBuffer = [minImg createPremultipliedRGBAFFFFBitmapWithColorSpace:_colorSpace
																   workingColorSpace:_workingColorSpace
																			rowBytes:&_rowBytes
																			  buffer:(void*)_imgBuffer
																		 renderOnCPU:YES];
				
				CIVector* minVect = [CIVector vectorWithX:_imgBuffer[0]
														Y:_imgBuffer[1]
														Z:_imgBuffer[2]];

				_imgBuffer = [maxImg createPremultipliedRGBAFFFFBitmapWithColorSpace:_colorSpace
																   workingColorSpace:_workingColorSpace
																			rowBytes:&_rowBytes
																			  buffer:(void*)_imgBuffer
																		 renderOnCPU:YES];
								
				float dx = _imgBuffer[0]-[minVect X], dy = _imgBuffer[1]-[minVect Y], dz = _imgBuffer[2]-[minVect Z];
				
				if (0 == dx || 0 == dy || 0 == dz)
					return inputImage;
				
				CIVector* invDiffVect = [CIVector vectorWithX:1.0f/dx
															Y:1.0f/dy
															Z:1.0/dz];

				float diffLen = sqrt(dx*dx + dy*dy + dz*dz);	
				if (diffLen < [inputStretchMinIntensityDistance floatValue])
					return inputImage;
				
				outImg =  [self apply:tFCIContrastStretchFilterEvalMinMaxOnCPUKernel, src, minVect, invDiffVect,
										kCIApplyOptionDefinition, [src definition], nil];
			}
		}
		
		break;
		
		default:
		case TFCIContrastStretchFilterOpTypeBoost: {
			float bS = [inputBoostStrength floatValue] * BOOST_BIAS;
			
			outImg = [self apply:tFCIContrastStretchFilterBoostKernel, src, inputBoostStrength, [NSNumber numberWithFloat:bS],
									kCIApplyOptionDefinition, [src definition], nil];
		}
		
		break;
	}
	
	return outImg;
}

@end