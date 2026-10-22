#include "global.h"

#include "InputHandler_SDL.h"

#include <SDL.h>

#include <chrono>
#include <cstddef>
#include <thread>
#include <vector>

#include "RageLog.h"
#include "RageTimer.h"

REGISTER_INPUT_HANDLER_CLASS2(SDL, SDL);

namespace {

// Stick and trigger travel that counts as a press.
constexpr Sint16 kAxisThreshold = 16384;
// Polling period of the input thread; it also timestamps the presses.
constexpr std::chrono::milliseconds kPollInterval(1);
// Hotplug scans run every this many polls.
constexpr int kPollsPerScan = 500;

struct PadInput {
  enum Kind { kButton, kAxisNegative, kAxisPositive } kind;
  int sdl_index;  // SDL_GameControllerButton or SDL_GameControllerAxis
  DeviceButton button;
};

const std::vector<PadInput>& PadInputs() {
  static const std::vector<PadInput> inputs = [] {
    std::vector<PadInput> v;
    for (int b = SDL_CONTROLLER_BUTTON_A; b <= SDL_CONTROLLER_BUTTON_RIGHTSHOULDER;
         ++b) {
      v.push_back({PadInput::kButton, b, enum_add2(JOY_BUTTON_1, b)});
    }
    v.push_back({PadInput::kButton, SDL_CONTROLLER_BUTTON_DPAD_UP, JOY_HAT_UP});
    v.push_back(
        {PadInput::kButton, SDL_CONTROLLER_BUTTON_DPAD_DOWN, JOY_HAT_DOWN});
    v.push_back(
        {PadInput::kButton, SDL_CONTROLLER_BUTTON_DPAD_LEFT, JOY_HAT_LEFT});
    v.push_back(
        {PadInput::kButton, SDL_CONTROLLER_BUTTON_DPAD_RIGHT, JOY_HAT_RIGHT});
    v.push_back(
        {PadInput::kAxisPositive, SDL_CONTROLLER_AXIS_TRIGGERLEFT, JOY_BUTTON_12});
    v.push_back(
        {PadInput::kAxisPositive, SDL_CONTROLLER_AXIS_TRIGGERRIGHT,
         JOY_BUTTON_13});
    v.push_back({PadInput::kAxisNegative, SDL_CONTROLLER_AXIS_LEFTX, JOY_LEFT});
    v.push_back({PadInput::kAxisPositive, SDL_CONTROLLER_AXIS_LEFTX, JOY_RIGHT});
    v.push_back({PadInput::kAxisNegative, SDL_CONTROLLER_AXIS_LEFTY, JOY_UP});
    v.push_back({PadInput::kAxisPositive, SDL_CONTROLLER_AXIS_LEFTY, JOY_DOWN});
    v.push_back(
        {PadInput::kAxisNegative, SDL_CONTROLLER_AXIS_RIGHTX, JOY_LEFT_2});
    v.push_back(
        {PadInput::kAxisPositive, SDL_CONTROLLER_AXIS_RIGHTX, JOY_RIGHT_2});
    v.push_back({PadInput::kAxisNegative, SDL_CONTROLLER_AXIS_RIGHTY, JOY_UP_2});
    v.push_back(
        {PadInput::kAxisPositive, SDL_CONTROLLER_AXIS_RIGHTY, JOY_DOWN_2});
    return v;
  }();
  return inputs;
}

bool IsDown(SDL_GameController* controller, const PadInput& input) {
  switch (input.kind) {
    case PadInput::kButton:
      return SDL_GameControllerGetButton(
                 controller,
                 static_cast<SDL_GameControllerButton>(input.sdl_index)) != 0;
    case PadInput::kAxisNegative:
      return SDL_GameControllerGetAxis(
                 controller,
                 static_cast<SDL_GameControllerAxis>(input.sdl_index)) <=
             -kAxisThreshold;
    case PadInput::kAxisPositive:
      return SDL_GameControllerGetAxis(
                 controller,
                 static_cast<SDL_GameControllerAxis>(input.sdl_index)) >=
             kAxisThreshold;
  }
  return false;
}

}  // namespace

InputHandler_SDL::InputHandler_SDL()
    : m_InputMutex("InputHandler_SDL"),
      m_bShutdown(false),
      m_bDevicesChanged(false) {
  // Nothing pumps SDL events in this engine: the input thread updates the
  // controllers itself and reads their state, so keep events out of the queue
  // and keep reading while the window is unfocused.
  SDL_SetHint(SDL_HINT_JOYSTICK_ALLOW_BACKGROUND_EVENTS, "1");
  SDL_SetHint(SDL_HINT_AUTO_UPDATE_JOYSTICKS, "0");
  if (SDL_InitSubSystem(SDL_INIT_GAMECONTROLLER) != 0) {
    LOG->Warn("SDL: couldn't init game controllers: %s", SDL_GetError());
    m_bShutdown = true;
    return;
  }
  SDL_GameControllerEventState(SDL_IGNORE);
  SDL_JoystickEventState(SDL_IGNORE);

  ScanDevices();
  m_InputThread.SetName("SDL input thread");
  m_InputThread.Create(InputThread_Start, this);
}

InputHandler_SDL::~InputHandler_SDL() {
  if (m_InputThread.IsCreated()) {
    m_bShutdown = true;
    m_InputThread.Wait();
  }
  for (Pad& pad : m_Pads) {
    if (pad.controller != nullptr) {
      SDL_GameControllerClose(pad.controller);
    }
  }
  SDL_QuitSubSystem(SDL_INIT_GAMECONTROLLER);
}

int InputHandler_SDL::InputThread_Start(void* p) {
  static_cast<InputHandler_SDL*>(p)->InputThread();
  return 0;
}

void InputHandler_SDL::InputThread() {
  const std::vector<PadInput>& inputs = PadInputs();
  int polls_until_scan = kPollsPerScan;
  while (!m_bShutdown) {
    if (--polls_until_scan == 0) {
      ScanDevices();
      polls_until_scan = kPollsPerScan;
    }
    SDL_GameControllerUpdate();
    RageTimer now;
    for (int slot = 0; slot < NUM_JOYSTICKS; ++slot) {
      Pad& pad = m_Pads[slot];
      if (pad.controller == nullptr) {
        continue;
      }
      for (std::size_t i = 0; i < inputs.size(); ++i) {
        bool down = IsDown(pad.controller, inputs[i]);
        if (down != pad.pressed[i]) {
          pad.pressed[i] = down;
          ButtonPressed(DeviceInput(
              enum_add2(DEVICE_JOY1, slot), inputs[i].button,
              down ? 1.0f : 0.0f, now));
        }
      }
    }
    std::this_thread::sleep_for(kPollInterval);
  }
}

void InputHandler_SDL::ReleaseAll(int slot) {
  Pad& pad = m_Pads[slot];
  const std::vector<PadInput>& inputs = PadInputs();
  RageTimer now;
  for (std::size_t i = 0; i < inputs.size(); ++i) {
    if (pad.pressed[i]) {
      pad.pressed[i] = false;
      ButtonPressed(DeviceInput(
          enum_add2(DEVICE_JOY1, slot), inputs[i].button, 0.0f, now));
    }
  }
}

// Runs on the main thread from the constructor, then only on the input thread.
void InputHandler_SDL::ScanDevices() {
  SDL_GameControllerUpdate();  // also detects added and removed devices

  for (int slot = 0; slot < NUM_JOYSTICKS; ++slot) {
    Pad& pad = m_Pads[slot];
    if (pad.controller == nullptr || SDL_GameControllerGetAttached(pad.controller)) {
      continue;
    }
    LOG->Info("SDL: Joy%d disconnected", slot + 1);
    ReleaseAll(slot);
    SDL_GameControllerClose(pad.controller);
    LockMut(m_InputMutex);
    pad = Pad();
    m_bDevicesChanged = true;
  }

  for (int index = 0; index < SDL_NumJoysticks(); ++index) {
    if (!SDL_IsGameController(index)) {
      continue;
    }
    int instance_id = SDL_JoystickGetDeviceInstanceID(index);
    int free_slot = -1;
    bool open = false;
    for (int slot = 0; slot < NUM_JOYSTICKS; ++slot) {
      if (m_Pads[slot].controller == nullptr) {
        if (free_slot < 0) {
          free_slot = slot;
        }
      } else if (m_Pads[slot].instance_id == instance_id) {
        open = true;
      }
    }
    if (open || free_slot < 0) {
      continue;
    }
    SDL_GameController* controller = SDL_GameControllerOpen(index);
    if (controller == nullptr) {
      LOG->Warn("SDL: couldn't open controller %d: %s", index, SDL_GetError());
      continue;
    }
    LOG->Info(
        "SDL: \"%s\" is Joy%d", SDL_GameControllerName(controller),
        free_slot + 1);
    LockMut(m_InputMutex);
    Pad& pad = m_Pads[free_slot];
    pad.controller = controller;
    pad.instance_id = instance_id;
    pad.pressed.assign(PadInputs().size(), false);
    m_bDevicesChanged = true;
  }
}

void InputHandler_SDL::GetDevicesAndDescriptions(
    std::vector<InputDeviceInfo>& vDevicesOut) {
  LockMut(m_InputMutex);
  for (int slot = 0; slot < NUM_JOYSTICKS; ++slot) {
    if (m_Pads[slot].controller != nullptr) {
      vDevicesOut.push_back(InputDeviceInfo(
          enum_add2(DEVICE_JOY1, slot),
          SDL_GameControllerName(m_Pads[slot].controller)));
    }
  }
  m_bDevicesChanged = false;
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
