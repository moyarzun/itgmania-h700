/* LowLevelWindow_SDL
 *
 * Why this exists: upstream StepMania's only Linux LowLevelWindow backend
 * is LowLevelWindow_X11 (GLX, requires a running X server). Our target is a
 * handheld with no X11, no Wayland, and no /dev/dri (no DRM/KMS at all) --
 * the only working graphics path is the vendor's "mali" fbdev+EGL+GLESv2
 * blob, which muOS's own SDL2 build exposes as an SDL_VIDEODRIVER named
 * exactly "mali" (see h700/README.md).
 *
 * Unlike LowLevelWindow_X11, this does not need to handle multiple
 * monitors, a window manager, or XRandR mode-setting gymnastics: the target
 * is always exactly one fixed-resolution display with no compositor at
 * all, so TryVideoMode/GetDisplaySpecs are deliberately much simpler than
 * their X11 counterparts.
 */
#include "global.h"
#include "LowLevelWindow_SDL.h"
#include "RageLog.h"
#include "RageException.h"
#include "DisplaySpec.h"
#include "LocalizedString.h"

#include <SDL2/SDL.h>

static LocalizedString FAILED_SDL_INIT( "LowLevelWindow_SDL", "Failed to initialize SDL video" );

LowLevelWindow_SDL::LowLevelWindow_SDL():
	m_pWindow( nullptr ),
	m_GLContext( nullptr )
{
	if( SDL_InitSubSystem( SDL_INIT_VIDEO ) != 0 )
		RageException::Throw( "%s: %s", FAILED_SDL_INIT.GetValue().c_str(), SDL_GetError() );

	LOG->Info( "SDL video driver: %s", SDL_GetCurrentVideoDriver() );
}

LowLevelWindow_SDL::~LowLevelWindow_SDL()
{
	if( m_GLContext != nullptr )
		SDL_GL_DeleteContext( m_GLContext );
	if( m_pWindow != nullptr )
		SDL_DestroyWindow( m_pWindow );
	SDL_QuitSubSystem( SDL_INIT_VIDEO );
}

void *LowLevelWindow_SDL::GetProcAddress( std::string s )
{
	return SDL_GL_GetProcAddress( s.c_str() );
}

std::string LowLevelWindow_SDL::TryVideoMode( const VideoModeParams &p, bool &bNewDeviceOut )
{
	// StepMania calls TryVideoMode() far more often than "at startup / when
	// video prefs change" -- e.g. simply entering or leaving a screen under
	// Options re-applies the current video mode unconditionally, with no
	// actual change in width/height/bpp/windowed. bNewDeviceOut=true tells
	// the engine the GL device was lost, forcing a full texture reload *and*
	// an InputHandler teardown+recreate (which re-enumerates every evdev
	// device from scratch). Since this implementation used to always
	// destroy+recreate the SDL window/GL context here regardless of whether
	// anything changed, every such menu visit produced a visible black-
	// screen flash, an audio underrun (main thread stalls during the
	// teardown+recreate), and a momentary input outage -- all reported by a
	// real user navigating Options. Skip the recreate when the mode that
	// actually matters here (this device has one fixed-resolution,
	// always-fullscreen display, so windowed/width/height/bpp are the only
	// fields that would ever require a new window) hasn't changed.
	bool bModeUnchanged = m_pWindow != nullptr
		&& p.windowed == CurrentParams.windowed
		&& p.width == CurrentParams.width
		&& p.height == CurrentParams.height
		&& p.bpp == CurrentParams.bpp;

	if( bModeUnchanged )
	{
		bNewDeviceOut = false;
		if( p.vsync != CurrentParams.vsync )
			SDL_GL_SetSwapInterval( p.vsync ? 1 : 0 );

		int windowWidth = CurrentParams.windowWidth;
		int windowHeight = CurrentParams.windowHeight;
		int rate = CurrentParams.rate;
		CurrentParams = p;
		CurrentParams.windowWidth = windowWidth;
		CurrentParams.windowHeight = windowHeight;
		CurrentParams.renderOffscreen = false;
		CurrentParams.rate = rate;
		return ""; // Success, nothing to recreate.
	}

	bNewDeviceOut = true;

	if( m_GLContext != nullptr )
	{
		SDL_GL_DeleteContext( m_GLContext );
		m_GLContext = nullptr;
	}
	if( m_pWindow != nullptr )
	{
		SDL_DestroyWindow( m_pWindow );
		m_pWindow = nullptr;
	}

	ASSERT( p.bpp == 16 || p.bpp == 32 );
	if( p.bpp == 32 )
	{
		SDL_GL_SetAttribute( SDL_GL_RED_SIZE, 8 );
		SDL_GL_SetAttribute( SDL_GL_GREEN_SIZE, 8 );
		SDL_GL_SetAttribute( SDL_GL_BLUE_SIZE, 8 );
	}
	else
	{
		SDL_GL_SetAttribute( SDL_GL_RED_SIZE, 5 );
		SDL_GL_SetAttribute( SDL_GL_GREEN_SIZE, 6 );
		SDL_GL_SetAttribute( SDL_GL_BLUE_SIZE, 5 );
	}
	SDL_GL_SetAttribute( SDL_GL_DEPTH_SIZE, 16 );
	SDL_GL_SetAttribute( SDL_GL_DOUBLEBUFFER, 1 );

	// There is no window manager and no windowed mode on this device --
	// always fullscreen, always the display's native size. p.width/p.height
	// are honored as the requested render resolution regardless.
	Uint32 flags = SDL_WINDOW_OPENGL | SDL_WINDOW_FULLSCREEN_DESKTOP;

	m_pWindow = SDL_CreateWindow( p.sWindowTitle.c_str(),
		SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
		p.width, p.height, flags );
	if( m_pWindow == nullptr )
		return std::string( "SDL_CreateWindow: " ) + SDL_GetError();

	m_GLContext = SDL_GL_CreateContext( m_pWindow );
	if( m_GLContext == nullptr )
		return std::string( "SDL_GL_CreateContext: " ) + SDL_GetError();

	SDL_GL_MakeCurrent( m_pWindow, m_GLContext );
	SDL_GL_SetSwapInterval( p.vsync ? 1 : 0 );

	int windowWidth = 0, windowHeight = 0;
	SDL_GetWindowSize( m_pWindow, &windowWidth, &windowHeight );

	CurrentParams = p;
	CurrentParams.windowWidth = windowWidth;
	CurrentParams.windowHeight = windowHeight;
	CurrentParams.renderOffscreen = false;

	SDL_DisplayMode mode;
	if( SDL_GetWindowDisplayMode( m_pWindow, &mode ) == 0 && mode.refresh_rate > 0 )
		CurrentParams.rate = mode.refresh_rate;
	else
		CurrentParams.rate = 60;

	return ""; // Success
}

void LowLevelWindow_SDL::SwapBuffers()
{
	SDL_GL_SwapWindow( m_pWindow );
}

void LowLevelWindow_SDL::GetDisplaySpecs( DisplaySpecs &out ) const
{
	// Single fixed display, no hotplug/multi-monitor support needed.
	int iDisplay = 0;
	SDL_DisplayMode mode;
	DisplayMode dm = { 640, 480, 60.0 };
	if( SDL_GetCurrentDisplayMode( iDisplay, &mode ) == 0 )
	{
		dm.width = static_cast<unsigned int>( mode.w );
		dm.height = static_cast<unsigned int>( mode.h );
		dm.refreshRate = mode.refresh_rate > 0 ? static_cast<double>( mode.refresh_rate ) : 60.0;
	}
	out.insert( DisplaySpec( "0", "Display", dm ) );
}

/*
 * (c) 2026 itgmania-h700 contributors
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the
 * "Software"), to deal in the Software without restriction, including
 * without limitation the rights to use, copy, modify, merge, publish,
 * distribute, and/or sell copies of the Software, and to permit persons to
 * whom the Software is furnished to do so, provided that the above
 * copyright notice(s) and this permission notice appear in all copies of
 * the Software and that both the above copyright notice(s) and this
 * permission notice appear in supporting documentation.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
 * OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
 * MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT OF
 * THIRD PARTY RIGHTS. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR HOLDERS
 * INCLUDED IN THIS NOTICE BE LIABLE FOR ANY CLAIM, OR ANY SPECIAL INDIRECT
 * OR CONSEQUENTIAL DAMAGES, OR ANY DAMAGES WHATSOEVER RESULTING FROM LOSS
 * OF USE, DATA OR PROFITS, WHETHER IN AN ACTION OF CONTRACT, NEGLIGENCE OR
 * OTHER TORTIOUS ACTION, ARISING OUT OF OR IN CONNECTION WITH THE USE OR
 * PERFORMANCE OF THIS SOFTWARE.
 */
