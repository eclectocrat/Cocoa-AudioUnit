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

#import "ArkAudioUnit.h"

// This is for AUParameterSet, which automatically handles notifications for us.
#import <AudioToolbox/AudioUnitUtilities.h>

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
#ifndef SOURCE_LOC
	#define _SL_UTIL_1(x)   #x
	#define _SL_UTIL_2(x)   _SL_UTIL_1(x)
	#define _SL_UTIL        _SL_UTIL_2(__LINE__)

	#define SOURCE_LOC __FILE__ "(" _SL_UTIL ")"
#endif
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@implementation ArkAudioUnit

static AUGraph _defaultGraph;

+ (void) setGraph:(AUGraph)graph
{
	_defaultGraph = graph;
}

+ (AUGraph)	graph
{
	return _defaultGraph;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
+ (ArkAudioUnit*) audioUnitWithComponent:(Component)au
{
	return [[[ArkAudioUnit alloc] initWithComponent:au] autorelease];
}

+ (ArkAudioUnit*) audioUnitWithDescription:(ComponentDescription)desc
{
	return [[[ArkAudioUnit alloc] initWithDescription:desc] autorelease];
}

+ (ArkAudioUnit*) audioUnitWithType:(OSType)type subType:(OSType)subtype manufacturer:(OSType)man
{
	return [[[ArkAudioUnit alloc] initWithType:type subType:subtype manufacturer:man] autorelease];
}

- (void) ark_initBasics
{
	_lastResult = noErr;
	_lastError = noErr;
	_hasRenderCallback = NO;
	_isOpen = NO;
	_initialized = NO;
}

- (BOOL) ark_readUnitText:(ComponentDescription*)tempDesc
{
	// I know this is ugly, welcome to the arcane arts.
	char name[255];
	char info[255];
	Handle nameHandle = NewHandle(255); 
	Handle infoHandle = NewHandle(255);
	OSStatus ret = GetComponentInfo(_component, tempDesc, nameHandle, infoHandle, NULL);
	if(ret == noErr) {
		CopyPascalStringToC((ConstStr255Param)(*nameHandle),name);
		CopyPascalStringToC((ConstStr255Param)(*infoHandle),info);
	}
	else {
		[self registerResult:ret];
		return NO;
	}
	DisposeHandle(nameHandle);
	DisposeHandle(infoHandle);
	
	[self setName:[NSString stringWithCString:name]];
	
	if(_info) [_info release];
	_info = [[NSString stringWithCString:info] retain];
	
	return YES;
}

- (id) initWithComponent:(Component)au
{
	memset(&_auDesc, 0, sizeof(ComponentDescription));
	[self ark_initBasics];

	[self registerResult:GetComponentInfo(au, &_auDesc, NULL, NULL, NULL)];
	if([self lastResult] == noErr)
		 return [self initWithDescription:_auDesc];
	else { 
		[self release];
		return nil;
	}
}

- (id) initWithDescription:(ComponentDescription)desc
{
	// Get the current audio unit graph.
	AUGraph graphRep = [ArkAudioUnit graph];
	if(NULL == graphRep)
	{
		NSLog(@"Cannot instantiate an AUNode without an AUGraph : %s", SOURCE_LOC);
		[self release];
		return nil;
	}

	// Find and open the audio unit.	
	_lastResult = AUGraphNewNode(graphRep, &desc, 0, NULL, &_audioNode);
	_lastError = _lastResult;
	if(noErr != _lastResult)
	{
		[self release];
		return nil;
	}
	else
	{
		_lastResult = AUGraphGetNodeInfo(
			graphRep, _audioNode, NULL, NULL, NULL, &_audioUnit);
		_lastError = _lastResult;
		if(noErr == _lastResult) 
		{
			if(self = [super init]) 
			{
				_auDesc = desc;
				_component = FindNextComponent(NULL, &_auDesc);
			
				[self ark_readUnitText:&desc];
				[self ark_initBasics];
				_isOpen = YES;
				
				// Now that we are opened, we can get all the factory presets.
				CFArrayRef presetsArray;
				UInt32 size = sizeof(presetsArray);
				_lastResult = AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_FactoryPresets,
					0, 0, &presetsArray, &size);
					
				if(noErr == _lastResult) _presets = (NSArray*)presetsArray;
				else if(_lastResult != kAudioUnitErr_InvalidProperty) 
					[self registerResult:_lastResult];
					
				_lastError = _lastResult;
			}
		}
	}
	return self;
}

- (id) initWithType:(OSType)type subType:(OSType)subtype manufacturer:(OSType)man
{
	ComponentDescription desc;
	desc.componentType = type;
	desc.componentSubType = subtype;
	desc.componentManufacturer = man;
	desc.componentFlags = 0;
	desc.componentFlagsMask = 0;
		
	return [self initWithDescription:desc];
}

- (id) duplicate
{
	ArkAudioUnit * unit = [[ArkAudioUnit alloc] initWithDescription:_auDesc];
	NSDictionary * curr = [self savePreset:nil];
	if(curr)
		[unit loadPresetFromDictionary:curr];
		
	return unit;
}

- (void) dealloc
{
	[self uninitialize];
	[self close];
	
	[_presets release];
	[_info release];
	
	if(additions)
		[additions release];
	
	[super dealloc];
}

- (NSString*) description
{
	// TODO: You can print a full state diagram of the unit here if you want.
	return [self name];
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Encoding
static NSString * ComponentDescriptionKey	= @"ArkAudioUnit.componentDescription";
static NSString * PresetKey					= @"ArkAudioUnit.preset";
static NSString * IsInitializedKey			= @"ArkAudioUnit.isInitialized";

- (void) encodeWithCoder:(NSCoder*)coder
{ 
	// TODO: Perhaps depending on the size of ComponentDescription is dangerous?
	[coder encodeBytes:(uint8_t*)(&_auDesc) length:sizeof(ComponentDescription) 
		forKey:ComponentDescriptionKey];
	
	NSDictionary * preset = [self savePreset:nil];
	[coder encodeObject:preset forKey:PresetKey];
	[coder encodeBool:_initialized forKey:IsInitializedKey];
}

- (id) initWithCoder:(NSCoder*)coder
{
	////////////////////////////////////
	// First get ComponentDescrpition
	////////////////////////////////////
	unsigned bytesLen;
	const uint8_t * rawDesc = [coder decodeBytesForKey:
		ComponentDescriptionKey returnedLength:&bytesLen];
	if(bytesLen != sizeof(ComponentDescription)) 
	{
		NSLog(@"Byte buffer not expected size at %s.", SOURCE_LOC);
		[self release];
		return nil;
	}
	ComponentDescription desc;
	memcpy(&desc, rawDesc, sizeof(ComponentDescription));
		
	////////////////////////////////////
	// Init node with description
	////////////////////////////////////
	if(self = [self initWithDescription:desc]) 
	{
		[self open];
		if([coder decodeBoolForKey:IsInitializedKey]) {
			[self initialize];
		}
		
	////////////////////////////////////
	// Load preset
	////////////////////////////////////
		NSDictionary * preset = [coder decodeObjectForKey:PresetKey];
		if([self loadPresetFromDictionary:preset] != noErr)
		{
			NSLog(@"Failed to load preset %@ when initializing AudioUnit %@ from coder %@.",
				preset, self, coder);
		}
	}
	return self;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (Component) audioUnit
{
	return _component;
}

- (ComponentDescription) audioUnitDescription
{
	return _auDesc;
}

- (AudioUnit) audioUnitInstance
{
	return _audioUnit;
}

- (AUNode) audioNodeInstance
{
	return _audioNode;
}

- (NSString*) info
{
	return [[_info retain] autorelease];
}

- (NSString*) name
{
	return [[_name copy] autorelease];
}

- (void) setName:(NSString*)newName
{
	[_name autorelease];
	_name = [newName retain];
}

- (BOOL) isOutput
{
	return _auDesc.componentType == kAudioUnitType_Output;
}

- (BOOL) isInstrument
{
	return _auDesc.componentType == kAudioUnitType_MusicDevice;
}

- (BOOL) isMixer
{
	return _auDesc.componentType == kAudioUnitType_Mixer;
}

- (BOOL) isEffect
{
	return _auDesc.componentType == kAudioUnitType_Effect;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (OSStatus) open
{
	if(!_isOpen) {
		OSErr ret = OpenAComponent(_component,&_audioUnit);
		if(ret == noErr) {
			_isOpen = YES;
			
			// Ok now that we are opened, we can get all the factory presets.
			CFArrayRef presetsArray;
			UInt32 size = sizeof(presetsArray);
			OSStatus ret = AudioUnitGetProperty(_audioUnit,
				kAudioUnitProperty_FactoryPresets,
				kAudioUnitScope_Global, 0, &presetsArray, &size);
				
			if(ret == noErr) {
				if(_presets) 
					[_presets release];
				_presets = (NSArray*)presetsArray;
			}
			else if(ret != kAudioUnitErr_InvalidProperty) 
				[self registerResult:ret];
		}
		else return [self registerResult:ret];
	}
	return noErr;
}

- (void) close
{
	if(_isOpen) {
		CloseComponent(_audioUnit);
		_isOpen = NO;
		
		[_info    release]; _info    = nil;
		[_presets release]; _presets = nil;
	}
}

- (BOOL) isOpen
{
	return _isOpen && CountComponentInstances((Component)_audioUnit);
}

- (OSStatus) initialize
{
	if(!_initialized) {
		if([self registerResult:AudioUnitInitialize(_audioUnit)] == noErr)
			_initialized = YES;
			
		return [self lastResult];
	}
	return noErr;
}

- (void) uninitialize
{
	if(_initialized) {
		AudioUnitUninitialize(_audioUnit);
		_initialized = NO;
	}
}

- (BOOL) isInitialized
{
	return _initialized;
}

- (void) reset
{
	if(_initialized)
		AudioUnitReset(_audioUnit, kAudioUnitScope_Global, 0);
}

- (BOOL) startOutput
{
	if([self isOutput])
	{
		if([self registerResult:AudioOutputUnitStart(_audioUnit)] == noErr);
			return YES;
	}
	return NO;
}

- (BOOL) stopOutput
{
	if([self isOutput])
	{
		if([self registerResult:AudioOutputUnitStop(_audioUnit)] == noErr);
			return YES;
	}
	return NO;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Parameters
//
- (OSStatus) setParameter:(AudioUnitParameterID)param forScope:(AudioUnitScope)scope 
				  element:(AudioUnitElement)elem toValue:(Float32)val
{
	AudioUnitParameter paramInfo;
	paramInfo.mAudioUnit = _audioUnit;
	paramInfo.mParameterID = param;
	paramInfo.mScope = scope;
	paramInfo.mElement = elem;
	return [self registerResult:AUParameterSet(NULL, NULL, &paramInfo, val, 0)];
}

- (Float32) parameter:(AudioUnitParameterID)param forScope:(AudioUnitScope)scope 
			  element:(AudioUnitElement)elem
{
	Float32 paramVal = 0.0;
	[self registerResult:AudioUnitGetParameter(_audioUnit,param,scope,elem,&paramVal)];
	return paramVal;
}
			   
- (OSStatus) setInputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem 
					   toValue:(Float32)val
{
	return [self setParameter:param forScope:kAudioUnitScope_Input element:elem toValue:val];
}

- (Float32) inputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem
{
	return [self parameter:param forScope:kAudioUnitScope_Input element:elem];
}

- (OSStatus) setOutputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem 
					    toValue:(Float32)val
{
	return [self setParameter:param forScope:kAudioUnitScope_Output element:elem toValue:val];
}

- (Float32) outputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem
{
	return [self parameter:param forScope:kAudioUnitScope_Output element:elem];
}

- (NSArray*) parameterList
{
	UInt32 arraySz = 0;
	if([self registerResult:AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_ParameterList,
		kAudioUnitScope_Global, 0, NULL, &arraySz)] != noErr) return nil;

	void * parameterIDs = malloc(arraySz);
	if(parameterIDs) 
	{
		if([self registerResult:AudioUnitGetProperty(_audioUnit, kAudioUnitProperty_ParameterList,
			kAudioUnitScope_Global, 0, parameterIDs, &arraySz)] != noErr) 
		{
			free(parameterIDs);
			return nil;
		}
		
		AudioUnitParameterID* paramIDArray = (AudioUnitParameterID*)parameterIDs;
		unsigned numParams = arraySz/sizeof(AudioUnitParameterID);
		unsigned i;
		
		NSMutableArray * paramArray = [NSMutableArray arrayWithCapacity:numParams];
		for(i = 0; i != numParams; i++) 
			[paramArray addObject:[NSNumber numberWithInt:(int)(paramIDArray[i])]];
			
		free(parameterIDs);
		return paramArray;
	}
	free(parameterIDs);
	return nil;
}

- (OSStatus) getParameterInfo:(AudioUnitParameterID)	paramID
					 forScope:(AudioUnitScope)			scope
				   infoStruct:(AudioUnitParameterInfo*) pinfo
{
	assert(pinfo);
	
	UInt32 piSize = sizeof(AudioUnitParameterInfo);
	return [self registerResult:AudioUnitGetProperty(_audioUnit, 
		kAudioUnitProperty_ParameterInfo, scope, paramID, &pinfo, &piSize)];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Properties
//
- (OSStatus) setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toValue:(void*)val size:(UInt32)size
{
	return [self registerResult:AudioUnitSetProperty(_audioUnit,prop,scope,elem,val,size)];
}
				 
- (OSStatus) setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toUInt32Value:(UInt32)val
{
	return [self setProperty:prop forScope:scope element:elem toValue:&val size:sizeof(UInt32)];
}
				 
- (OSStatus) setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toFloat32Value:(Float32)val
{
	return [self setProperty:prop forScope:scope element:elem toValue:&val size:sizeof(Float32)];
}
				 
- (OSStatus) setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toFloat64Value:(Float64)val
{
	return [self setProperty:prop forScope:scope element:elem toValue:&val size:sizeof(Float64)];
}
				 
- (OSStatus) getProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem buffer:(void*)buf
{
	assert(buf);

	UInt32 dataSz = 0;
	Boolean writable;
	if([self registerResult:AudioUnitGetPropertyInfo(_audioUnit,prop,scope,elem,
		&dataSz, &writable)] != noErr) return [self lastResult];
	
	return [self registerResult:AudioUnitGetProperty(
		_audioUnit,prop,scope,elem, buf,&dataSz)];
}
			  
- (UInt32) UInt32Property:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				  element:(AudioUnitElement)elem
{
	UInt32 propVal = 0;
	UInt32 propSz  = sizeof(UInt32);
	[self registerResult:AudioUnitGetProperty(_audioUnit,prop,scope,elem,&propVal,&propSz)];
		
	return propVal;
}
					
- (Float32) Float32Property:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
					element:(AudioUnitElement)elem
{
	Float32 propVal = 0;
	UInt32  propSz  = sizeof(Float32);
	[self registerResult:AudioUnitGetProperty(_audioUnit,prop,scope,elem,&propVal,&propSz)];
	
	return propVal;
}
					 
- (Float64) Float64Property:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
					element:(AudioUnitElement)elem
{
	Float64 propVal = 0;
	UInt32  propSz  = sizeof(Float64);
	[self registerResult:AudioUnitGetProperty(_audioUnit,prop,scope,elem,&propVal,&propSz)];
	
	return propVal;
}

- (UInt32) propertySize:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				element:(AudioUnitElement)elem
{
	UInt32 size = 0;
	[self registerResult:AudioUnitGetPropertyInfo(_audioUnit,prop,scope,elem,&size,NULL)];
	return size;
}
				  
- (BOOL) isPropertyWritable:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
					element:(AudioUnitElement)elem
{
	Boolean writable = 0;
	[self registerResult:AudioUnitGetPropertyInfo(_audioUnit,prop,scope,elem,NULL,&writable)];
	return (BOOL)writable;
}

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Specific Properties
//
- (OSStatus) setBypassing:(BOOL)bypass
{
	UInt32 doBypass = bypass ? 1 : 0;
	return [self registerResult:AudioUnitSetProperty(_audioUnit,
		kAudioUnitProperty_BypassEffect,
		kAudioUnitScope_Global, 0, &doBypass, sizeof(doBypass))];
}

- (BOOL) isBypassing
{
	UInt32 doBypass   = 0;
	UInt32 doBypassSz = sizeof(doBypass);
	[self registerResult:AudioUnitGetProperty(_audioUnit,
		kAudioUnitProperty_BypassEffect,
		kAudioUnitScope_Global, 0, &doBypass, &doBypassSz)];

	return doBypass ? YES : NO;
}

- (Float64) latency
{
	return [self Float64Property:kAudioUnitProperty_Latency forScope:kAudioUnitScope_Global element:0];
}

- (Float64) tailTime
{
	return [self Float64Property:kAudioUnitProperty_TailTime forScope:kAudioUnitScope_Global element:0];
}

- (OSStatus) setBusCount:(UInt32)busCount forScope:(AudioUnitScope)scope
{
	return [self setProperty:kAudioUnitProperty_BusCount 
		forScope:scope element:0 toUInt32Value:busCount];
}

- (UInt32) busCountForScope:(AudioUnitScope)scope
{
	return [self UInt32Property:kAudioUnitProperty_BusCount forScope:scope element:0];
}

- (BOOL) isBusCountWritableForScope:(AudioUnitScope)scope
{
	return [self isPropertyWritable:kAudioUnitProperty_BusCount forScope:scope element:0];
}

- (OSStatus) setStreamFormat:(AudioStreamBasicDescription*)desc 
	forScope:(AudioUnitScope)scope bus:(AudioUnitElement)busNum
{
	assert(desc);

	return [self registerResult:AudioUnitSetProperty(_audioUnit,kAudioUnitProperty_StreamFormat,
		scope,busNum,desc,sizeof(AudioStreamBasicDescription))];
}

- (OSStatus) getStreamFormatForScope:(AudioUnitScope)  scope 
								 bus:(AudioUnitElement)busNum
				   formatDescription:(AudioStreamBasicDescription*)desc;
{
	UInt32 descSz = sizeof(AudioStreamBasicDescription);
	memset(&desc, 0, descSz);
	return [self registerResult:AudioUnitGetProperty(_audioUnit,
		kAudioUnitProperty_StreamFormat, scope,busNum,desc,&descSz)];
}
											 
- (Float64) sampleRateForScope:(AudioUnitScope)	scope
						   bus:(AudioUnitElement) busNum
{
	AudioStreamBasicDescription desc;
	[self getStreamFormatForScope:scope bus:busNum formatDescription:&desc];
	return desc.mSampleRate;
}

- (AUChannelInfo) supportedChannels
{
	AUChannelInfo desc;
	UInt32 descSz = sizeof(AUChannelInfo);
	memset(&desc, 0, descSz);
	[self registerResult:AudioUnitGetProperty(_audioUnit, 
		kAudioUnitProperty_SupportedNumChannels, kAudioUnitScope_Global,0,&desc,&descSz)];
	return desc;
}

- (OSStatus) setMaxCPULoad:(Float32)load
{
	return [self setProperty:kAudioUnitProperty_CPULoad 
		forScope:kAudioUnitScope_Global element:0 toFloat32Value:load];
}

- (Float32) maxCPULoad
{
	return [self Float32Property:kAudioUnitProperty_CPULoad 
		forScope:kAudioUnitScope_Global element:0];
}

- (OSStatus) setRenderQuality:(UInt32)renderQuality
{
	return [self setProperty:kAudioUnitProperty_RenderQuality forScope:kAudioUnitScope_Global
		element:0 toUInt32Value:renderQuality];
}

- (UInt32) renderQuality
{
	return [self UInt32Property:kAudioUnitProperty_RenderQuality 
		forScope:kAudioUnitScope_Global element:0];
}

- (OSStatus) setHostCallback:(HostCallbackInfo)info
{
	return [self setProperty:kAudioUnitProperty_HostCallbacks forScope:kAudioUnitScope_Global 
		element:0 toValue:&info size:sizeof(HostCallbackInfo)];
}

- (OSStatus) setMaxFramesPerSlice:(UInt32)maxFrames
{
	return [self setProperty:kAudioUnitProperty_MaximumFramesPerSlice forScope:kAudioUnitScope_Global
		element:0 toUInt32Value:maxFrames];
}

- (UInt32) maxFramesPerSlice
{
	return [self UInt32Property:kAudioUnitProperty_MaximumFramesPerSlice 
		forScope:kAudioUnitScope_Global element:0];
}

- (OSStatus) setExternalBuffer:(AudioUnitExternalBuffer)buff
{
	return [self setProperty:kAudioUnitProperty_SetExternalBuffer forScope:kAudioUnitScope_Global
		element:0 toValue:&buff size:sizeof(AudioUnitExternalBuffer)];
}

- (OSStatus) useDefaultBuffer
{
	AudioUnitExternalBuffer buff;
	buff.buffer = 0;
	buff.size   = 0;
	return [self setExternalBuffer:buff];
}

- (OSStatus) setRenderCallback:(AURenderCallback)callback forElement:(AudioUnitElement)elem
	withRefCon:(void*)refCon
{
	AURenderCallbackStruct rcb;
	rcb.inputProc = callback;
	rcb.inputProcRefCon = refCon;
					  
	OSStatus ret = [self setProperty:kAudioUnitProperty_SetRenderCallback 
		forScope:kAudioUnitScope_Input element:elem toValue:&rcb size:sizeof(AURenderCallbackStruct)];
		
	if((ret == noErr) && callback)
		_hasRenderCallback = YES;
		
	return ret;
}

- (BOOL) hasRenderCallback
{
	return _hasRenderCallback;
}

- (OSStatus) removeRenderCallbackForElement:(AudioUnitElement)elem
{
	if(_hasRenderCallback) {
		if([self setRenderCallback:0 forElement:elem withRefCon:0] == noErr) {
			_hasRenderCallback = NO;
			return noErr;
		}
		return [self lastResult];
	}
	return noErr;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
- (OSStatus) connectInput:(unsigned)inp fromAudioUnit:(ArkAudioUnit*)au port:(unsigned)outp
{
	if(inp > [self busCountForScope:kAudioUnitScope_Input])
		return [self registerResult:-1];
		
	if([self registerResult:AUGraphConnectNodeInput(
		[ArkAudioUnit graph],
		[au audioNodeInstance],
		outp,
		[self audioNodeInstance],
		inp)] == noErr)
	{
		Boolean res;
		[self registerResult:AUGraphUpdate([ArkAudioUnit graph], &res)];
	}
	return [self lastResult];
}

- (OSStatus) disconnectInput:(unsigned)port
{
	if([self registerResult:AUGraphDisconnectNodeInput(
		[ArkAudioUnit graph],
		[self audioNodeInstance],
		port)] == noErr)
	{
		Boolean res;
		[self registerResult:AUGraphUpdate([ArkAudioUnit graph], &res)];
	}
	return [self lastResult];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Presets
//
- (NSArray*) presets
{
	return _presets;
}

- (OSStatus) selectPreset:(AUPreset)preset
{
	return [self setProperty:kAudioUnitProperty_CurrentPreset forScope:kAudioUnitScope_Global
		element:0 toValue:&preset size:sizeof(preset)];
}

- (OSStatus) selectPresetAtIndex:(unsigned)index
{
	if([_presets count] > index)
		 return [self selectPreset:*((AUPreset*)[_presets objectAtIndex:index])];
	else return -1;
}

- (OSStatus) savePreset:(NSString*)name toFile:(NSString*)filePath
{
	NSDictionary* preset = [self savePreset:name];
	if(preset) {
		[preset writeToFile:filePath atomically:YES];
		return noErr;
	}
	else return [self lastResult];
}

- (NSDictionary*) savePreset:(NSString*)name
{

// TODO: If there is no name passed, then we will store a generic preset.
//	if(name) {
//		AUPreset userPreset;
//		userPreset.presetNumber = -1; // This indicates User preset.
//		userPreset.presetName = (CFStringRef)[name cString];
//		if([self setProperty:kAudioUnitProperty_PresentPreset forScope:0
//			element:0 toValue:&userPreset size:sizeof(userPreset)] != noErr) return [self lastResult];
//	}
						
	CFPropertyListRef plist;
    UInt32 size = sizeof(CFPropertyListRef*);
    OSStatus status = AudioUnitGetProperty(_audioUnit,
		kAudioUnitProperty_ClassInfo,
		kAudioUnitScope_Global, 0,
		&plist,
		&size);
	
	if([self registerResult:status] == noErr)		
		return [(NSDictionary*)plist autorelease];
		
	else return nil;
}

- (OSStatus) loadPresetFromFile:(NSString*)filePath
{
	NSDictionary* dictionary = [NSDictionary dictionaryWithContentsOfFile:filePath]; 
    CFPropertyListRef plist = (CFPropertyListRef)dictionary;
	return [self setProperty:kAudioUnitProperty_ClassInfo forScope:kAudioUnitScope_Global element:0
		toValue:&plist size:sizeof(CFPropertyListRef)];
}

- (OSStatus) loadPresetFromDictionary:(NSDictionary*)dictionary
{
    CFPropertyListRef plist = (CFPropertyListRef)dictionary;
	return [self setProperty:kAudioUnitProperty_ClassInfo forScope:kAudioUnitScope_Global element:0
		toValue:&plist size:sizeof(CFPropertyListRef*)];
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Error reporting and Debug
//
- (OSStatus) registerResult: (OSStatus) err
{
	_lastResult = err;
	if(err != noErr) _lastError = err;
	return err;
}

- (OSStatus) lastResult
{
	return _lastResult;
}

- (NSError*) lastError
{
	return [NSError errorWithDomain:NSOSStatusErrorDomain code:_lastError userInfo:nil];
}

- (OSStatus) lastRenderError: (OSStatus*) res
{
	OSStatus ret;
	UInt32 size = sizeof(OSStatus);
	OSStatus result = AudioUnitGetProperty(_audioUnit,
		kAudioUnitProperty_LastRenderError, kAudioUnitScope_Global, 0, &ret, &size);
		
	if([self registerResult:result] != noErr) 
		return [self lastResult];
		
	if(res) *res = ret;
	return noErr;
}

@end

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Misc Helpers
//
NSData * NSDataFromComponentDescription (ComponentDescription* compDesc)
{
	if(compDesc)
		 return [NSData dataWithBytes:(unsigned char*)compDesc 
						length:sizeof(ComponentDescription)];
	else return nil;
}

@implementation NSData(AudioUnitDescriptionInterface)
- (ComponentDescription) audioUnitDescription
{
	ComponentDescription desc;
	if([self length] == sizeof(ComponentDescription)) {
		memcpy(&desc, [self bytes], sizeof(ComponentDescription));
	}
	return desc;
}
@end