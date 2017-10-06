extern "C" {
#include "vice.h"
#include "main.h"
#include "types.h"
#include "viciitypes.h"
#include "vicii.h"
#include "c64mem.h"
}

#include "CViewC64VicDisplay.h"
#include "VID_GLViewController.h"
#include "CGuiMain.h"
#include "VID_ImageBinding.h"
#include "CViewC64.h"
#include "SYS_KeyCodes.h"
#include "C64DebugInterface.h"
#include "C64SettingsStorage.h"
#include "CViewC64Screen.h"
#include "CSlrFont.h"
#include "CGuiLabel.h"
#include "CViewC64StateVIC.h"
#include "CViewMemoryMap.h"
#include "CViewDataDump.h"
#include "CViewDisassemble.h"
#include "CViewC64VicControl.h"
#include "C64CharMulti.h"
#include "C64CharHires.h"
#include "C64VicDisplayCanvasBlank.h"
#include "C64VicDisplayCanvasHiresText.h"
#include "C64VicDisplayCanvasMultiText.h"
#include "C64VicDisplayCanvasExtendedText.h"
#include "C64VicDisplayCanvasHiresBitmap.h"
#include "C64VicDisplayCanvasMultiBitmap.h"

#include "C64KeyboardShortcuts.h"


// docs: http://codebase64.org/doku.php?id=base:vicii_memory_organizing


// screen is:
//
// X from 0x000 to 0x1F7 (max 0x1F8=0)   | interior is: 0x88   0x1C8  | visible is: 0x068 0x1E8
// Y from 0x000 to 0x137 (max 0x138=0)   |              0x32   0x0FB  |             0x010 0x120

//

//    frame  |visible   interior  visible|  frame
// X: 0x000  | 0x068  0x088 0x1C8  0x1E8 |  0x1F8
//        0             136   456             504
// Y: 0x000  | 0x010  0x032 0x0FA  0x120 |  0x138
//        0              50   251             312



CViewC64VicDisplay::CViewC64VicDisplay(GLfloat posX, GLfloat posY, GLfloat posZ, GLfloat sizeX, GLfloat sizeY,
									   C64DebugInterface *debugInterface)
: CGuiView(posX, posY, posZ, sizeX, sizeY)
{
	this->name = "CViewC64VicDisplay";
	
	this->debugInterface = debugInterface;
	
	viewFrame = NULL;
//	viewFrame = new CGuiViewFrame(this, new CSlrString("VIC Display"));
//	this->AddGuiElement(viewFrame);

	// view with buttons to control this Vic Display
	viewVicControl = NULL;
	
//	//	m_ecm = (video_mode & 4) >> 2;  // 0 standard, 1 extended
//	//	m_bmm = (video_mode & 2) >> 1;  // 0 text, 1 bitmap
//	//	m_mcm = video_mode & 1;         // 0 hires, 1 multi
//
	
	this->autoScrollMode = AUTOSCROLL_DISASSEMBLE_UNKNOWN;
	
	font = viewC64->fontCBMShifted;
	fontScale = 0.8;
	fontHeight = font->GetCharHeight('@', fontScale) + 2;
	
	// vic display frame
	displayFrameRasterX = 0.0f;
	displayFrameRasterY = 0.0f;
	displayFrameRasterSizeX = 320.0f;
	displayFrameRasterSizeY = 200.0f;

	renderDisplayFrame = false;

	updateViewAspectRatio = false;
	
	// test:
//	displayFrameRasterX = 50.0f;
//	displayFrameRasterY = 50.0f;
//	displayFrameRasterSizeX = 120.0f;
//	displayFrameRasterSizeY = 100.0f;
	
	// 320x200
	
	int w = 512;
	int h = 512;
	imageDataScreen = new CImageData(w, h, IMG_TYPE_RGBA);
	imageDataScreen->AllocImage(false, true);
	
	//	for (int x = 0; x < w; x++)
	//	{
	//		for (int y = 0; y < h; y++)
	//		{
	//			imageData->SetPixelResultRGBA(x, y, x % 255, y % 255, 0, 255);
	//		}
	//	}
	
	
	imageScreen = new CSlrImage(true, false);
	imageScreen->LoadImage(imageDataScreen, RESOURCE_PRIORITY_STATIC, false);
	imageScreen->resourceType = RESOURCE_TYPE_IMAGE_DYNAMIC;
	imageScreen->resourcePriority = RESOURCE_PRIORITY_STATIC;
	VID_PostImageBinding(imageScreen, NULL);
	
//	imageDataScreen = new CImageData(512, 512, IMG_TYPE_RGBA);
//	imageDataScreen->AllocImage(false, true);

	
	// character mode screen texture boundaries
	screenTexEndX = (float)320.0f / 512.0f;
	screenTexEndY = 1.0f - (float)200.0f / 512.0f;

	this->showGridLines = true; //false;

	this->showDisplayBorderType = VIC_DISPLAY_SHOW_BORDER_FULL;		//VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA
	this->showSpritesGraphics = true;
	this->showSpritesFrames = true;

	this->isCursorLocked = false;
	
	rasterCursorPosX = rasterCursorPosY = -9999;
	
	// init all types of canvas
	this->canvasBlank = new C64VicDisplayCanvasBlank(this);
	this->canvasHiresText = new C64VicDisplayCanvasHiresText(this);
	this->canvasMultiText = new C64VicDisplayCanvasMultiText(this);
	this->canvasExtendedText = new C64VicDisplayCanvasExtendedText(this);
	this->canvasHiresBitmap = new C64VicDisplayCanvasHiresBitmap(this);
	this->canvasMultiBitmap = new C64VicDisplayCanvasMultiBitmap(this);
	
	currentCanvas = canvasMultiBitmap;
	
	// init display default vars
	this->SetDisplayPosition(posX, posY, 1.0f, false);
	
	this->scale = 1.0f;
	
	showRasterCursor = true;
	
	canScrollDisassemble = true;
	
	currentVicMode = 0;
	
//	/// debug
//	int rasterNum = 0x003A;
//	C64AddrBreakpoint *addrBreakpoint = new C64AddrBreakpoint(rasterNum);
//	debugInterface->breakpointsC64Raster[rasterNum] = addrBreakpoint;
//	
//	debugInterface->breakOnC64Raster = true;

	InitRasterColorsFromScheme();
	
	applyScrollRegister = false;
	
	backupRenderDataWithColors = false;
	
	arrowKeyDown = false;
	foundMemoryCellPC = false;
	
	// keyboard shortcut zones for this view
	shortcutZones.push_back(KBZONE_DISASSEMBLE);
	//shortcutZones.push_back(KBZONE_MEMORY);

	this->autoScrollMode = AUTOSCROLL_DISASSEMBLE_UNKNOWN;

}

void CViewC64VicDisplay::SetVicControlView(CViewC64VicControl *vicControl)
{
	this->viewVicControl = vicControl;
}


// TODO: move this to CGuiView and generalize
void CViewC64VicDisplay::SetAutoScrollMode(int newMode)
{
	if (this->autoScrollMode == newMode)
		return;
	
	LOGD("CViewC64VicDisplay::SetAutoScrollMode: %d", newMode);
	this->autoScrollMode = newMode;
	
	if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_RASTER_PC)
	{
		if (canScrollDisassemble == true)
		{
			if (viewC64->viewC64Disassemble->changedByUser == false)
			{
				viewC64->viewC64Disassemble->isTrackingPC = true;
				viewC64->viewC64Disassemble->changedByUser = false;
			}
		}
	}
	else if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_BITMAP_ADDRESS)
	{
		if (viewC64->viewC64Disassemble->changedByUser == false)
		{
			ScrollMemoryAndDisassembleToRasterPosition(rasterCursorPosX, rasterCursorPosY, true);
		}
	}
	else if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_TEXT_ADDRESS)
	{
		if (viewC64->viewC64Disassemble->changedByUser == false)
		{
			ScrollMemoryAndDisassembleToRasterPosition(rasterCursorPosX, rasterCursorPosY, true);
		}
	}
	else if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_COLOUR_ADDRESS)
	{
		if (viewC64->viewC64Disassemble->changedByUser == false)
		{
			ScrollMemoryAndDisassembleToRasterPosition(rasterCursorPosX, rasterCursorPosY, true);
		}
	}
	
	// update UI
	if (viewVicControl != NULL)
	{
		viewVicControl->SetAutoScrollModeUI(autoScrollMode);
	}
}

bool CViewC64VicDisplay::IsInside(GLfloat x, GLfloat y)
{
	if (viewFrame != NULL)
	{
		return viewFrame->IsInside(x, y);
	}

	return CGuiView::IsInside(x, y);
	
}

void CViewC64VicDisplay::SetShowDisplayBorderType(u8 borderType)
{
	this->showDisplayBorderType = borderType;
	
	LOGD("SetShowDisplayBorderType: %d", this->showDisplayBorderType);
	
	// update positions based on visibility of the border
	this->SetPosition(this->posX, this->posY);
}


void CViewC64VicDisplay::SetPosition(GLfloat posX, GLfloat posY)
{
	this->SetDisplayPosition(posX, posY, scale, this->updateViewAspectRatio);
}

void CViewC64VicDisplay::SetDisplayPosition(float posX, float posY, float scale, bool updateViewAspectRatio)
{
	this->updateViewAspectRatio = updateViewAspectRatio;
	this->scale = scale;
	
	float sx, sy;
	
	if (updateViewAspectRatio == false)
	{
		if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
		{
			this->SetScreenAndDisplaySize(posX, posY, 504.0f * 0.6349 * scale, 312.0f * 0.6349 * scale);
		}
		else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
		{
			this->SetScreenAndDisplaySize(posX + 33.0f * 0.7353f * scale, posY, 384.0f * 0.7353f * scale, 272.0f * 0.7353f * scale);
		}
		else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
		{
			this->SetScreenAndDisplaySize(posX, posY, 320.0f * scale, 200.0f * scale);
		}

		sx = 320.0f * scale;
		sy = 200.0f * scale;
	}
	else
	{
		if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
		{
			sx = 504.0f * 0.6349 * scale;
			sy = 312.0f * 0.6349 * scale;
		}
		else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
		{
			sx = 384.0f * 0.7353f * scale;
			sy = 272.0f * 0.7353f * scale;
		}
		else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
		{
			sx = 320.0f * scale;
			sy = 200.0f * scale;
		}

		this->SetScreenAndDisplaySize(posX, posY, sx, sy);
	}

	CGuiView::SetPosition(posX, posY, posZ, sx, sy);

	UpdateRasterCrossFactors();
}

void CViewC64VicDisplay::SetDisplayScale(float scale)
{
	this->SetDisplayPosition(this->posX, this->posY, scale, false);
}

void CViewC64VicDisplay::SetScreenAndDisplaySize(float dPosX, float dPosY, float dSizeX, float dSizeY)
{
	//LOGD("CViewC64VicDisplay::SetScreenAndDisplaySize: %f %f %f %f", dPosX, dPosY, dSizeX, dSizeY);
	
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
	{
		// border is on, make display smaller
		//    frame  |visible   interior  visible|  frame
		// X: 0x000  | 0x068  0x088 0x1C8  0x1E8 |  0x1F8
		//        0      104    136   456    488      504
		// Y: 0x000  | 0x010  0x032 0x0FA  0x120 |  0x138
		//        0       16     50   251    288      312
		

		fullScanScreenPosX = dPosX;
		fullScanScreenPosY = dPosY;
		fullScanScreenSizeX = dSizeX;
		fullScanScreenSizeY = dSizeY;

		displayPosX = dPosX + (fullScanScreenSizeX / 504.0) * 136.0;
		displayPosY = dPosY + (fullScanScreenSizeY / 312.0) *  50.0;
		displaySizeX = fullScanScreenSizeX * (320.0 / 504.0);
		displaySizeY = fullScanScreenSizeY * (200.0 / 312.0);
		
		visibleScreenPosX = dPosX + (fullScanScreenSizeX / 504.0) * 104.0;
		visibleScreenPosY = dPosY + (fullScanScreenSizeY / 312.0) *  16.0;
		visibleScreenSizeX = fullScanScreenSizeX * (384.0 / 504.0);
		visibleScreenSizeY = fullScanScreenSizeY * (272.0 / 312.0);
		
		displayPosWithScrollX = displayPosX;
		displayPosWithScrollY = displayPosY;
		
		scrollInRasterPixelsX = 0;
		scrollInRasterPixelsY = 0;

	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		// border is on, make display smaller
		//    frame  |visible   interior  visible|  frame
		// X: 0x000  | 0x068  0x088 0x1C8  0x1E8 |  0x1F8
		//        0      104    136   456    488      504
		// Y: 0x000  | 0x010  0x032 0x0FA  0x120 |  0x138
		//        0       16     50   251    288      312
		
		
		fullScanScreenPosX = dPosX;
		fullScanScreenPosY = dPosY;
		fullScanScreenSizeX = dSizeX;
		fullScanScreenSizeY = dSizeY;
		
		float fx = 320.0f / 384.0f;
		float fy = 200.0f / 272.0f;
		
		displaySizeX = fullScanScreenSizeX * fx - 0.05f;
		displaySizeY = fullScanScreenSizeY * fy;
		
		float pixelSizeX = displaySizeX / 320.0f;
		float pixelSizeY = displaySizeY / 200.0f;

		//LOGD("pixelSizeX=%f pixelSizeY=%f", pixelSizeX, pixelSizeY);
		
		displayPosX = dPosX + (fullScanScreenSizeX-displaySizeX) / 2.0f;
		displayPosY = dPosY + pixelSizeY * 0x23;
		
		visibleScreenPosX = displayPosX - pixelSizeX * 0x20;;
		visibleScreenPosY = fullScanScreenPosY;
		visibleScreenSizeX = displaySizeX + pixelSizeX * 0x40;
		visibleScreenSizeY = fullScanScreenSizeY;
		
		displayPosWithScrollX = displayPosX;
		displayPosWithScrollY = displayPosY;
		
		scrollInRasterPixelsX = 0;
		scrollInRasterPixelsY = 0;
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
	{
		// no borders mode
		fullScanScreenPosX = dPosX;
		fullScanScreenPosY = dPosY;
		fullScanScreenSizeX = dSizeX;
		fullScanScreenSizeY = dSizeY;

		displayPosX = fullScanScreenPosX;
		displayPosY = fullScanScreenPosY;
		displaySizeX = fullScanScreenSizeX;
		displaySizeY = fullScanScreenSizeY;
		
		visibleScreenPosX = displayPosX;
		visibleScreenPosY = displayPosY;
		visibleScreenSizeX = displaySizeX;
		visibleScreenSizeY = displaySizeY;
		
		displayPosWithScrollX = displayPosX;
		displayPosWithScrollY = displayPosY;

		scrollInRasterPixelsX = 0;
		scrollInRasterPixelsY = 0;
	}
	else SYS_FatalExit("CViewC64VicDisplay::SetScreenAndDisplaySize: unknown border type: %d", showDisplayBorderType);
}

/*
void CViewC64VicDisplay::SetPosition(GLfloat posX, GLfloat posY, GLfloat posZ, float fontSize)
{
	this->fontSize = fontSize;
	
	this->SetScreenAndDisplaySize(posX, posY, fontSize * 40.0f, fontSize * 25.0f);
	
	this->scale = (fontSize * 40.0f) / 320.0f;
	
	LOGD("scale=%f", scale);
	
	CGuiView::SetPosition(posX, posY, posZ, fullScanScreenSizeX, fullScanScreenSizeY);
	
	UpdateRasterCrossFactors();
}
*/

CViewC64VicDisplay::~CViewC64VicDisplay()
{
}


// TODO: move this to Tools
void CViewC64VicDisplay::GetRasterColorScheme(int schemeNum, float splitAmount, float *r, float *g, float *b)
{
	switch(schemeNum)
	{
		default:
			// red
			*r = 1.0f - splitAmount;
			*g = splitAmount;
			*b = 0.0f;
			break;
		case 1:
			// green
			*r = splitAmount;
			*g = 1.0f - splitAmount;
			*b = 0.0f;
			break;
		case 2:
			// blue
			*r = splitAmount;
			*g = 0.0f;
			*b = 1.0f - splitAmount;
			break;
		case 3:
			// black
			*r = 0.0f;
			*g = 0.0f;
			*b = 0.0f;
			break;
		case 4:
			// dark gray
			*r = 0.25f;
			*g = 0.25f;
			*b = 0.25f;
			break;
		case 5:
			// light gray
			*r = 0.70f;
			*g = 0.70f;
			*b = 0.70f;
			break;
		case 6:
			// white
			*r = 1.0f;
			*g = 1.0f;
			*b = 1.0f;
			break;
	}

}

void CViewC64VicDisplay::InitRasterColorsFromScheme()
{
	// grid lines
	GetRasterColorScheme(c64SettingsScreenGridLinesColorScheme, 0.0f,
						 &gridLinesColorR, &gridLinesColorG, &gridLinesColorB);
	
	gridLinesColorA = c64SettingsScreenGridLinesAlpha;

	// raster long screen line
	GetRasterColorScheme(c64SettingsScreenRasterCrossLinesColorScheme, 0.0f,
						 &rasterLongScrenLineR, &rasterLongScrenLineG, &rasterLongScrenLineB);
	rasterLongScrenLineA = c64SettingsScreenRasterCrossLinesAlpha;
	
	//c64SettingsScreenRasterCrossAlpha = 0.85

	// exterior
	GetRasterColorScheme(c64SettingsScreenRasterCrossExteriorColorScheme, 0.1f,
						 &rasterCrossExteriorR, &rasterCrossExteriorG, &rasterCrossExteriorB);
	
	rasterCrossExteriorA = 0.8235f * c64SettingsScreenRasterCrossAlpha;		// 0.7
	
	// tip
	GetRasterColorScheme(c64SettingsScreenRasterCrossTipColorScheme, 0.1f,
						 &rasterCrossEndingTipR, &rasterCrossEndingTipG, &rasterCrossEndingTipB);
	
	rasterCrossEndingTipA = 0.1765f * c64SettingsScreenRasterCrossAlpha;	// 0.15
	
	// white interior cross
	GetRasterColorScheme(c64SettingsScreenRasterCrossInteriorColorScheme, 0.1f,
						 &rasterCrossInteriorR, &rasterCrossInteriorG, &rasterCrossInteriorB);

	rasterCrossInteriorA = c64SettingsScreenRasterCrossAlpha;	// 0.85
	
}

void CViewC64VicDisplay::InitGridLinesColorFromSettings()
{
	this->gridLinesColorR = c64SettingsPaintGridCharactersColorR;
	this->gridLinesColorG = c64SettingsPaintGridCharactersColorG;
	this->gridLinesColorB = c64SettingsPaintGridCharactersColorB;
	this->gridLinesColorA = c64SettingsPaintGridCharactersColorA;
	
	this->gridLinesColorR2 = c64SettingsPaintGridPixelsColorR;
	this->gridLinesColorG2 = c64SettingsPaintGridPixelsColorG;
	this->gridLinesColorB2 = c64SettingsPaintGridPixelsColorB;
	this->gridLinesColorA2 = c64SettingsPaintGridPixelsColorA;
	
	
//	viewVicDisplayMain->gridLinesColorR = 0.7f;
//	viewVicDisplayMain->gridLinesColorG = 0.7f;
//	viewVicDisplayMain->gridLinesColorB = 0.7f;
//	viewVicDisplayMain->gridLinesColorA = 1.0f;
//	
//	viewVicDisplayMain->gridLinesColorR2 = 0.5f;
//	viewVicDisplayMain->gridLinesColorG2 = 0.5f;
//	viewVicDisplayMain->gridLinesColorB2 = 0.5f;
//	viewVicDisplayMain->gridLinesColorA2 = 0.3f;
//	

}

void CViewC64VicDisplay::DoLogic()
{
	CGuiView::DoLogic();
}

// TODO: refactor to GetScreenAddressForRaster
int CViewC64VicDisplay::GetTextModeAddressForRaster(int x, int y)
{
	u16 screenBase = this->screenAddress;
	
	int charColumn = floor((float)((float)x / 8.0f));
	int charRow = floor((float)((float)y / 8.0f));
	
	int offset = charColumn + charRow * 40;
	
	return screenBase + offset;
}

// TODO: refactor to GetColorAddressForRaster
int CViewC64VicDisplay::GetColourAddressForRaster(int x, int y)
{
	u16 screenBase = 0xD800;
	
	int charColumn = floor((float)((float)x / 8.0f));
	int charRow = floor((float)((float)y / 8.0f));
	
	int offset = charColumn + charRow * 40;
	
	return screenBase + offset;
}


int CViewC64VicDisplay::GetBitmapModeAddressForRaster(int x, int y)
{
	u16 bitmapBase = this->bitmapAddress;
	
	int charColumn = floor((float)((float)x / 8.0f));
	int charRow = floor((float)((float)y / 8.0f));
	
	int pixelCharY = y % 8;
	
	int offset = charColumn*8 + charRow * 40*8 + pixelCharY;
	
	return bitmapBase + offset;
}

int CViewC64VicDisplay::GetAddressForRaster(int x, int y)
{
	if (x >= 0 && x < 320 && y >= 0 && y < 200)
	{
		
		switch (currentVicMode)
		{
			case 0:    // normal text mode
				return this->GetTextModeAddressForRaster(x, y);
			case 1:    // hires bitmap mode
				return this->GetBitmapModeAddressForRaster(x, y);
			case 2:    // extended background mode
				return this->GetTextModeAddressForRaster(x, y);
			case 4:    // multicolor text mode
				return this->GetTextModeAddressForRaster(x, y);
			case 5:    // multicolor bitmap mode
				return this->GetBitmapModeAddressForRaster(x, y);
			default:   // illegal modes (3, 6 and 7)
				return -1;
		}
	}
	
	return -1;
}

#define C64D_PHI1_TYPE_RAM		0
#define C64D_PHI1_TYPE_CHARROM	1
#define C64D_PHI1_TYPE_CART		2

extern "C" {
	unsigned char c64d_fetch_phi1_type(int addr);
	BYTE *ultimax_romh_phi1_ptr(WORD addr);
	BYTE *ultimax_romh_phi2_ptr(WORD addr);

}

// the code below has been ported from these Vice functions:

//static int doodle_vicii_save(screenshot_t *screenshot, const char *filename)
//static int doodle_vicii_text_mode_render(screenshot_t *screenshot, const char *filename)
//void vicii_screenshot(screenshot_t *screenshot)


void CViewC64VicDisplay::GetViciiPointers(vicii_cycle_state_t *viciiState,
										  u8 **screen_ptr, u8 **color_ram_ptr, u8 **chargen_ptr,
										  u8 **bitmap_low_ptr, u8 **bitmap_high_ptr,
										  u8 *colors)
{
	u16 screen_addr;            // Screen start address.
	u8 *screen_base_phi2;       // Pointer to screen memory.
	u8 *char_base;              // Pointer to character memory.
	u8 *bitmap_low_base;        // Pointer to bitmap memory (low part).
	u8 *bitmap_high_base;       // Pointer to bitmap memory (high part).
	int charset_addr, bitmap_bank;
	
	screen_addr = viciiState->vbank_phi2 + ((viciiState->regs[0x18] & 0xf0) << 6);
	screen_addr = (screen_addr & viciiState->vaddr_mask_phi2) | viciiState->vaddr_offset_phi2;
	
	charset_addr = (viciiState->regs[0x18] & 0xe) << 10;
	charset_addr = (charset_addr + viciiState->vbank_phi1);
	charset_addr &= viciiState->vaddr_mask_phi1;
	charset_addr |= viciiState->vaddr_offset_phi1;
	
	bitmap_bank = charset_addr & 0xe000;
	
	// check for UI control and adjust values
	if (this->viewVicControl)
	{
		this->viewVicControl->SetViciiPointersFromUI(&screen_addr, &charset_addr, &bitmap_bank);
	}

	///
	//LOGD("screen_addr=%04x charsetAddress=%04x bitmap_bank=%04x", screen_addr, charsetAddress, bitmap_bank);
	
	int tmp = charset_addr;
	
	bitmap_low_base = vicii.ram_base_phi1 + bitmap_bank;
	
	if (viciiState->export_ultimax_phi2) {
		if ((screen_addr & 0x3fff) >= 0x3000) {
			screen_base_phi2 = ultimax_romh_phi2_ptr((WORD)(0x1000 + (screen_addr & 0xfff)));
		} else {
			screen_base_phi2 = vicii.ram_base_phi2 + screen_addr;
		}
	} else {
		if ((screen_addr & viciiState->vaddr_chargen_mask_phi2)
			!= viciiState->vaddr_chargen_value_phi2) {
			screen_base_phi2 = vicii.ram_base_phi2 + screen_addr;
		} else {
			screen_base_phi2 = mem_chargen_rom_ptr + (screen_addr & 0xc00);
		}
	}
	
	if (viciiState->export_ultimax_phi1) {
		if ((tmp & 0x3fff) >= 0x3000) {
			char_base = ultimax_romh_phi1_ptr((WORD)(0x1000 + (tmp & 0xfff)));
		} else {
			char_base = vicii.ram_base_phi1 + tmp;
		}
		
		if (((bitmap_bank + 0x1000) & 0x3fff) >= 0x3000) {
			bitmap_high_base = ultimax_romh_phi1_ptr(0x1000);
		} else {
			bitmap_high_base = bitmap_low_base + 0x1000;
		}
	} else {
		if ((tmp & viciiState->vaddr_chargen_mask_phi1)
			!= viciiState->vaddr_chargen_value_phi1) {
			char_base = vicii.ram_base_phi1 + tmp;
		} else {
			char_base = mem_chargen_rom_ptr + (tmp & 0x0800);
		}
		
		if (((bitmap_bank + 0x1000) & viciiState->vaddr_chargen_mask_phi1)
			!= viciiState->vaddr_chargen_value_phi1) {
			bitmap_high_base = bitmap_low_base + 0x1000;
		} else {
			bitmap_high_base = mem_chargen_rom_ptr;
		}
	}
	
	//		raster_screenshot(&vicii.raster, screenshot);
	//
	//		screenshot->chipid = "VICII";
	//		screenshot->video_regs = vicii.regs;
	//		screenshot->screen_ptr = ;
	//		screenshot->chargen_ptr = char_base;
	//		screenshot->bitmap_ptr = NULL;
	//		screenshot->bitmap_low_ptr = bitmap_low_base;
	//		screenshot->bitmap_high_ptr = bitmap_high_base;
	//		screenshot->color_ram_ptr = mem_color_ram_vicii;
	
	*screen_ptr = screen_base_phi2;
	*color_ram_ptr = mem_color_ram_vicii;
	*chargen_ptr = char_base;
	*bitmap_low_ptr = bitmap_low_base;
	*bitmap_high_ptr = bitmap_high_base;
	
	for (int i = 0; i < 0x0F; i++)
	{
		colors[i] = viciiState->regs[0x20 + i] & 0x0F;
	}

	//////////////////
	this->screenAddress = screen_addr;
	this->bitmapAddress = bitmap_bank;
}

void CViewC64VicDisplay::UpdateDisplayPosFromScrollRegister(vicii_cycle_state_t *viciiState)
{
	if (applyScrollRegister)
	{
		this->scrollInRasterPixelsX = (viciiState->regs[0x16] & 0x07);
		this->scrollInRasterPixelsY = (viciiState->regs[0x11] & 0x07) - 3.0f;

		
		float xScroll = (float)(scrollInRasterPixelsX);
		float yScroll = (float)(scrollInRasterPixelsY);
		
		displayPosWithScrollX = displayPosX + xScroll * rasterScaleFactorX;
		displayPosWithScrollY = displayPosY + yScroll * rasterScaleFactorX;
		
//		LOGD("displayPosX=%3f  xScroll=%3f (%3f) displayPosWithScrollX=%3f",
//			 displayPosX, xScroll, xScroll * rasterScaleFactorX, displayPosWithScrollX);
//		LOGD("displayPosY=%3f  yScroll=%3f (%3f) displayPosWithScrollY=%3f",
//			 displayPosY, yScroll, yScroll * rasterScaleFactorY, displayPosWithScrollY);
	}
	else
	{
		displayPosWithScrollX = displayPosX;
		displayPosWithScrollY = displayPosY;
		
		this->scrollInRasterPixelsX = 0;
		this->scrollInRasterPixelsY = 0;
		
//		LOGD("displayPosX=%3f  NOSCROL=%3f (%3f) displayPosWithScrollX=%3f",
//			 displayPosX, 0.0f, 0.0f, displayPosWithScrollX);
//		LOGD("displayPosY=%3f  NOSCROL=%3f (%3f) displayPosWithScrollY=%3f",
//			 displayPosY, 0.0f, 0.0f, displayPosWithScrollY);
	}
}

void CViewC64VicDisplay::RefreshScreenStateOnly(vicii_cycle_state_t *viciiState)
{
	u8 mc;
	u8 eb;
	u8 bm;
	u8 blank;
	
	mc = (viciiState->regs[0x16] & 0x10) >> 4;
	bm = (viciiState->regs[0x11] & 0x20) >> 5;
	eb = (viciiState->regs[0x11] & 0x40) >> 6;
	
	blank = (viciiState->regs[0x11] & 0x10) >> 4;
	
	if (this->viewVicControl)
	{
		this->viewVicControl->RefreshStateButtonsUI(&mc, &eb, &bm, &blank);
	}

	// refresh texture of C64's character mode screen
	u8 *screen_ptr;
	u8 *color_ram_ptr;
	u8 *chargen_ptr;
	u8 *bitmap_low_ptr;
	u8 *bitmap_high_ptr;
	u8 colors[0x0F];
	
	this->GetViciiPointers(viciiState, &screen_ptr, &color_ram_ptr, &chargen_ptr, &bitmap_low_ptr, &bitmap_high_ptr, colors);

	UpdateDisplayPosFromScrollRegister(viciiState);
}

void CViewC64VicDisplay::RefreshScreen(vicii_cycle_state_t *viciiState)
{
	//LOGD("CViewC64VicDisplay::RefreshScreen");
	
	RefreshScreenImageData(viciiState);

	imageScreen->ReplaceImageData(imageDataScreen);

	// no need to mutex this operation:
//	debugInterface->UnlockRenderScreenMutex();
}

void CViewC64VicDisplay::RefreshScreenImageData(vicii_cycle_state_t *viciiState)
{
	//LOGD("CViewC64VicDisplay::RefreshScreen");
	
	// locking is not needed here, let's avoid too much mutex mangling
	//	debugInterface->LockRenderScreenMutex();
	
	
	/*
	 int video_mode, m_mcm, m_bmm, m_ecm, v_bank, v_vram;
	 int i, bits, bits2, charsetAddr;
	 
	 video_mode = ((vicii.regs[0x11] & 0x60) | (vicii.regs[0x16] & 0x10)) >> 4;
	 
	 m_ecm = (video_mode & 4) >> 2;  // 0 standard, 1 extended
	 m_bmm = (video_mode & 2) >> 1;  // 0 text, 1 bitmap
	 m_mcm = video_mode & 1;         // 0 hires, 1 multi
	 
	 v_bank = vicii.vbank_phi1;
	 
	 v_vram = ((vicii.regs[0x18] >> 4) * 0x0400) + vicii.vbank_phi2;
	 
	 charsetAddr = (((vicii.regs[0x18] >> 1) & 0x7) * 0x0800) + v_bank;
	 
	 u8 phi1_type = c64d_fetch_phi1_type(charsetAddr);
	 
	 LOGD("v_vram=%04x charsetAddr=%04x phi1type=%x", v_vram, charsetAddr, phi1_type);
	 */
	
	///
	
	u8 mc;
	u8 eb;
	u8 bm;
	u8 blank;
	
	mc = (viciiState->regs[0x16] & 0x10) >> 4;
	eb = (viciiState->regs[0x11] & 0x40) >> 6;
	bm = (viciiState->regs[0x11] & 0x20) >> 5;
	
	blank = (viciiState->regs[0x11] & 0x10) >> 4;
	
	// control states by UI control
	if (this->viewVicControl)
	{
		this->viewVicControl->RefreshStateButtonsUI(&mc, &eb, &bm, &blank);
	}
	
	UpdateDisplayPosFromScrollRegister(viciiState);
	
	if (!blank)
	{
		//		ui_error("Screen is blanked, no picture to save");
		//		return -1;
		
		//LOGD("blank");
		this->currentCanvas = this->canvasBlank;
		this->currentCanvas->RefreshScreen(viciiState, imageDataScreen);
		return;
	}
	
	currentVicMode = mc << 2 | eb << 1 | bm;
	
	switch (currentVicMode)
	{
		case 0:    // normal text mode
			this->currentCanvas = this->canvasHiresText;
			break;
		case 1:    // hires bitmap mode
			this->currentCanvas = this->canvasHiresBitmap;
			break;
		case 2:    // extended background mode
			this->currentCanvas = this->canvasExtendedText;
			break;
		case 4:    // multicolor text mode
			this->currentCanvas = this->canvasMultiText;
			break;
		case 5:    // multicolor bitmap mode
			this->currentCanvas = this->canvasMultiBitmap;
			break;
		default:   // illegal modes (3, 6 and 7)
			this->currentCanvas = this->canvasBlank;
			break;
	}
	
	this->currentCanvas->RefreshScreen(viciiState, imageDataScreen);
		
	// no need to mutex this operation:
	//	debugInterface->UnlockRenderScreenMutex();
}


////

void CViewC64VicDisplay::RenderFocusBorder()
{
	if (this->focusElement != NULL)
	{
		this->focusElement->RenderFocusBorder();
	}
	else
	{
		const float lineWidth = 0.7f;
		BlitRectangle(this->fullScanScreenPosX, this->fullScanScreenPosY, this->posZ, this->fullScanScreenSizeX, this->fullScanScreenSizeY, 1.0f, 0.0f, 0.0f, 0.5f, lineWidth);
	}
}



void CViewC64VicDisplay::Render()
{
	// debug
//	BlitRectangle(this->posX, this->posY, this->posZ,
//				  this->sizeX, this->sizeY, 0.1f, 0.8f, 1.0f, 1.0f, 3.0f);
	
	
	//LOGG("CViewC64VicDisplay::Render: %s", this->name);
	BlitFilledRectangle(posX, posY, posZ, sizeX, sizeY, 0, 0, 0, 0.7f);

	
	// Render the VIC Display
	VID_SetClipping(this->fullScanScreenPosX, this->fullScanScreenPosY, this->fullScanScreenSizeX, this->fullScanScreenSizeY);
	
	this->RenderDisplay();

	VID_ResetClipping();

	if (showGridLines)
	{
		this->RenderGridLines();
	}
	
	const float lineWidth = 1.25f;//0.7f;
	
	if (renderDisplayFrame)
	{
		BlitRectangle(displayFrameScreenPosX, displayFrameScreenPosY, this->posZ,
					  displayFrameScreenSizeX, displayFrameScreenSizeY, 0.43f, 0.45f, 0.43f, 1.0f, lineWidth);
	}

	
//	BlitRectangle(this->posX, this->posY, this->posZ, this->screenSizeX, this->screenSizeY,
	//0.3f, 0.3f, 0.3f, 0.7f, lineWidth);

	//	BlitRectangle(this->posX, this->posY, this->posZ, this->displaySizeX, this->displaySizeY,
	//0.3f, 1.0f, 0.3f, 0.7f, lineWidth);
	
	
//	BlitRectangle(displayFrameScreenPosX, displayFrameScreenPosY, this->posZ,
//				  displayFrameScreenSizeX, displayFrameScreenSizeY, 1.0f, 0.1f, 0.1f, 1.0f, 4.0f);


//	BlitRectangle(viewC64->viewC64Screen->posX, viewC64->viewC64Screen->posY, viewC64->viewC64Screen->posZ,
//				  viewC64->viewC64Screen->sizeX, viewC64->viewC64Screen->sizeY, 0.3f, 0.3f, 0.3f, 0.7f, lineWidth);

	if (showRasterCursor)
	{
		this->RenderCursor();
	}

	//BlitRectangle(lblAutolockScrollMode->posX, lblAutolockScrollMode->posY, posZ, lblAutolockScrollMode->sizeX, lblAutolockScrollMode->sizeY, 1, 1, 0, 1);
	
	
	
	// render UI
	CGuiView::Render();
}

void CViewC64VicDisplay::GetScreenPosFromRasterPos2(float rasterX, float rasterY, float *x, float *y)
{
	*x = (rasterX * displaySizeX / 320.0f) + displayPosWithScrollX;
	*y = (rasterY * displaySizeY / 200.0f) + displayPosWithScrollY;
}

void CViewC64VicDisplay::GetScreenPosFromRasterPosWithoutScroll(float rasterX, float rasterY, float *x, float *y)
{
	*x = (rasterX * displaySizeX / 320.0f) + displayPosX;
	*y = (rasterY * displaySizeY / 200.0f) + displayPosY;
}

void CViewC64VicDisplay::GetRasterPosFromScreenPos2(float x, float y, float *rasterX, float *rasterY)
{
//	LOGD("CViewC64VicDisplay::GetRasterPosFromScreenPos: %f %f", x, y);
	
	float px1 = x - displayPosWithScrollX;
	float py1 = y - displayPosWithScrollY;
	
//	LOGD(" disp=%f %f | size=%f %f", displayPosX, displayPosY, displaySizeX, displaySizeY);
	
	*rasterX = px1 / displaySizeX * 320.0f;
	*rasterY = py1 / displaySizeY * 200.0f;

//	LOGD("  p1=%f %f raster=%f %f", px1, py1, *rasterX, *rasterY);
}

void CViewC64VicDisplay::GetRasterPosFromScreenPosWithoutScroll(float x, float y, float *rasterX, float *rasterY)
{
//	LOGD("CViewC64VicDisplay::GetRasterPosFromScreenPosWithoutScroll: %f %f", x, y);
	
	float px1 = x - displayPosX;
	float py1 = y - displayPosY;
	
//	LOGD(" disp=%f %f | size=%f %f", displayPosX, displayPosY, displaySizeX, displaySizeY);
	
	*rasterX = px1 / displaySizeX * 320.0f;
	*rasterY = py1 / displaySizeY * 200.0f;
	
//	LOGD("  p1=%f %f raster=%f %f (%f %f)", px1, py1, *rasterX, *rasterY, floor(*rasterX), floor(*rasterY));
}

void CViewC64VicDisplay::GetRasterPosFromMousePos2(float *rasterX, float *rasterY)
{
	GetRasterPosFromScreenPos2(guiMain->mousePosX, guiMain->mousePosY, rasterX, rasterY);
}

void CViewC64VicDisplay::GetRasterPosFromMousePosWithoutScroll(float *rasterX, float *rasterY)
{
	GetRasterPosFromScreenPosWithoutScroll(guiMain->mousePosX, guiMain->mousePosY, rasterX, rasterY);
}

bool CViewC64VicDisplay::IsRasterCursorInsideScreen()
{
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
	{
		if (rasterCursorPosY >= 0 && rasterCursorPosY <= 200.0f
			&& rasterCursorPosX >= 0 && rasterCursorPosX < 320.0f)
		{
			return true;
		}
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
	{
		// with border on
		// X: 0x000  0x088 0x1C8  0x1F8
		//        0    136   456    504
		// Y: 0x000  0x032 0x0FA  0x138
		//        0     50   251    312
		if (rasterCursorPosX >= -0x88 && rasterCursorPosX < 0x170 &&
			rasterCursorPosY >= -0x32 && rasterCursorPosY < 0x106)
		{
			return true;
		}
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		//    frame  |visible   interior  visible|  frame
		// X: 0x000  | 0x068  0x088 0x1C8  0x1E8 |  0x1F8
		//        0             136   456             504
		// Y: 0x000  | 0x010  0x032 0x0FA  0x120 |  0x138
		//        0              50   251             312
		
		if (rasterCursorPosX >= -0x20 && rasterCursorPosX < 0x160 &&
			rasterCursorPosY >= -0x22 && rasterCursorPosY < 0xF6)
		{
			return true;
		}
	}
	
	return false;
}

extern "C"
{
	void c64d_vicii_copy_state_data(vicii_cycle_state_t *viciiDest, vicii_cycle_state_t *viciiSrc);
};

vicii_cycle_state_t *CViewC64VicDisplay::UpdateViciiState()
{
	vicii_cycle_state_t *viciiState = NULL;
	
	if (this->visible == false && this->isCursorLocked == false)
	{
		// not locked & not visible - copy current state
		viciiState = &(viewC64->currentViciiState);
		c64d_vicii_copy_state_data(&(viewC64->viciiStateToShow), viciiState);
		viewC64->viewC64StateVIC->isLockedState = false;
		
		return viciiState;
	}

//	LOGD("rasterCursorPosX=%f rasterCursorPosY=%f", rasterCursorPosX, rasterCursorPosY);
	
	return UpdateViciiStateNonVisible(this->rasterCursorPosX, this->rasterCursorPosY);
}

vicii_cycle_state_t *CViewC64VicDisplay::UpdateViciiStateNonVisible(float rx, float ry)
{
	vicii_cycle_state_t *viciiState = NULL;

	int rasterX = floor(rx);
	int rasterY = floor(ry);
	
	bool isInsideScreen = IsRasterCursorInsideScreen();
	
	if (isInsideScreen)
	{
		if (c64SettingsVicStateRecordingMode == C64D_VICII_RECORD_MODE_EVERY_CYCLE)
		{
			float cycle = (rasterX + 0x88) / 8;
			viciiState = c64d_get_vicii_state_for_raster_cycle(rasterY + 0x32, cycle);
			c64d_vicii_copy_state_data(&(viewC64->viciiStateToShow), viciiState);
			
			viewC64->viewC64StateVIC->isLockedState = true;
		}
		else if (c64SettingsVicStateRecordingMode == C64D_VICII_RECORD_MODE_EVERY_LINE)
		{
			viciiState = c64d_get_vicii_state_for_raster_cycle(rasterY + 0x32, 0x00);
			c64d_vicii_copy_state_data(&(viewC64->viciiStateToShow), viciiState);
			viewC64->viewC64StateVIC->isLockedState = true;
		}
		else
		{
			viciiState = &(viewC64->currentViciiState);
			c64d_vicii_copy_state_data(&(viewC64->viciiStateToShow), viciiState);
			viewC64->viewC64StateVIC->isLockedState = false;
		}
	}
	else
	{
		// outside screen - copy current state
		viciiState = &(viewC64->currentViciiState);
		c64d_vicii_copy_state_data(&(viewC64->viciiStateToShow), viciiState);
		viewC64->viewC64StateVIC->isLockedState = false;
	}
	

	return viciiState;
}

void CViewC64VicDisplay::RenderDisplay()
{
//	LOGD("CViewC64VicDisplay::RenderDisplay: %s", this->name);
	
	// this is updated in CViewC64
	//vicii_cycle_state_t *viciiState = this->UpdateViciiState();
	
	vicii_cycle_state_t *viciiState = &(viewC64->viciiStateToShow);
	RefreshScreen(viciiState);
	
	// nearest neighbour
	{
		glBindTexture(GL_TEXTURE_2D, imageScreen->texture[0]);
		
		glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
		glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_NEAREST);
	}

	this->RenderDisplayScreen();
	
	this->RenderDisplaySprites(viciiState);
	
	
//	// back to linear scale
//	{
//		glBindTexture(GL_TEXTURE_2D, imageScreen->texture[0]);
//		
//		glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MIN_FILTER,GL_LINEAR);
//		glTexParameteri(GL_TEXTURE_2D,GL_TEXTURE_MAG_FILTER,GL_LINEAR);
//	}
}

void CViewC64VicDisplay::RenderDisplayScreen()
{
	// render C64 screen border
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL
		|| showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		float br, bg, bb;
		u8 color = viewC64->viciiStateToShow.regs[0x20];
		
		viewC64->debugInterface->GetFloatCBMColor(color, &br, &bg, &bb);
		
		BlitFilledRectangle(visibleScreenPosX, visibleScreenPosY, posZ, visibleScreenSizeX, visibleScreenSizeY, br, bg, bb, 1.0f);
	}
	
	// render texture of C64's screen
	Blit(imageScreen,
		 displayPosWithScrollX,
		 displayPosWithScrollY, -1,
		 displaySizeX,
		 displaySizeY,
		 0.0f, 1.0f, screenTexEndX, screenTexEndY);
	
}

void CViewC64VicDisplay::RenderDisplayScreen(CSlrImage *imageScreenToRender)
{
	// render C64 screen border
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL
		|| showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		float br, bg, bb;
		u8 color = viewC64->viciiStateToShow.regs[0x20];
		
		viewC64->debugInterface->GetFloatCBMColor(color, &br, &bg, &bb);
		
		BlitFilledRectangle(visibleScreenPosX, visibleScreenPosY, posZ, visibleScreenSizeX, visibleScreenSizeY, br, bg, bb, 1.0f);
	}
	
	// render texture of C64's screen
	Blit(imageScreenToRender,
		 displayPosWithScrollX,
		 displayPosWithScrollY, -1,
		 displaySizeX,
		 displaySizeY,
		 0.0f, 1.0f, screenTexEndX, screenTexEndY);
	
}


void CViewC64VicDisplay::RenderDisplaySprites(vicii_cycle_state_t *viciiState)
{
	if (showSpritesGraphics || showSpritesFrames)
	{
		const float spriteTexStartX = 4.0/32.0;
		const float spriteTexStartY = (32.0-4.0)/32.0;
		const float spriteTexEndX = (4.0+24.0)/32.0;
		const float spriteTexEndY = (32.0-(4.0+21.0))/32.0;
		
		for (int i = VICII_NUM_SPRITES-1; i >= 0 ; i--)
		{
			CSlrImage *spriteImage = (*viewC64->viewC64StateVIC->spritesImages)[i];
			
			int bits = viciiState->regs[0x15];
			
			bool enabled = ((bits >> i) & 1) ? true : false;
			
			if (!enabled)
				continue;
			
			float x = viciiState->sprite[i].x;
			
			// sprites with x >= 488 are rendered as from 0 by VIC
			// confirmed by my old intro with sprites scroll on borders
			// but sprites with x >= 0x1F8 are not rendered at all as they are after last VIC raster line cycle

			if (x >= 0x1F8)
				continue;
			
			// TODO: confirm the value 0x01D0
			if (x >= 0x01D0)
			{
				// 488 = 8 - 24 = -16
				x = (x - 488.0f) - 16.0f;
			}
			
			x -= 0x18;
			
			float sprPosY = viciiState->regs[1 + (i << 1)];
			
			float y = sprPosY - 0x32;
			
			float px = displayPosX + (float)x * rasterScaleFactorX  + rasterCrossOffsetX;
			float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
			
			bits = viciiState->regs[0x1d];
			float spriteSizeX = ((bits >> i) & 1) ? 48 : 24;
			
			bits = viciiState->regs[0x17];
			float spriteSizeY = ((bits >> i) & 1) ? 42 : 21;
			
			spriteSizeX *= rasterScaleFactorX;
			spriteSizeY *= rasterScaleFactorY;
			
			if (showSpritesFrames)
			{
				BlitRectangle(px, py, posZ, spriteSizeX, spriteSizeY, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f);
				
				if (sprPosY < 54)
				{
					if (sprPosY < 30)
					{
						float y = sprPosY - 0x31 + 0xFF;
						float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
						BlitRectangle(px, py, posZ, spriteSizeX, spriteSizeY, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f);
					}
					else
					{
						float y = sprPosY - 0x32 - 0x36;
						float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
						BlitRectangle(px, py, posZ, spriteSizeX, spriteSizeY, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f);
					}
				}
				
			}
			
			if (showSpritesGraphics)
			{
				Blit(spriteImage, px, py, posZ, spriteSizeX, spriteSizeY, spriteTexStartX, spriteTexStartY, spriteTexEndX, spriteTexEndY);
				
				// TODO: confirm are these values correct?
				if (sprPosY < 54)
				{
					if (sprPosY < 30)
					{
						float y = sprPosY - 0x31 + 0xFF;
						float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
						Blit(spriteImage, px, py, posZ, spriteSizeX, spriteSizeY, spriteTexStartX, spriteTexStartY, spriteTexEndX, spriteTexEndY);
					}
					//					else
					//					{
					//						float y = sprPosY - 0x32 - 0x36;
					//						float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
					//						Blit(spriteImage, px, py, posZ, spriteSizeX, spriteSizeY, spriteTexStartX, spriteTexStartY, spriteTexEndX, spriteTexEndY);
					//					}
				}
			}
		}
	}
}

//
void CViewC64VicDisplay::RenderDisplaySpritesOnly(vicii_cycle_state_t *viciiState)
{
	const float spriteTexStartX = 4.0/32.0;
	const float spriteTexStartY = (32.0-4.0)/32.0;
	const float spriteTexEndX = (4.0+24.0)/32.0;
	const float spriteTexEndY = (32.0-(4.0+21.0))/32.0;
	
	std::vector<CSlrImage *>::iterator it = viewC64->viewC64StateVIC->spritesImages->begin();
	
	for (int i = 0; i < VICII_NUM_SPRITES; i++)
	{
		CSlrImage *spriteImage = *it;
		it++;
		
		int bits = viciiState->regs[0x15];
		
		bool enabled = ((bits >> i) & 1) ? true : false;
		
		if (!enabled)
			continue;
		
		float x = viciiState->sprite[i].x;
		
		// sprites with x >= 488 are rendered as from 0 by VIC
		// confirmed by my old intro with sprites scroll on borders
		// but sprites with x >= 0x1F8 are not rendered at all as they are after last VIC raster line cycle
		
		if (x >= 0x1F8)
			continue;
		
		// TODO: confirm the value 0x01D0
		if (x >= 0x01D0)
		{
			// 488 = 8 - 24 = -16
			x = (x - 488.0f) - 16.0f;
		}
		
		x -= 0x18;
		
		float sprPosY = viciiState->regs[1 + (i << 1)];
		
		float y = sprPosY - 0x32;
		
		float px = displayPosX + (float)x * rasterScaleFactorX  + rasterCrossOffsetX;
		float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
		
		bits = viciiState->regs[0x1d];
		float spriteSizeX = ((bits >> i) & 1) ? 48 : 24;
		
		bits = viciiState->regs[0x17];
		float spriteSizeY = ((bits >> i) & 1) ? 42 : 21;
		
		spriteSizeX *= rasterScaleFactorX;
		spriteSizeY *= rasterScaleFactorY;
		
		Blit(spriteImage, px, py, posZ, spriteSizeX, spriteSizeY, spriteTexStartX, spriteTexStartY, spriteTexEndX, spriteTexEndY);
		
		// TODO: confirm are these values correct?
		if (sprPosY < 54)
		{
			if (sprPosY < 30)
			{
				float y = sprPosY - 0x31 + 0xFF;
				float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
				Blit(spriteImage, px, py, posZ, spriteSizeX, spriteSizeY, spriteTexStartX, spriteTexStartY, spriteTexEndX, spriteTexEndY);
			}
			//					else
			//					{
			//						float y = sprPosY - 0x32 - 0x36;
			//						float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
			//						Blit(spriteImage, px, py, posZ, spriteSizeX, spriteSizeY, spriteTexStartX, spriteTexStartY, spriteTexEndX, spriteTexEndY);
			//					}
		}
	}
}

void CViewC64VicDisplay::RenderGridSpritesOnly(vicii_cycle_state_t *viciiState)
{
	const float spriteTexStartX = 4.0/32.0;
	const float spriteTexStartY = (32.0-4.0)/32.0;
	const float spriteTexEndX = (4.0+24.0)/32.0;
	const float spriteTexEndY = (32.0-(4.0+21.0))/32.0;
	
	std::vector<CSlrImage *>::iterator it = viewC64->viewC64StateVIC->spritesImages->begin();
	
	for (int i = 0; i < VICII_NUM_SPRITES; i++)
	{
		CSlrImage *spriteImage = *it;
		it++;
		
		int bits = viciiState->regs[0x15];
		
		bool enabled = ((bits >> i) & 1) ? true : false;
		
		if (!enabled)
			continue;
		
		float x = viciiState->sprite[i].x;
		
		// sprites with x >= 488 are rendered as from 0 by VIC
		// confirmed by my old intro with sprites scroll on borders
		// but sprites with x >= 0x1F8 are not rendered at all as they are after last VIC raster line cycle
		
		if (x >= 0x1F8)
			continue;
		
		// TODO: confirm the value 0x01D0
		if (x >= 0x01D0)
		{
			// 488 = 8 - 24 = -16
			x = (x - 488.0f) - 16.0f;
		}
		
		x -= 0x18;
		
		float sprPosY = viciiState->regs[1 + (i << 1)];
		
		float y = sprPosY - 0x32;
		
		float px = displayPosX + (float)x * rasterScaleFactorX  + rasterCrossOffsetX;
		float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
		
		bits = viciiState->regs[0x1d];
		float spriteSizeX = ((bits >> i) & 1) ? 48 : 24;
		
		bits = viciiState->regs[0x17];
		float spriteSizeY = ((bits >> i) & 1) ? 42 : 21;
		
		spriteSizeX *= rasterScaleFactorX;
		spriteSizeY *= rasterScaleFactorY;
		
		BlitRectangle(px, py, posZ, spriteSizeX, spriteSizeY, 1.0f, 0.0f, 0.0f, 1.0f, 1.0f);
		
		if (sprPosY < 54)
		{
			if (sprPosY < 30)
			{
				float y = sprPosY - 0x31 + 0xFF;
				float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
				BlitRectangle(px, py, posZ, spriteSizeX, spriteSizeY, 0.0f, 1.0f, 1.0f, 1.0f, 1.0f);
			}
			else
			{
				float y = sprPosY - 0x32 - 0x36;
				float py = displayPosY + (float)y * rasterScaleFactorY  + rasterCrossOffsetY;
				BlitRectangle(px, py, posZ, spriteSizeX, spriteSizeY, 1.0f, 1.0f, 0.0f, 1.0f, 1.0f);
			}
		}

	}
}

//


void CViewC64VicDisplay::RenderGridLines()
{
	// raster screen in hex:
	// startx = 68 (88) endx = 1e8 (1c8)
	// starty = 10 (32) endy = 120 ( fa)
	
	float cys = displayPosWithScrollY + 0.0f * rasterScaleFactorY  + rasterCrossOffsetY;
	float cye = displayPosWithScrollY + 200.0f * rasterScaleFactorY  + rasterCrossOffsetY;
	
	float cxs = displayPosWithScrollX + 0.0f * rasterScaleFactorX  + rasterCrossOffsetX;
	float cxe = displayPosWithScrollX + 320.0f * rasterScaleFactorX  + rasterCrossOffsetX;
	
	
	// vertical lines
	for (float rasterX = 0.0f; rasterX < 321.0f; rasterX += 8.0f)
	{
		float cx = displayPosWithScrollX + (float)rasterX * rasterScaleFactorX  + rasterCrossOffsetX;
		
		BlitLine(cx, cys, cx, cye, -1,
				 gridLinesColorR, gridLinesColorG, gridLinesColorB, gridLinesColorA);
	}
	
	// horizontal lines
	for (float rasterY = 0.0f; rasterY < 201.0f; rasterY += 8)
	{
		float cy = displayPosWithScrollY + (float)rasterY * rasterScaleFactorY  + rasterCrossOffsetY;
		
		BlitLine(cxs, cy, cxe, cy, -1,
				 gridLinesColorR, gridLinesColorG, gridLinesColorB, gridLinesColorA);
	}
	
	
	//		float cx = displayPosWithScrollX + (float)rasterX * rasterScaleFactorX  + rasterCrossOffsetX;
	//		float cy = displayPosWithScrollY + (float)rasterY * rasterScaleFactorY  + rasterCrossOffsetY;

	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL
		|| showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		if (this->hasFocus == false)
		{
			BlitRectangle(fullScanScreenPosX, fullScanScreenPosY, posZ, fullScanScreenSizeX, fullScanScreenSizeY,
						  0.5f, 0.5f, 0.5f, 0.5f);
		}

		if ((viewC64->viciiStateToShow.regs[0x20] & 0x0F) == 0x00)
		{
			BlitRectangle(visibleScreenPosX, visibleScreenPosY, posZ, visibleScreenSizeX, visibleScreenSizeY,
						  gridLinesColorB, gridLinesColorG, gridLinesColorR, gridLinesColorA*1.3f, 0.75f);
		}
		
	}
	
}

void CViewC64VicDisplay::RenderCursor()
{
	RenderCursor(this->rasterCursorPosX, this->rasterCursorPosY);
}

void CViewC64VicDisplay::RenderCursor(float rasterCursorPosX, float rasterCursorPosY)
{
	if (isCursorLocked && viewC64->viewC64Disassemble->isTrackingPC == false)
	{
		UpdateRasterCursorPos();
		ScrollMemoryAndDisassembleToRasterPosition(rasterCursorPosX, rasterCursorPosY, false);
	}
	
	//    frame  |visible   interior  visible|  frame
	// X: 0x000  | 0x068  0x088 0x1C8  0x1E8 |  0x1F8
	//        0             136   456             504
	// Y: 0x000  | 0x010  0x032 0x0FA  0x120 |  0x138
	//        0              50   251             312

	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
	{
		if (rasterCursorPosX >= -0x88 && rasterCursorPosX < 0x170
			&& rasterCursorPosY >= -0x32 && rasterCursorPosY < 0x106)
		{
			this->RenderRaster(rasterCursorPosX, rasterCursorPosY);
		}
		else
		{
			if (viewC64->isShowingRasterCross)
			{
				int rx = viewC64->rasterToShowX - 0x88;
				int ry = viewC64->rasterToShowY - 0x32;
				
				if (viewC64->rasterToShowX >= 0x000 && viewC64->rasterToShowX < 0x1F8
					&& viewC64->rasterToShowY >= 0x000 && viewC64->rasterToShowY < 0x138)
				{
					this->RenderRaster(rx, ry);
				}
			}
			
		}
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		if (rasterCursorPosX >= -0x20 && rasterCursorPosX <= 0x160
			&& rasterCursorPosY >= -0x22 && rasterCursorPosY <= 0xF6)
		{
			this->RenderRaster(rasterCursorPosX, rasterCursorPosY);
		}
		else
		{
			if (viewC64->isShowingRasterCross)
			{
				int rx = viewC64->rasterToShowX - 0x88;
				int ry = viewC64->rasterToShowY - 0x32;
				
				if (viewC64->rasterToShowX >= 0x068 && viewC64->rasterToShowX < 0x1F0
					&& viewC64->rasterToShowY >= 0x010 && viewC64->rasterToShowY < 0x128)
				{
					this->RenderRaster(rx, ry);
				}
			}
		}
	}
	else //if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
	{
		if (rasterCursorPosX >= 0 && rasterCursorPosX <= 320.0f && rasterCursorPosY >= 0 && rasterCursorPosY <= 200.0f)
		{
			this->RenderRaster(rasterCursorPosX, rasterCursorPosY);
		}
		else
		{
			if (viewC64->isShowingRasterCross)
			{
				int rx = viewC64->rasterToShowX - 0x88;
				int ry = viewC64->rasterToShowY - 0x32;
				
				// X: 0x000  0x088 0x1C8  0x1F8
				//        0    136   456    504
				// Y: 0x000  0x032 0x0FA  0x138
				//        0     50   251    312
				
				if (rx >= 0 && rx <= 320.0f && ry >= 0 && ry <= 200.0f)
				{
					this->RenderRaster(rx, ry);
				}
			}
		}
	}
}


void CViewC64VicDisplay::UpdateRasterCrossFactors()
{
//	LOGD("CViewC64VicDisplay::UpdateRasterCrossFactors");

	if (viewC64->debugInterface->GetEmulatorType() == C64_EMULATOR_VICE)
	{
		this->rasterScaleFactorX = displaySizeX / (float)320;
		this->rasterScaleFactorY = displaySizeY / (float)200;
		rasterCrossOffsetX = 0.0f; // -103.787 * rasterScaleFactorX;
		rasterCrossOffsetY = 0.0f; //-15.500 * rasterScaleFactorY;
	}
	
	rasterCrossWidth = 1.0f;
	rasterCrossWidth2 = rasterCrossWidth/2.0f;
	
	rasterCrossSizeX = 25.0f * rasterScaleFactorX;
	rasterCrossSizeY = 25.0f * rasterScaleFactorY;
	rasterCrossSizeX2 = rasterCrossSizeX/2.0f;
	rasterCrossSizeY2 = rasterCrossSizeY/2.0f;
	rasterCrossSizeX3 = rasterCrossSizeX/3.0f;
	rasterCrossSizeY3 = rasterCrossSizeY/3.0f;
	rasterCrossSizeX4 = rasterCrossSizeX/4.0f;
	rasterCrossSizeY4 = rasterCrossSizeY/4.0f;
	rasterCrossSizeX6 = rasterCrossSizeX/6.0f;
	rasterCrossSizeY6 = rasterCrossSizeY/6.0f;
	
	rasterCrossSizeX34 = rasterCrossSizeX2+rasterCrossSizeX4;
	rasterCrossSizeY34 = rasterCrossSizeY2+rasterCrossSizeY4;
	
	UpdateDisplayFrameScreen();
}

void CViewC64VicDisplay::UpdateDisplayFrameScreen()
{
	// display frame in view/screen coordinates
	displayFrameScreenPosX = this->displayPosWithScrollX + displayFrameRasterX*rasterScaleFactorX - 1.0f;
	displayFrameScreenPosY = this->displayPosWithScrollY + displayFrameRasterY*rasterScaleFactorY - 1.0f;
	
	displayFrameScreenSizeX = displayFrameRasterSizeX * rasterScaleFactorX + 2.0f;
	displayFrameScreenSizeY = displayFrameRasterSizeY * rasterScaleFactorY + 2.0f;
}

void CViewC64VicDisplay::SetDisplayFrameRaster(float rasterX, float rasterY, float rasterSizeX, float rasterSizeY)
{
//	LOGD("SetDisplayFrameRaster: %f %f %f %f", rasterX, rasterY, rasterSizeX, rasterSizeY);
	
	displayFrameRasterX = rasterX;
	displayFrameRasterY = rasterY;
	displayFrameRasterSizeX = rasterSizeX;
	displayFrameRasterSizeY = rasterSizeY;

	UpdateDisplayFrameScreen();
}


void CViewC64VicDisplay::RenderRaster(int rasterX, int rasterY)
{
	float cx = displayPosWithScrollX + (float)rasterX * rasterScaleFactorX  + rasterCrossOffsetX;
	float cy = displayPosWithScrollY + (float)rasterY * rasterScaleFactorY  + rasterCrossOffsetY;
	

	/// long screen line
	BlitFilledRectangle(posX, cy - rasterCrossWidth2, posZ, fullScanScreenSizeX, rasterCrossWidth,
						rasterLongScrenLineR, rasterLongScrenLineG, rasterLongScrenLineB, rasterLongScrenLineA);
	BlitFilledRectangle(cx - rasterCrossWidth2, posY, posZ, rasterCrossWidth, fullScanScreenSizeY,
						rasterLongScrenLineR, rasterLongScrenLineG, rasterLongScrenLineB, rasterLongScrenLineA);

	// red cross
	BlitFilledRectangle(cx - rasterCrossWidth2, cy - rasterCrossSizeY2, posZ, rasterCrossWidth, rasterCrossSizeY,
						rasterCrossExteriorR, rasterCrossExteriorG, rasterCrossExteriorB, rasterCrossExteriorA);
	BlitFilledRectangle(cx - rasterCrossSizeX2, cy - rasterCrossWidth2, posZ, rasterCrossSizeX, rasterCrossWidth,
						rasterCrossExteriorR, rasterCrossExteriorG, rasterCrossExteriorB, rasterCrossExteriorA);

	// cross ending tip
	BlitFilledRectangle(cx - rasterCrossWidth2, cy - rasterCrossSizeY34, posZ, rasterCrossWidth, rasterCrossSizeY4,
						rasterCrossEndingTipR, rasterCrossEndingTipG, rasterCrossEndingTipB, rasterCrossEndingTipA);
	BlitFilledRectangle(cx - rasterCrossWidth2, cy + rasterCrossSizeY2, posZ, rasterCrossWidth, rasterCrossSizeY4,
						rasterCrossEndingTipR, rasterCrossEndingTipG, rasterCrossEndingTipB, rasterCrossEndingTipA);
	BlitFilledRectangle(cx - rasterCrossSizeX34, cy - rasterCrossWidth2, posZ, rasterCrossSizeX4, rasterCrossWidth,
						rasterCrossEndingTipR, rasterCrossEndingTipG, rasterCrossEndingTipB, rasterCrossEndingTipA);
	BlitFilledRectangle(cx + rasterCrossSizeX2, cy - rasterCrossWidth2, posZ, rasterCrossSizeX4, rasterCrossWidth,
						rasterCrossEndingTipR, rasterCrossEndingTipG, rasterCrossEndingTipB, rasterCrossEndingTipA);

	// white interior cross
	BlitFilledRectangle(cx - rasterCrossWidth2, cy - rasterCrossSizeY6, posZ, rasterCrossWidth, rasterCrossSizeY3,
						rasterCrossInteriorR, rasterCrossInteriorG, rasterCrossInteriorB, rasterCrossInteriorA);
	BlitFilledRectangle(cx - rasterCrossSizeX6, cy - rasterCrossWidth2, posZ, rasterCrossSizeX3, rasterCrossWidth,
						rasterCrossInteriorR, rasterCrossInteriorG, rasterCrossInteriorB, rasterCrossInteriorA);
	
}

void CViewC64VicDisplay::RenderBadLines()
{
//	LOGD("CViewC64VicDisplay::RenderBadLines");

	float cy = displayPosY + rasterCrossOffsetY - (0x33 * rasterScaleFactorY) + rasterScaleFactorY/2.0f;
	
	for (int rasterLine = 0; rasterLine < 312; rasterLine++)
	{
		vicii_cycle_state_t *viciiState = c64d_get_vicii_state_for_raster_line(rasterLine);
		
		if (viciiState->bad_line)
		{
			BlitFilledRectangle(posX, cy, posZ, sizeX, rasterScaleFactorY, 0.0f, 1.0f, 1.0f, c64SettingsScreenGridLinesAlpha);
		}
		
		cy += rasterScaleFactorY;
	}

}


void CViewC64VicDisplay::Render(GLfloat posX, GLfloat posY)
{
	CGuiView::Render(posX, posY);
}



bool CViewC64VicDisplay::ScrollMemoryAndDisassembleToRasterPosition(float rx, float ry, bool isForced)
{
	LOGD("ScrollMemoryAndDisassembleToRasterPosition: %f %f %d", rx, ry, isForced);

	// check if outside
	int addr = -1;
	
	if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_RASTER_PC)
	{
		// will be updated via VIC State view / PC state lock
		foundMemoryCellPC = true;
		return false;
	}
	
	if (rx < 0 || rx > 319 || ry < 0 || ry > 199)
	{
		foundMemoryCellPC = false;
		return false;
	}

	
	if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_COLOUR_ADDRESS)
	{
		addr = GetColourAddressForRaster(rx, ry);
	}
	else if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_TEXT_ADDRESS)
	{
		addr = GetTextModeAddressForRaster(rx, ry);
	}
	else if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_BITMAP_ADDRESS)
	{
		addr = GetAddressForRaster(rx, ry);
	}
	else	// ?
	{
		return false;
	}
	
	if (addr < 0 || addr > 0xFFFF)
		return false;
	
	//LOGD("addr=%04x autoScrollMode=%d", addr, autoScrollMode);
	
	rasterCursorPosX = rx;
	rasterCursorPosY = ry;
	
	viewC64->viewC64MemoryDataDump->ScrollToAddress(addr);
	
	if (canScrollDisassemble == true)
	{
		if (isForced)
		{
			viewC64->viewC64Disassemble->changedByUser = false;
		}
		
		CViewMemoryMapCell *cell = viewC64->viewC64MemoryMap->memoryCells[addr];
		if (cell->pc != -1)
		{
			//LOGD(".... isForced=%d changed=%d", isForced, viewC64->viewC64Disassemble->changedByUser);
			//LOGD("viewC64->viewC64Disassemble->changedByUser=%d", viewC64->viewC64Disassemble->changedByUser);
			if (isForced || viewC64->viewC64Disassemble->changedByUser == false)
			{
				//LOGD("      SCROLL TO %04x", cell->pc);
				viewC64->viewC64Disassemble->ScrollToAddress(cell->pc);
				foundMemoryCellPC = true;
			}
		}
		else
		{
			//LOGD(".... pc=%d", cell->pc);
			foundMemoryCellPC = false;
		}
	}
	
	return true;
}

bool CViewC64VicDisplay::IsInsideDisplay(float x, float y)
{
	if (x >= displayPosWithScrollX && x <= displayPosWithScrollX+displaySizeX
		&& y >= displayPosWithScrollY && y <= displayPosWithScrollY+displaySizeY)
	{
		return true;
	}
	return false;
}

bool CViewC64VicDisplay::IsInsideScreen(float x, float y)
{
	if (x >= fullScanScreenPosX && x <= fullScanScreenPosX+fullScanScreenSizeX
		&& y >= fullScanScreenPosY && y <= fullScanScreenPosY+fullScanScreenSizeY)
	{
		return true;
	}
	return false;
}



//@returns is consumed
bool CViewC64VicDisplay::DoTap(GLfloat x, GLfloat y)
{
	LOGG("CViewC64VicDisplay::DoTap:  x=%f y=%f", x, y);
	
	if (this->IsInsideScreen(x, y))
	{
		float rx, ry;
		
		this->GetRasterPosFromScreenPos2(x, y, &rx, &ry);
		
		// check if tapped the same raster position = unlock
		if (isCursorLocked && rasterCursorPosX == rx && rasterCursorPosY == ry)
		{
			// unlock
			UnlockCursor();
			return true;
		}
		
		if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_RASTER_PC)
		{
			rasterCursorPosX = rx;
			rasterCursorPosY = ry;
			
			LockCursor();
			
			// *UX fix: always update* // do not update disassemble when user moved code
//			if (viewC64->viewC64Disassemble->changedByUser == false)
			{
				if (canScrollDisassemble == true)
				{
					viewC64->viewC64Disassemble->isTrackingPC = true;
				}
			}
			return true;
		}
		else
		{
			// *UX fix: always update* // do not update disassemble when user moved code
//			if (viewC64->viewC64Disassemble->changedByUser == false)
			{
				if (ScrollMemoryAndDisassembleToRasterPosition(rx, ry, true))
				{
					LockCursor();
					if (canScrollDisassemble == true)
					{
						viewC64->viewC64Disassemble->isTrackingPC = false;
					}
					return true;
				}
			}
//			else
//			{
//				rasterCursorPosX = rx;
//				rasterCursorPosY = ry;
//
//				LockCursor();
//				return true;
//			}
		}
	}

	return CGuiView::DoTap(x, y);
}

bool CViewC64VicDisplay::DoRightClick(GLfloat x, GLfloat y)
{
	// TODO: this is too nasty workaround, do something with this!
	if (viewC64->currentScreenLayoutId == C64_SCREEN_LAYOUT_VIC_DISPLAY
		&& guiMain->currentView == viewC64)
	{
		if (viewC64->viewC64Screen->IsInsideViewNonVisible(x, y))
		{
			if (viewC64->viewC64Screen->visible)
			{
				viewC64->viewC64Screen->showZoomedScreen = true;
				viewC64->viewC64Screen->visible = false;
			}
			else
			{
				viewC64->viewC64Screen->showZoomedScreen = false;
				viewC64->viewC64Screen->visible = true;
			}
			
			return true;
		}
	}
	
	return false; //CGuiView::DoRightClick(x, y);
}


void CViewC64VicDisplay::SetNextAutoScrollMode()
{
	switch(autoScrollMode)
	{
		case AUTOSCROLL_DISASSEMBLE_RASTER_PC:
			SetAutoScrollMode(AUTOSCROLL_DISASSEMBLE_BITMAP_ADDRESS);
			break;
			
		case AUTOSCROLL_DISASSEMBLE_BITMAP_ADDRESS:
			SetAutoScrollMode(AUTOSCROLL_DISASSEMBLE_TEXT_ADDRESS);
			break;
			
		case AUTOSCROLL_DISASSEMBLE_TEXT_ADDRESS:
			SetAutoScrollMode(AUTOSCROLL_DISASSEMBLE_COLOUR_ADDRESS);
			break;
			
		default:
		case AUTOSCROLL_DISASSEMBLE_COLOUR_ADDRESS:
			SetAutoScrollMode(AUTOSCROLL_DISASSEMBLE_RASTER_PC);
			break;
			
	}
}

void CViewC64VicDisplay::UpdateRasterCursorPos()
{
	if (!isCursorLocked)
	{
		float px = guiMain->mousePosX - displayPosWithScrollX;
		float py = guiMain->mousePosY - displayPosWithScrollY;
		
		rasterCursorPosX = px / displaySizeX * 320.0f;
		rasterCursorPosY = py / displaySizeY * 200.0f;
		
		//LOGD("mx=%f x=%f rx=%f  my=%f y=%f ry=%f", mousePosX, px, rasterX, mousePosY, py, rasterY);
	}
}

bool CViewC64VicDisplay::DoFinishTap(GLfloat x, GLfloat y)
{
	LOGG("CViewC64VicDisplay::DoFinishTap: %f %f", x, y);
	return CGuiView::DoFinishTap(x, y);
}

//@returns is consumed
bool CViewC64VicDisplay::DoDoubleTap(GLfloat x, GLfloat y)
{
	LOGG("CViewC64VicDisplay::DoDoubleTap:  x=%f y=%f", x, y);
	return CGuiView::DoDoubleTap(x, y);
}

bool CViewC64VicDisplay::DoFinishDoubleTap(GLfloat x, GLfloat y)
{
	LOGG("CViewC64VicDisplay::DoFinishTap: %f %f", x, y);
	return CGuiView::DoFinishDoubleTap(x, y);
}

void CViewC64VicDisplay::UpdateAutoscrollDisassemble(bool isForced)
{
	if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_TEXT_ADDRESS
		|| autoScrollMode == AUTOSCROLL_DISASSEMBLE_BITMAP_ADDRESS
		|| autoScrollMode == AUTOSCROLL_DISASSEMBLE_COLOUR_ADDRESS)
	{
		ScrollMemoryAndDisassembleToRasterPosition(rasterCursorPosX, rasterCursorPosY, isForced);
	}
	else if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_RASTER_PC)
	{
		if (canScrollDisassemble == true)
		{
			if (isForced || viewC64->viewC64Disassemble->changedByUser == false)
			{
				viewC64->viewC64Disassemble->isTrackingPC = true;
				viewC64->viewC64Disassemble->changedByUser = false;
			}
		}
	}
}

bool CViewC64VicDisplay::DoNotTouchedMove(GLfloat x, GLfloat y)
{
	LOGI("CViewC64VicDisplay::DoNotTouchedMove (this=%x)", this);
	
	this->UpdateRasterCursorPos();

	UpdateAutoscrollDisassemble(false);

	return CGuiView::DoNotTouchedMove(x, y);
}

bool CViewC64VicDisplay::DoMove(GLfloat x, GLfloat y, GLfloat distX, GLfloat distY, GLfloat diffX, GLfloat diffY)
{
	this->UpdateRasterCursorPos();
	return CGuiView::DoMove(x, y, distX, distY, diffX, diffY);
}

bool CViewC64VicDisplay::FinishMove(GLfloat x, GLfloat y, GLfloat distX, GLfloat distY, GLfloat accelerationX, GLfloat accelerationY)
{
	return CGuiView::FinishMove(x, y, distX, distY, accelerationX, accelerationY);
}

bool CViewC64VicDisplay::DoScrollWheel(float deltaX, float deltaY)
{
	// TODO: fix me
	return false;
	
	if (c64SettingsUseMultiTouchInMemoryMap)
	{
		float f = 2.0f;
		MoveDisplayDiff(deltaX * f, deltaY * f);
	}
	else
	{
		if (c64SettingsMemoryMapInvertControl)
		{
			deltaY = -deltaY;
		}
		
		// scale
		float dy = deltaY * 0.25f;
		
		float newScale = this->scale + dy;
		
		LOGG("CViewC64VicDisplay::DoScrollWheel:  %f %f %f", this->scale, dy, newScale);
		
		ZoomDisplay(newScale);
	}
	
	return true;
}

void CViewC64VicDisplay::MoveDisplayDiff(float diffX, float diffY)
{
	float px = this->posX;
	float py = this->posY;
	
	px += diffX;
	py += diffY;
	
	MoveDisplayToScreenPos(px, py);
}

void CViewC64VicDisplay::MoveDisplayToScreenPos(float px, float py)
{
	if (px > 0.0f)
		px = 0.0f;
	
	if (py > 0.0f)
		py = 0.0f;
	
	if (px + this->visibleScreenSizeX < SCREEN_WIDTH)
	{
		px = SCREEN_WIDTH - this->visibleScreenSizeX;
	}
	
	if (py + this->visibleScreenSizeY < SCREEN_HEIGHT)
	{
		py = SCREEN_HEIGHT - this->visibleScreenSizeY;
	}
	
	this->SetPosition(px, py);
	UpdateDisplayFrame();
}

void CViewC64VicDisplay::ZoomDisplay(float newScale)
{
	if (newScale < 1.80f)
		newScale = 1.80f;
	
	if (newScale > 60.0f)
		newScale = 60.0f;
	
	if (newScale < c64SettingsPaintGridShowZoomLevel)
	{
		this->showGridLines = false;
	}
	else
	{
		this->showGridLines = true;
	}
	
	float cx = guiMain->mousePosX;
	float cy = guiMain->mousePosY;
	
		float px, py;
		this->GetRasterPosFromScreenPosWithoutScroll(cx, cy, &px, &py);
		
		this->SetDisplayScale(newScale);
		
		float pcx, pcy;
		this->GetScreenPosFromRasterPosWithoutScroll(px, py, &pcx, &pcy);
		
		MoveDisplayDiff(cx-pcx, cy-pcy);
	
	UpdateDisplayFrame();
}

void CViewC64VicDisplay::UpdateDisplayFrame()
{
	// check boundaries
	float px = this->posX;
	float py = this->posY;
	
	if (px > 0.0f)
		px = 0.0f;
	
	if (py > 0.0f)
		py = 0.0f;
	
	if (px + this->visibleScreenSizeX < SCREEN_WIDTH)
	{
		px = SCREEN_WIDTH - this->visibleScreenSizeX;
	}
	
	if (py + this->visibleScreenSizeY < SCREEN_HEIGHT)
	{
		py = SCREEN_HEIGHT - this->visibleScreenSizeY;
	}
	
	this->SetPosition(px, py);
	
	float rx, ry;
	this->GetRasterPosFromScreenPosWithoutScroll(0.0f, 0.0f, &rx, &ry);
	
	float rx2, ry2;
	
	//	LOGD("viewVicDisplayMain->sizeX=%f", viewVicDisplayMain->sizeX);
	//	viewVicDisplayMain->GetRasterPosFromScreenPos(viewVicDisplayMain->posX + viewVicDisplayMain->sizeX,
	//												  viewVicDisplayMain->posY + viewVicDisplayMain->sizeY, &rx2, &ry2);
	
	this->GetRasterPosFromScreenPosWithoutScroll(SCREEN_WIDTH-1,
												  SCREEN_HEIGHT-1, &rx2, &ry2);
	
	
	
	float rsx = rx2 - rx;
	float rsy = ry2 - ry;
	
	this->SetDisplayFrameRaster((int)rx+1, (int)ry+1, (int)rsx-1, (int)rsy-1);
	
	//	viewVicDisplaySmall->SetDisplayFrameRaster(rx+1, ry+1, rsx-1, rsy-1);
}


bool CViewC64VicDisplay::InitZoom()
{
	return CGuiView::InitZoom();
}

bool CViewC64VicDisplay::DoZoomBy(GLfloat x, GLfloat y, GLfloat zoomValue, GLfloat difference)
{
	// TODO: fix me
	return false;
	
	// scale
	float dy = difference * 0.25f;
	
	float newScale = this->scale + dy;
	
	LOGG("CViewC64VicDisplay::DoZoomBy:  %f %f %f", this->scale, dy, newScale);
	
	this->SetDisplayScale(newScale);
	
//	ZoomDisplay(newScale);
	
	
	return true;
}

bool CViewC64VicDisplay::DoMultiTap(COneTouchData *touch, float x, float y)
{
	return CGuiView::DoMultiTap(touch, x, y);
}

bool CViewC64VicDisplay::DoMultiMove(COneTouchData *touch, float x, float y)
{
	return CGuiView::DoMultiMove(touch, x, y);
}

bool CViewC64VicDisplay::DoMultiFinishTap(COneTouchData *touch, float x, float y)
{
	return CGuiView::DoMultiFinishTap(touch, x, y);
}

void CViewC64VicDisplay::FinishTouches()
{
	return CGuiView::FinishTouches();
}

//    frame  |visible   interior  visible|  frame
// X: 0x000  | 0x068  0x088 0x1C8  0x1E8 |  0x1F8
//        0             136   456             504
// Y: 0x000  | 0x010  0x032 0x0FA  0x120 |  0x138
//        0              50   251             312

void CViewC64VicDisplay::RasterCursorLeft()
{
	rasterCursorPosX--;
	
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
	{
		if (rasterCursorPosX < -0x088)
		{
			rasterCursorPosX = 0x16F;
			rasterCursorPosY--;
			if (rasterCursorPosY < -0x032)
				rasterCursorPosY = 0x105;
		}
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
	{
		if (rasterCursorPosX < 0)
		{
			rasterCursorPosX = 319;
			rasterCursorPosY--;
			if (rasterCursorPosY < 0)
				rasterCursorPosY = 199;
		}
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		if (rasterCursorPosX < -0x020)
		{
			rasterCursorPosX = 0x15F;
			rasterCursorPosY--;
			if (rasterCursorPosY < -0x022)
				rasterCursorPosY = 0x0EE;
		}
	}
}

void CViewC64VicDisplay::RasterCursorRight()
{
	rasterCursorPosX++;
	
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
	{
		if (rasterCursorPosX >= 0x170)
		{
			rasterCursorPosX = -0x088;
			rasterCursorPosY++;
			if (rasterCursorPosY >= 0x106)
				rasterCursorPosY = -0x032;
		}
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
	{
		if (rasterCursorPosX >= 320)
		{
			rasterCursorPosX = 0;
			rasterCursorPosY++;
			if (rasterCursorPosY >= 200)
				rasterCursorPosY = 0;
		}
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		if (rasterCursorPosX >= 0x160)
		{
			rasterCursorPosX = -0x020;
			rasterCursorPosY++;
			if (rasterCursorPosY >= 0x0EF)
				rasterCursorPosY = -0x022;
		}
	}
}

void CViewC64VicDisplay::RasterCursorUp()
{
	rasterCursorPosY--;
	
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
	{
		if (rasterCursorPosY < -0x032)
			rasterCursorPosY = 0x105;
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
	{
		if (rasterCursorPosY < 0)
			rasterCursorPosY = 199;
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		if (rasterCursorPosY < -0x022)
			rasterCursorPosY = 0x0EE;
	}
}

void CViewC64VicDisplay::RasterCursorDown()
{
	rasterCursorPosY++;
	
	if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_FULL)
	{
		if (rasterCursorPosY >= 0x106)
			rasterCursorPosY = -0x032;
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_NONE)
	{
		if (rasterCursorPosY >= 200)
			rasterCursorPosY = 0;
	}
	else if (showDisplayBorderType == VIC_DISPLAY_SHOW_BORDER_VISIBLE_AREA)
	{
		if (rasterCursorPosY >= 0x0EF)
			rasterCursorPosY = -0x022;
	}
}

void CViewC64VicDisplay::LockCursor()
{
	isCursorLocked = true;
	
	if (viewVicControl)
	{
		viewVicControl->btnLockCursor->SetOn(true);
	}
}

void CViewC64VicDisplay::UnlockCursor()
{
	isCursorLocked = false;
	
	if (viewVicControl)
	{
		viewVicControl->btnLockCursor->SetOn(false);
	}
}

void CViewC64VicDisplay::ToggleVICRasterBreakpoint()
{
	LOGM("CViewC64VicDisplay::ToggleVICRasterBreakpoint");

	int rasterLine;

	if (viewC64->isShowingRasterCross)
	{
		rasterLine = viewC64->rasterToShowY;
	}
	else
	{
		rasterLine = (int)(rasterCursorPosY) + 0x32;
	}
	

	if (rasterLine >= 0 && rasterLine <= 0x137)
	{
		char *buf = SYS_GetCharBuf();
		
		viewC64->debugInterface->LockMutex();

		std::map<uint16, C64AddrBreakpoint *> *breakpointsMap = &(viewC64->debugInterface->breakpointsC64Raster);

		// find if breakpoint exists
		std::map<uint16, C64AddrBreakpoint *>::iterator it = breakpointsMap->find(rasterLine);
		
		if (it == breakpointsMap->end())
		{
			C64AddrBreakpoint *addrBreakpoint = new C64AddrBreakpoint(rasterLine);
			(*breakpointsMap)[addrBreakpoint->addr] = addrBreakpoint;
			
			sprintf(buf, "Created raster breakpoint line $%03X", rasterLine);
		}
		else
		{
			C64AddrBreakpoint *breakpoint = it->second;
			breakpointsMap->erase(it);
			delete breakpoint;
			
			sprintf(buf, "Deleted raster breakpoint line $%03X", rasterLine);
		}

		if (breakpointsMap->empty())
		{
			viewC64->debugInterface->breakOnC64Raster = false;
		}
		else
		{
			viewC64->debugInterface->breakOnC64Raster = true;
		}

		
		viewC64->debugInterface->UnlockMutex();
		
		guiMain->ShowMessage(buf);
		SYS_ReleaseCharBuf(buf);
	}
}


bool CViewC64VicDisplay::KeyDown(u32 keyCode, bool isShift, bool isAlt, bool isControl)
{
	if (keyCode == MTKEY_ARROW_UP
		|| keyCode == MTKEY_ARROW_DOWN
		|| keyCode == MTKEY_ARROW_LEFT
		|| keyCode == MTKEY_ARROW_RIGHT)
	{
		arrowKeyDown = true;
		
		LockCursor();

		if (keyCode == MTKEY_ARROW_LEFT)
		{
			for (int i = 0; i < 8; i++)
				RasterCursorLeft();
			
			if (isShift)
			{
				for (int i = 0; i < 8*4; i++)
					RasterCursorLeft();
			}
		}
		else if (keyCode == MTKEY_ARROW_RIGHT)
		{
			for (int i = 0; i < 8; i++)
				RasterCursorRight();
			if (isShift)
			{
				for (int i = 0; i < 8; i++)
					RasterCursorRight();
			}
		}
		else if (keyCode == MTKEY_ARROW_UP)
		{
			RasterCursorUp();
			if (isShift)
			{
				for (int i = 0; i < 7; i++)
					RasterCursorUp();
			}
		}
		else if (keyCode == MTKEY_ARROW_DOWN)
		{
			RasterCursorDown();
			if (isShift)
			{
				for (int i = 0; i < 7; i++)
					RasterCursorDown();
			}
		}
		
		if (canScrollDisassemble == true)
		{
			if (autoScrollMode == AUTOSCROLL_DISASSEMBLE_RASTER_PC)
			{
				viewC64->viewC64Disassemble->isTrackingPC = true;
			}
			else
			{
				viewC64->viewC64Disassemble->isTrackingPC = false;
				ScrollMemoryAndDisassembleToRasterPosition(rasterCursorPosX, rasterCursorPosY, true);
			}
		}
		
		return true;
	}

	if (viewVicControl)
	{
		if (viewVicControl->KeyDown(keyCode, isShift, isAlt, isControl))
			return true;
	}

	//
	CSlrKeyboardShortcut *keyboardShortcut = viewC64->keyboardShortcuts->FindShortcut(shortcutZones, keyCode, isShift, isAlt, isControl);
	
	if (keyboardShortcut == viewC64->keyboardShortcuts->kbsToggleBreakpoint)
	{
		ToggleVICRasterBreakpoint();
		
		viewC64->viewC64Screen->KeyUpModifierKeys(isShift, isAlt, isControl);
		return true;
	}

	
	return false; //CGuiView::KeyDown(keyCode, isShift, isAlt, isControl);
}

bool CViewC64VicDisplay::KeyUp(u32 keyCode, bool isShift, bool isAlt, bool isControl)
{
	if (keyCode == MTKEY_ARROW_UP
		|| keyCode == MTKEY_ARROW_DOWN
		|| keyCode == MTKEY_ARROW_LEFT
		|| keyCode == MTKEY_ARROW_RIGHT)
	{
		arrowKeyDown = false;
	}

	return CGuiView::KeyUp(keyCode, isShift, isAlt, isControl);
}

bool CViewC64VicDisplay::KeyPressed(u32 keyCode, bool isShift, bool isAlt, bool isControl)
{
	return CGuiView::KeyPressed(keyCode, isShift, isAlt, isControl);
}

void CViewC64VicDisplay::ActivateView()
{
	LOGG("CViewC64VicDisplay::ActivateView()");
	
	backupRenderDataWithColors = viewC64->viewC64MemoryDataDump->renderDataWithColors;
	viewC64->viewC64MemoryDataDump->renderDataWithColors = true;
}

void CViewC64VicDisplay::DeactivateView()
{
	LOGG("CViewC64VicDisplay::DeactivateView()");
	
	if (!isCursorLocked)
	{
		viewC64->viewC64MemoryDataDump->renderDataWithColors = backupRenderDataWithColors;

		ResetCursorLock();
		
		UpdateRasterCursorPos();
		UpdateViciiState();
	}
	
}


void CViewC64VicDisplay::ResetCursorLock()
{
	rasterCursorPosX = -1;
	rasterCursorPosY = -1;
}
