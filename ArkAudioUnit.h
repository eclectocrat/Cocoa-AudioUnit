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

#import  <Foundation/Foundation.h>
#include <AudioUnit/AudioUnit.h>
#include <AudioToolbox/AUGraph.h>

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
@interface ArkAudioUnit : NSObject<NSCoding>
{
	ComponentDescription _auDesc;
	Component _component;
	AudioUnit _audioUnit;
	AUNode	  _audioNode;
	
	NSString *	_name;
	NSString *	_info;
	NSArray  *	_presets;
	
	BOOL _isOpen;
	BOOL _initialized;
	BOOL _hasRenderCallback;
	
	OSStatus _lastResult;
	OSStatus _lastError;
	
@public
	NSMutableDictionary * additions;
}
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
+ (void)	setGraph:(AUGraph)graph;
+ (AUGraph)	graph;
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
+ (ArkAudioUnit*)	audioUnitWithComponent:(Component)au;
+ (ArkAudioUnit*)	audioUnitWithDescription:(ComponentDescription)desc;
+ (ArkAudioUnit*)	audioUnitWithType:(OSType)type subType:(OSType)subtype manufacturer:(OSType)man;

- (id)	initWithComponent:(Component)au;
- (id)	initWithDescription:(ComponentDescription)desc;
- (id)	initWithType:(OSType)type subType:(OSType)subtype manufacturer:(OSType)man;

///
/// duplicate    
///		Returns a copy of this AudioUnit, including state. This is a non-NSCopying method to avoid 
///		accidental copying (in NSCell for instance), which could be very expensive.
/// @return A copy of self
///
- (id)	duplicate;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Information
//
- (Component)				audioUnit;
- (ComponentDescription)	audioUnitDescription;
- (AudioUnit)				audioUnitInstance;
- (AUNode)					audioNodeInstance;

///
/// info
///		Returns an information string, generally useful for debugging.
///
- (NSString*)	info;
- (NSString*)	name;
- (void)		setName:(NSString*)newName;
- (BOOL)		isOutput;
- (BOOL)		isInstrument;
- (BOOL)		isMixer;
- (BOOL)		isEffect;
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
///
/// open
///		@note AudioUnits are opened, but not initialized by default.
/// @return noErr if successful
///
- (OSStatus) open;
///
/// close
///		@note AudioUnits are automatically closed on destruction, if you wish to close but not
///		discard an AudioUnit, consider -uninitialize instead.
///
- (void)		close;
- (BOOL)		isOpen;
- (OSStatus)	initialize;
- (void)		uninitialize;
- (BOOL)		isInitialized;
- (void)		reset;
///
/// stopOutput
///		@note only works with output units.
///
- (BOOL) startOutput;
///
/// stopOutput
///		@note only works with output units.
///
- (BOOL) stopOutput;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Parameters
//
- (OSStatus)	setParameter:(AudioUnitParameterID)param forScope:(AudioUnitScope)scope 
					 element:(AudioUnitElement)elem toValue:(Float32)val;

- (Float32)		parameter:(AudioUnitParameterID)param forScope:(AudioUnitScope)scope 
				  element:(AudioUnitElement)elem;
			   
- (OSStatus)	setInputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem 
					      toValue:(Float32) val;

- (Float32)		inputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem;

- (OSStatus)	setOutputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem 
					       toValue:(Float32) val;

- (Float32)		outputParameter:(AudioUnitParameterID)param element:(AudioUnitElement)elem;		
///
/// parameterList
///	@return An array of NSNumbers. Cast from intValue to AudioUnitParameterID.
///
- (NSArray*) parameterList;
///
/// parameterInfo:forScope:
///		@code
///		struct AudioUnitParameterInfo {
///			char                    name[60];
///			CFStringRef             cfNameString;
///			AudioUnitParameterUnit  unit;
///			Float32                 minValue;
///			Float32                 maxValue;
///			Float32                 defaultValue;
///			UInt32                  flags;
///		};
///		@endcode
///
- (OSStatus) getParameterInfo:(AudioUnitParameterID)	paramID
					 forScope:(AudioUnitScope)			scope
				   infoStruct:(AudioUnitParameterInfo*) pinfo;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
/// Properties
///
- (OSStatus)	setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toValue:(void*)val size:(UInt32)size;
				 
- (OSStatus)	setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toUInt32Value:(UInt32)val;
				 
- (OSStatus)	setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toFloat32Value:(Float32)val;
				 
- (OSStatus)	setProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem toFloat64Value:(Float64)val;
				 
- (OSStatus)	getProperty:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				 element:(AudioUnitElement)elem buffer:(void*)buf;
			  
- (UInt32)		UInt32Property:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				  element:(AudioUnitElement)elem;
					
- (Float32)		Float32Property:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
					element:(AudioUnitElement)elem;
					 
- (Float64)		Float64Property:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
					element:(AudioUnitElement)elem;
					 
- (UInt32)		propertySize:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
				element:(AudioUnitElement)elem;
				  
- (BOOL)		isPropertyWritable:(AudioUnitPropertyID)prop forScope:(AudioUnitScope)scope
					element:(AudioUnitElement)elem;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Specific Properties
//
- (OSStatus)	setBypassing:(BOOL)bypass;
- (BOOL)		isBypassing;
- (Float64)		latency;
- (Float64)		tailTime;

// These are for kAudioUnitScope_Input, kAudioUnitScope_Output only.
- (OSStatus)	setBusCount:(UInt32)busCount forScope:(AudioUnitScope)scope;
- (UInt32)		busCountForScope:(AudioUnitScope)scope;
- (BOOL)		isBusCountWritableForScope:(AudioUnitScope)scope;
///
/// @defgroup streamDesc Stream Description
/// @code
/// struct AudioStreamBasicDescription
/// {
/// 	Float64	mSampleRate;		//	the native sample rate of the audio stream
/// 	UInt32	mFormatID;			//	the specific encoding type of audio stream
/// 	UInt32	mFormatFlags;		//	flags specific to each format
/// 	UInt32	mBytesPerPacket;	//	the number of bytes in a packet
/// 	UInt32	mFramesPerPacket;	//	the number of frames in each packet
/// 	UInt32	mBytesPerFrame;		//	the number of bytes in a frame
/// 	UInt32	mChannelsPerFrame;	//	the number of channels in each frame
/// 	UInt32	mBitsPerChannel;	//	the number of bits in each channel
///		UInt32	mReserved;			//	reserved, pads the structure out to force 8 byte alignment
/// };
/// @endcode
///
- (OSStatus) setStreamFormat:(AudioStreamBasicDescription*)desc 
					forScope:(AudioUnitScope)			   scope 
						 bus:(AudioUnitElement)			   busNum;

- (OSStatus) getStreamFormatForScope:(AudioUnitScope) scope 
								 bus:(AudioUnitElement)  busNum
				   formatDescription:(AudioStreamBasicDescription*)desc;
											 
- (Float64)	sampleRateForScope:(AudioUnitScope)	 scope
						   bus:(AudioUnitElement)busNum;
///
/// supportedChannels
///		@code
///		struct AUChannelInfo {
///			SInt16 inChannels;  // kAudioUnitScope_Input
///			SInt16 outChannels; // kAudioUnitScope_Output
///		};
///		@endcode
///
- (AUChannelInfo)	supportedChannels;
- (OSStatus)		setMaxCPULoad:(Float32)load;
- (Float32)			maxCPULoad;
///
/// setRenderQuality:
///		Range for renderQuality is 0-127.
///
- (OSStatus) setRenderQuality:(UInt32)renderQuality;
///
/// renderQuality
///		Range for renderQuality is 0-127.
///
- (UInt32) renderQuality;
///
/// setHostCallback:
///		@code
///		struct HostCallbackInfo {
///			void *								hostUserData;   // MUST be non-null
///			HostCallback_GetBeatAndTempo			beatAndTempoProc;
///			HostCallback_GetMusicalTimeLocation   musicalTimeLocationProc;
///		};
///
///		typedef OSStatus (*HostCallback_GetBeatAndTempo)(
///			void *     inHostUserData,
///			Float64 *  outCurrentBeat,
///			Float64 *  outCurrentTempo);
///
///		typedef OSStatus (*HostCallback_GetMusicalTimeLocation)(
///			void *     inHostUserData,
///			UInt32 *   outDeltaSampleOffsetToNextBeat,
///			Float32 *  outTimeSig_Numerator,
///			UInt32 *   outTimeSig_Denominator,
///			Float64 *  outCurrentMeasureDownBeat);
///		@endcode
///
- (OSStatus)	setHostCallback:(HostCallbackInfo)info;
- (OSStatus)	setMaxFramesPerSlice:(UInt32)maxFrames;
- (UInt32)		maxFramesPerSlice;
///
/// setExternalBuffer:
///		@code
///		struct AudioUnitExternalBuffer {
///			Byte *  buffer;
///			UInt32  size;
///		};
///		@endcode
///
- (OSStatus) setExternalBuffer:(AudioUnitExternalBuffer)buff;
- (OSStatus) useDefaultBuffer;
///
/// setRenderCallback:withRefCon:
///		@code
///		OSStatus renderCallback (
///			void							*inRefCon, 
///			AudioUnitRenderActionFlags      *ioActionFlags,
///			const AudioTimeStamp            *inTimeStamp, 
///			UInt32                          inBusNumber,
///			UInt32                          inNumFrames, 
///			AudioBufferList                 *ioData)
///		@endcode
///
- (OSStatus) setRenderCallback:(AURenderCallback)callback forElement:(AudioUnitElement)elem
	withRefCon:(void*)refCon;

- (BOOL) hasRenderCallback;

- (OSStatus) removeRenderCallbackForElement:(AudioUnitElement)elem;
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Simple AUGraph connection/disconnection. Automatically updates graph.
//
- (OSStatus)	connectInput:(unsigned)inp fromAudioUnit:(ArkAudioUnit*)au port:(unsigned)outp;
- (OSStatus)	disconnectInput:(unsigned)port;
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Presets and Persistence
//
- (NSArray*)		presets;
- (OSStatus)		selectPreset:(AUPreset)preset;
- (OSStatus)		selectPresetAtIndex:(unsigned int)index;
- (OSStatus)		savePreset:(NSString*)name toFile:(NSString*)filePath;
- (NSDictionary*)	savePreset:(NSString*)name;
- (OSStatus)		loadPresetFromFile:(NSString*)filePath;
- (OSStatus)		loadPresetFromDictionary:(NSDictionary*)dictionary;

////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Error reporting and Debug
//
- (OSStatus) registerResult:(OSStatus)err;
- (OSStatus) lastResult;
- (NSError*) lastError;
- (OSStatus) lastRenderError:(OSStatus*)res;

@end
////////////////////////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////////////////////////
// Misc Helpers
//
extern NSData * NSDataFromComponentDescription (ComponentDescription*);

@interface NSData(AudioUnitDescriptionInterface)
- (ComponentDescription) audioUnitDescription;
@end