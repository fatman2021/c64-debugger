#ifndef _C64DEBUGINTERFACEVICE_H_
#define _C64DEBUGINTERFACEVICE_H_

#include "C64DebugInterface.h"
#include "ViceWrapper.h"

//HAVE_NETWORK  ?

enum shift_type {
	NO_SHIFT = 0,             /* Key is not shifted. */
	VIRTUAL_SHIFT = (1 << 0), /* The key needs a shift on the real machine. */
	LEFT_SHIFT = (1 << 1),    /* Key is left shift. */
	RIGHT_SHIFT = (1 << 2),   /* Key is right shift. */
	ALLOW_SHIFT = (1 << 3),   /* Allow key to be shifted. */
	DESHIFT_SHIFT = (1 << 4), /* Although SHIFT might be pressed, do not
							   press shift on the real machine. */
	ALLOW_OTHER = (1 << 5),   /* Allow another key code to be assigned if
							   SHIFT is pressed. */
	SHIFT_LOCK = (1 << 6),    /* Key is shift lock. */
	
	ALT_MAP  = (1 << 8)       /* Key is used for an alternative keyboard
							   mapping */
};


class CViceAudioChannel;

class C64DebugInterfaceVice : public C64DebugInterface
{
public:
	C64DebugInterfaceVice(CViewC64 *viewC64, uint8 *c64memory, bool patchKernalFastBoot);
	~C64DebugInterfaceVice();
	
	virtual void InitKeyMap(C64KeyMap *keyMap);

	CImageData *screen;
	
	CViceAudioChannel *viceAudioChannel;
	
	int screenHeight;
	
	int modelType;
	virtual int GetC64ModelType();

	virtual int GetEmulatorType();
	virtual CSlrString *GetEmulatorVersionString();
	virtual void RunEmulationThread();
	
	virtual uint8 *GetCharRom();

	volatile uint8 machineType;
	virtual uint8 GetC64MachineType();

	virtual int GetC64ScreenSizeX();
	virtual int GetC64ScreenSizeY();
	
	virtual CImageData *GetC64ScreenImageData();

	virtual void Reset();
	virtual void HardReset();
	virtual void DiskDriveReset();

	//
	virtual void KeyboardDown(uint32 mtKeyCode);
	virtual void KeyboardUp(uint32 mtKeyCode);
	
	virtual void JoystickDown(int port, uint32 axis);
	virtual void JoystickUp(int port, uint32 axis);
	
	virtual void KeyboardDownWithJoystickCheck(uint32 mtKeyCode);
	virtual void KeyboardUpWithJoystickCheck(uint32 mtKeyCode);

	//
	virtual int GetC64CpuPC();
	virtual int GetDrive1541PC();
	virtual void GetC64CpuState(C64StateCPU *state);
	virtual void GetDrive1541CpuState(C64StateCPU *state);
	virtual void GetVICState(C64StateVIC *state);

	virtual void GetDrive1541State(C64StateDrive1541 *state);

	virtual void InsertD64(CSlrString *path);
	virtual void DetachDriveDisk();

	virtual bool GetSettingIsWarpSpeed();
	virtual void SetSettingIsWarpSpeed(bool isWarpSpeed);
	virtual bool GetSettingUseKeyboardForJoystick();
	virtual void SetSettingUseKeyboardForJoystick(bool isJoystickOn);
	virtual void SetKeyboardJoystickPort(uint8 joystickPort);

	virtual void GetSidTypes(std::vector<CSlrString *> *sidTypes);
	virtual void SetSidType(int sidType);
	
	// samplingMethod: Fast=0, Interpolating=1, Resampling=2, Fast Resampling=3
	virtual void SetSidSamplingMethod(int samplingMethod);
	// emulateFilters: no=0, yes=1
	virtual void SetSidEmulateFilters(int emulateFilters);
	// passband: 0-90
	virtual void SetSidPassBand(int passband);
	// filterBias: -500 500
	virtual void SetSidFilterBias(int filterBias);

	// 0=none, 1=stereo, 2=triple
	virtual void SetSidStereo(int stereoMode);
	virtual void SetSidStereoAddress(uint16 sidAddress);
	virtual void SetSidTripleAddress(uint16 sidAddress);

	virtual void GetC64ModelTypes(std::vector<CSlrString *> *modelTypeNames, std::vector<int> *modelTypeIds);
	virtual void SetC64ModelType(int modelType);
	virtual void SetEmulationMaximumSpeed(int maximumSpeed);

	bool isJoystickEnabled;
	uint8 joystickPort;
	
	virtual void SetVSPBugEmulation(bool isVSPBugEmulation);

	virtual void SetByteC64(uint16 addr, uint8 val);
	virtual void SetByteToRamC64(uint16 addr, uint8 val);
	virtual uint8 GetByteC64(uint16 addr);
	virtual uint8 GetByteFromRamC64(uint16 addr);
	virtual void MakeJmpC64(uint16 addr);
	virtual void MakeJmpNoResetC64(uint16 addr);
	virtual void MakeJsrC64(uint16 addr);
	
	
	virtual void MakeBasicRunC64();
	
	///
	virtual void SetStackPointerC64(uint8 val);
	virtual void SetRegisterAC64(uint8 val);
	virtual void SetRegisterXC64(uint8 val);
	virtual void SetRegisterYC64(uint8 val);
	virtual void SetRegisterPC64(uint8 val);

	///
	virtual void SetStackPointer1541(uint8 val);
	virtual void SetRegisterA1541(uint8 val);
	virtual void SetRegisterX1541(uint8 val);
	virtual void SetRegisterY1541(uint8 val);
	virtual void SetRegisterP1541(uint8 val);

	virtual void SetByte1541(uint16 addr, uint8 val);
	virtual void SetByteToRam1541(uint16 addr, uint8 val);
	virtual uint8 GetByte1541(uint16 addr);
	virtual uint8 GetByteFromRam1541(uint16 addr);
	virtual void MakeJmp1541(uint16 addr);
	virtual void MakeJmpNoReset1541(uint16 addr);

	// memory access for memory map
	virtual void GetWholeMemoryMapC64(uint8 *buffer);
	virtual void GetWholeMemoryMapFromRamC64(uint8 *buffer);
	virtual void GetWholeMemoryMap1541(uint8 *buffer);
	virtual void GetWholeMemoryMapFromRam1541(uint8 *buffer);

	virtual void GetMemoryC64(uint8 *buffer, int addrStart, int addrEnd);
	virtual void GetMemoryFromRamC64(uint8 *buffer, int addrStart, int addrEnd);
	virtual void GetMemoryDrive1541(uint8 *buffer, int addrStart, int addrEnd);
	virtual void GetMemoryFromRamDrive1541(uint8 *buffer, int addrStart, int addrEnd);

	virtual void FillC64Ram(uint16 addr, uint16 size, uint8 value);

	virtual void GetVICColors(uint8 *cD021, uint8 *cD022, uint8 *cD023, uint8 *cD025, uint8 *cD026, uint8 *cD027, uint8 *cD800);
	virtual void GetVICSpriteColors(uint8 *cD021, uint8 *cD025, uint8 *cD026, uint8 *spriteColors);
	virtual void GetCBMColor(uint8 colorNum, uint8 *r, uint8 *g, uint8 *b);
	virtual void GetFloatCBMColor(uint8 colorNum, float *r, float *g, float *b);

	virtual bool LoadFullSnapshot(CByteBuffer *snapshotBuffer);
	virtual void SaveFullSnapshot(CByteBuffer *snapshotBuffer);
	
	virtual bool LoadFullSnapshot(char *filePath);
	virtual void SaveFullSnapshot(char *filePath);

	virtual void SetDebugMode(uint8 debugMode);
	virtual uint8 GetDebugMode();
	
	virtual bool IsCpuJam();
	virtual void ForceRunAndUnJamCpu();

	virtual void AttachCartridge(CSlrString *filePath);
	virtual void DetachCartridge();
	virtual void CartridgeFreezeButtonPressed();
	virtual void GetC64CartridgeState(C64StateCartridge *cartridgeState);

	//
	virtual void SetVicRegister(uint8 registerNum, uint8 value);
	virtual u8 GetVicRegister(uint8 registerNum);

	virtual void SetVicRecordStateMode(uint8 recordMode);

	// render states
	virtual void RenderStateVIC(vicii_cycle_state_t *viciiState,
								float posX, float posY, float posZ, bool isVertical, bool showSprites, CSlrFont *fontBytes, float fontSize,
								std::vector<CImageData *> *spritesImageData, std::vector<CSlrImage *> *spritesImages, bool renderDataWithColors);
	void PrintVicInterrupts(uint8 flags, char *buf);
	void UpdateVICSpritesImages(vicii_cycle_state_t *viciiState,
								std::vector<CImageData *> *spritesImageData,
								std::vector<CSlrImage *> *spritesImages, bool renderDataWithColors);

	virtual void RenderStateDrive1541(float posX, float posY, float posZ, CSlrFont *fontBytes, float fontSize,
									  bool renderVia1, bool renderVia2, bool renderDriveLed, bool isVertical);
	virtual void RenderStateCIA(float px, float py, float posZ, CSlrFont *fontBytes, float fontSize, int ciaId);
	virtual void RenderStateSID(uint16 sidBase, float posX, float posY, float posZ, CSlrFont *fontBytes, float fontSize);
	void PrintSidWaveform(uint8 wave, char *buf);
	
	// SID
	virtual void SetSIDMuteChannels(int sidNumber, bool mute1, bool mute2, bool mute3, bool muteExt);
	virtual void SetSIDReceiveChannelsData(int sidNumber, bool isReceiving);

	// memory
	uint8 *c64memory;
	
	virtual void SetPatchKernalFastBoot(bool isPatchKernal);
	virtual void SetRunSIDWhenInWarp(bool isRunningSIDInWarp);
	
	//
	virtual void SetRunSIDEmulation(bool isSIDEmulationOn);
	virtual void SetAudioVolume(float volume);
};

extern C64DebugInterfaceVice *debugInterfaceVice;

void ViceKeyMapInitDefault();

#endif

