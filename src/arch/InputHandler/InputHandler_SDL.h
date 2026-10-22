#ifndef INPUT_HANDLER_SDL_H
#define INPUT_HANDLER_SDL_H

#include <vector>

#include "InputHandler.h"
#include "RageInputDevice.h"
#include "RageThreads.h"

struct _SDL_GameController;

// Gamepads through SDL's GameController API, so any pad with a mapping in
// SDL_GAMECONTROLLERCONFIG (PortMaster sets one per device) reports the same
// buttons: controllers are DEVICE_JOY1.., face/system buttons JOY_BUTTON_1 +
// SDL_GameControllerButton (A=1, B=2, X=3, Y=4, Back=5, Guide=6, Start=7,
// L3=8, R3=9, L1=10, R1=11), triggers JOY_BUTTON_12/13, the D-pad the
// JOY_HAT_* buttons and the sticks JOY_LEFT.. / JOY_LEFT_2...
class InputHandler_SDL : public InputHandler {
 public:
  InputHandler_SDL();
  ~InputHandler_SDL();
  bool DevicesChanged() { return m_bDevicesChanged; }
  void GetDevicesAndDescriptions(std::vector<InputDeviceInfo>& vDevicesOut);

 private:
  struct Pad {
    _SDL_GameController* controller = nullptr;
    int instance_id = -1;
    std::vector<bool> pressed;
  };

  static int InputThread_Start(void* p);
  void InputThread();
  void ScanDevices();
  void ReleaseAll(int slot);

  RageThread m_InputThread;
  RageMutex m_InputMutex;  // guards m_Pads' controllers and m_bDevicesChanged
  Pad m_Pads[NUM_JOYSTICKS];
  bool m_bShutdown;
  bool m_bDevicesChanged;
};

#endif

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
