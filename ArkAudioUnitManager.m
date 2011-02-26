////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Arkonnekt AppKit, Cocoa classes for audio programming. 
// Copyright (C) 2005 Jeremy Jurksztowicz
//
// This library is free software; you can redistribute it and/or modify it under the terms of the 
// GNU Lesser General Public License as published by the Free Software Foundation; either version 
// 2.1 of the License, or (at your option) any later version. This library is distributed in the 
// hope that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU Lesser General Public License 
// for more details. 
//
// You should have received a copy of the GNU Lesser General Public License along with this library; 
// if not, write to the Free Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 
// 02111-1307 USA
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////

#import  "ArkAudioUnitManager.h"
#import  "ArkAudioUnit.h"
#include <AudioUnit/AudioUnit.h>
#include <AudioUnit/MusicDevice.h>

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
static int sort_names (id n1, id n2, void*context)
{
	return [(NSString*)n1 compare:n2];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation ArkAudioUnitManager

static ArkAudioUnitManager  * theDefaultManager;

+ (void) initialize
{
	static BOOL done = NO;
	if(!done) {
		theDefaultManager  = [[ArkAudioUnitManager  alloc] init];
		done = YES;
	}
}

+ (ArkAudioUnitManager*) defaultManager
{
	return theDefaultManager;
}

- (void) dealloc
{
	[self closeAllAudioUnits];
	[super dealloc];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
+ (BOOL) installDefaultAUGraph
{
	AUGraph auGraph;
	OSStatus err = NewAUGraph(&auGraph);
	if(err) {
		NSLog(@"Error creating new AUGraph. OSStatus %d", (OSErr)err);
		return NO;
	}
	
	err = AUGraphOpen(auGraph);
	if(err) {
		NSLog(@"Error opening AUGraph. OSStatus %d", (OSErr)err);
		return NO;
	}
	
	err = AUGraphInitialize(auGraph);
	if(err) {
		NSLog(@"Error initializing AUGraph. OSStatus %d", (OSErr)err);
		return NO;
	}
	
	[ArkAudioUnit setGraph:auGraph];
	return YES;
}

+ (void) destroyInstalledAUGraph
{
	AUGraph graph = [ArkAudioUnit graph];
	OSStatus ret = AUGraphUninitialize(graph);
	if(ret)
		NSLog(@"Error uninitializing AUGraph. OSStatus %d", (OSErr)ret);
		
	ret = AUGraphClose(graph);
	if(ret)
		NSLog(@"Error closing AUGraph. OSStatus %d", (OSErr)ret);

	OSStatus err = DisposeAUGraph(graph);
	if(err)
		NSLog(@"Error destroying AUGraph. OSStatus %d", (OSErr)ret);
		
	[ArkAudioUnit setGraph:0];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
+ (NSArray*) stringsForUnit:(Component)tempComp 
			withDescription:(ComponentDescription*)tempDesc
{
	assert(tempComp);
	
	char name[255];
	char info[255];
	Handle nameHandle = NewHandle(255); 
	Handle infoHandle = NewHandle(255);
	OSStatus ret = GetComponentInfo(tempComp, tempDesc, nameHandle, infoHandle, NULL);
	if(ret == noErr) {
		CopyPascalStringToC((ConstStr255Param)(*nameHandle),name);
		CopyPascalStringToC((ConstStr255Param)(*infoHandle),info);
	}
	else return nil;
	
	DisposeHandle(nameHandle);
	DisposeHandle(infoHandle);
	
	return [NSArray arrayWithObjects:
		[NSString stringWithCString:name],
		[NSString stringWithCString:info], nil];
}

+ (NSDictionary*) createUnitListWithType:(int)uType
{
	NSMutableDictionary * dict = [NSMutableDictionary dictionary];
	
	ComponentDescription desc, instDesc;
	desc.componentType		   = uType;
	desc.componentSubType      = 0;
    desc.componentManufacturer = 0;
    desc.componentFlags		   = 0;
    desc.componentFlagsMask    = 0;
	instDesc = desc;
	
	Component compIter = FindNextComponent(NULL, &desc);
	while(compIter != NULL) 
	{
		NSArray * ret = [ArkAudioUnitManager stringsForUnit:compIter withDescription:&instDesc];
		if(!ret)
		{
			NSLog(@"Error reading AudioUnit strings, skipping to next AudioUnit.");
			compIter = FindNextComponent(compIter, &instDesc);
			continue;
		}
		[dict setObject:[NSData dataWithBytes:(uint8_t const*)(&instDesc) 
				 length:sizeof(ComponentDescription)]
				 forKey:[ret objectAtIndex:0]];
					 
		compIter = FindNextComponent(compIter, &desc);
		instDesc = desc;
	}
	return dict;
}

+ (ComponentDescription) descriptionInDictionary:(NSDictionary*)dict withName:(NSString*)name
{
	// Leave room for growing the ComponentDescription layout.
	assert([(NSData*)[dict objectForKey:name] length] >= sizeof(ComponentDescription));
	const uint8_t * rawDesc = [[dict objectForKey:name] bytes];
	ComponentDescription desc;
	memcpy(&desc, rawDesc, sizeof(ComponentDescription));

	return desc;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) createInstrumentList
{
	[_instruments release];
	_instruments = [[ArkAudioUnitManager createUnitListWithType:kAudioUnitType_MusicDevice] retain];
}

- (NSArray*) instrumentNames
{
	if(!_instrumentNames) 
	{
		if(!_instruments)
			[self createInstrumentList];
		
		_instrumentNames = [[[_instruments allKeys] 
			sortedArrayUsingFunction:sort_names context:NULL] retain];
	}	
	return _instrumentNames;
}

- (ArkAudioUnit*) createInstrumentWithName:(NSString*)name
{
	return [ArkAudioUnit audioUnitWithDescription:
		[ArkAudioUnitManager descriptionInDictionary:_instruments withName:name]];
}

- (ComponentDescription) descriptionOfInstrumentWithName:(NSString*)name
{
	return [ArkAudioUnitManager descriptionInDictionary:_instruments withName:name];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) createRealtimeEffectList
{
	[_realtimeEffects release];
	_realtimeEffects = [[ArkAudioUnitManager createUnitListWithType:kAudioUnitType_Effect] retain];
}

- (NSArray*) realtimeEffectNames
{
	if(!_realtimeEffectNames) 
	{
		if(!_realtimeEffects)
			[self createRealtimeEffectList];
			
		_realtimeEffectNames = [[[_realtimeEffects allKeys] 
			sortedArrayUsingFunction:sort_names context:NULL] retain];
	}
		
	return _realtimeEffectNames;
}

- (ArkAudioUnit*) createRealtimeEffectWithName:(NSString*)name
{
	return [ArkAudioUnit audioUnitWithDescription:
		[ArkAudioUnitManager descriptionInDictionary:_realtimeEffects withName:name]];
}

- (ComponentDescription) descriptionOfRealtimeEffectWithName:(NSString*)name
{
	return [ArkAudioUnitManager descriptionInDictionary:_realtimeEffects withName:name];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) createMixerList
{
	[_mixers release];
	_mixers = [[ArkAudioUnitManager createUnitListWithType:kAudioUnitType_Mixer] retain];
}

- (NSArray*) mixerNames
{
	if(!_mixerNames)
	{
		if(!_mixers)
			[self createMixerList];
			
		_mixerNames = [[[_mixers allKeys] 
			sortedArrayUsingFunction:sort_names context:NULL] retain];
	}	
	return _mixerNames;
}

- (ArkAudioUnit*) createMixerWithName:(NSString*)name
{
	return [ArkAudioUnit audioUnitWithDescription:
		[ArkAudioUnitManager descriptionInDictionary:_mixers withName:name]];
}

- (ComponentDescription) descriptionOfMixerWithName:(NSString*)name
{
	return [ArkAudioUnitManager descriptionInDictionary:_mixers withName:name];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// kAudioUnitType_Panner
//
- (void) createPannerList
{
	[_panners release];
	_panners = [[ArkAudioUnitManager createUnitListWithType:kAudioUnitType_Panner] retain];
}

- (NSArray*) pannerNames
{
	if(!_pannerNames)
	{
		if(!_panners)
			[self createPannerList];
		
		_pannerNames = [[[_panners allKeys] 
			sortedArrayUsingFunction:sort_names context:NULL] retain];
	}	
	return _pannerNames;
}

- (ArkAudioUnit*) createPannerWithName:(NSString*)name
{
	return [ArkAudioUnit audioUnitWithDescription:
		[ArkAudioUnitManager descriptionInDictionary:_panners withName:name]];
}

- (ComponentDescription) descriptionOfPannerWithName:(NSString*)name
{
	return [ArkAudioUnitManager descriptionInDictionary:_panners withName:name];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) createOutputList
{
	[_outputs release];
	_outputs = [[ArkAudioUnitManager createUnitListWithType:kAudioUnitType_Output] retain];
}

- (NSArray*) outputNames
{
	if(!_outputNames)
	{
		if(!_outputs)
			[self createOutputList];
		
		_outputNames = [[[_outputs allKeys] 
			sortedArrayUsingFunction:sort_names context:NULL] retain];
	}	
	return _outputNames;
}

- (ArkAudioUnit*) createOutputWithName:(NSString*)name
{
	return [ArkAudioUnit audioUnitWithDescription:
		[ArkAudioUnitManager descriptionInDictionary:_outputs withName:name]];
}

- (ComponentDescription) descriptionOfOutputWithName:(NSString*)name
{
	return [ArkAudioUnitManager descriptionInDictionary:_outputs withName:name];
}

- (ArkAudioUnit*) createDefaultOutput
{
	return [self createOutputWithName:[[self outputNames] objectAtIndex:0]];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (void) createAllAudioUnitLists
{
	[self createInstrumentList];
	[self createRealtimeEffectList];
	[self createMixerList];
	[self createPannerList];
	[self createOutputList];
}

- (void) closeAllAudioUnits
{
	[_instruments			release]; _instruments			= nil;
	[_instrumentNames		release]; _instrumentNames		= nil;
	
	[_realtimeEffects		release]; _realtimeEffects		= nil;
	[_realtimeEffectNames   release]; _realtimeEffectNames  = nil;
	
	[_offlineEffects		release]; _offlineEffects		= nil;
	[_offlineEffectNames	release]; _offlineEffectNames   = nil;
	
	[_mixers				release]; _mixers				= nil;
	[_mixerNames			release]; _mixerNames			= nil;
	
	[_panners				release]; _panners				= nil;
	[_pannerNames			release]; _pannerNames			= nil;
	
	[_outputs				release]; _outputs				= nil;
	[_outputNames			release]; _outputNames			= nil;
}

@end