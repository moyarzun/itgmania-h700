/* LowLevelWindow_SDL - SDL2 window driver, for Linux targets with no X11/
 * Wayland/DRM-KMS available (e.g. handhelds exposing only a vendor "mali"
 * fbdev+EGL+GLESv2 blob). See LowLevelWindow_SDL.cpp for the full rationale;
 * this intentionally does not replicate LowLevelWindow_X11's multi-monitor/
 * XRandR/window-manager handling, since the target is always a single fixed
 * display with no window manager. */

#ifndef LOW_LEVEL_WINDOW_SDL_H
#define LOW_LEVEL_WINDOW_SDL_H

#include "RageDisplay.h" // VideoModeParams
#include "LowLevelWindow.h"

struct SDL_Window;
typedef void *SDL_GLContext;

class LowLevelWindow_SDL : public LowLevelWindow
{
public:
	LowLevelWindow_SDL();
	~LowLevelWindow_SDL();

	void *GetProcAddress( std::string s );
	std::string TryVideoMode( const VideoModeParams &p, bool &bNewDeviceOut );
	void SwapBuffers();

	const ActualVideoModeParams GetActualVideoModeParams() const { return CurrentParams; }
	void GetDisplaySpecs( DisplaySpecs &out ) const;

private:
	SDL_Window *m_pWindow;
	SDL_GLContext m_GLContext;
	ActualVideoModeParams CurrentParams;
};

#ifdef ARCH_LOW_LEVEL_WINDOW
#error "More than one LowLevelWindow selected!"
#endif
#define ARCH_LOW_LEVEL_WINDOW LowLevelWindow_SDL

#endif
