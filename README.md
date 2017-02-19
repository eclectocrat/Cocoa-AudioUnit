ArkAudioUnit, a flat wrapper around AUGraph API. This code was written several years ago against an early version of CoreAudio, and was used successfully in production code without problems. I haven't reviewed the code for a long time, it may require minor changes to be compatible with the latest CoreAudio, but Apple is pretty good about maintaining primary API's intact, so it'll probably work right out the box. THIS SOFTWARE COMES WITH NO WARRANTY! USERS TAKE ON FULL RESPONSIBILITY FOR THE RESULTS OF THIS CODE AND I ACCEPT NO LIABILITY OF ANY KIND.

```
// This will catalogue all available AudioUnits on your system, and prep them for use.
ArkAudioUnitManager * unitManager = [ArkAudioUnitManager defaultManager];

if(![ArkAudioUnitManager installDefaultAUGraph]) {
    // Handle Error!
}

// This is the simple way, but if you only need certain types of unit then you can call the individual list creation
// methods (-createOutputList, -createRealtimeEffectList, etc.).
[unitManager createAllAudioUnitLists];

ArkAudioUnit * outputUnit = [unitManager createDefaultOutput];
if([outputUnit initialize] != noErr) {
    NSError * whatHappened = [outputUnit lastError];
    NSLog(@"Error initializing output unit: %@", [whatHappened localizedDescription]);
    return -1;
}
if([outputUnit startOutput] == NO) {
    // You can also use the NSError interface as above...
    const OSStatus whatHappened = [outputUnit lastResult];
    NSLog(@"Error starting output unit: %d", whatHappened);
    return -1;
}

// You can get the names of instruments from [unitManager instrumentNames]. I put them in an NSMenu so that users could
// select the instrument by name, and I could instantiate it from the menu label.
ArkAudioUnit * instrument = [unitManager createInstrumentWithName:SOME_INSTRUMENT_NAME_HERE];
[instrument initialize];

ArkAudioUnit * fx = [unitManager createRealtimeEffectWithName:SOME_FX_NAME_HERE];
[fx initialize];
[fx loadPresetFromFile:SOME_FILE_PATH];

// Connect graph.
[outputUnit connectInput:0 fromAudioUnit:fx port:0];
[fx connectInput:0 fromAudioUnit:instrument port:0];

I think that's the gist of it. To do specific things you need to be familiar with the AudioUnit framework. Saving and loading presets are supported, changing the render callback (to access a custom sampler for example) is supported, all the property and parameter stuff is supported. If you need more access you can use the -audioUnitInstance and -audioNodeInstance methods to get at the underlying stuff, and go at the CoreAudio API's directly. All the cleanup is handled automatically, so as long as you remember to alloc and retain correctly, everything should stay clean. You might want to close the AudioUnit managers lists after you've instantiated whatever units you need because it maintains a list of open (but not initialized... whew!) units internally, but that's pretty standard practice for audio unit hosts. In case of an error, the error recovery API is a little weird:

if([unit initialize] != noErr) {
    NSError * error = [unit lastError];
    // Whatever...
}

id([unit startOutput] == NO) {
    const OSStatus result = [unit lastResult];
    NSError * error = [unit lastError];
    // Hi Mom!
}
```

This was designed as a thin wrapper around AudioUnit and AUGraph, so if you understand the core Apple API's then this just adds a bit of convenience and the Cocoa Way(TM) (circa 2005!) to those same API's, and doesn't mess with the basic paradigm. Also the code is straightforward and readable, so go ahead and look in the implementation files to understand what's going on. All the CoreAudio structs that are used in this library are displayed in comments in the header files, to save you from digging into coreaudio docs.

I've just updated the code for use on my 10.6 machine, it needed a few tweaks to the pascal string management (yuck!), but was otherwise ok.

Questions and comments are welcome. Good Luck! 
