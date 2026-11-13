#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include "flutter_window.h"
#include "utils.h"

#include "app_links/app_links_plugin_c_api.h"
bool SendAppLinkToInstance(const std::wstring &title)
{
  HWND hwnd = ::FindWindow(L"FLUTTER_RUNNER_WIN32_WINDOW", title.c_str());

  if (hwnd)
  {
    SendAppLink(hwnd);

    WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
    GetWindowPlacement(hwnd, &place);

    switch (place.showCmd)
    {
    case SW_SHOWMAXIMIZED:
      ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ShowWindow(hwnd, SW_NORMAL);
      break;
    }

    SetWindowPos(0, HWND_TOP, 0, 0, 0, 0, SWP_SHOWWINDOW | SWP_NOSIZE | SWP_NOMOVE);
    SetForegroundWindow(hwnd);

    return true;
  }

  return false;
}

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command)
{
  if (SendAppLinkToInstance(L"Ente Auth"))
  {
    return EXIT_SUCCESS;
  }
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent())
  {
    CreateAndAttachConsole();
  }

  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(70, 70);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"Ente Auth", origin, size))
  {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0))
  {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
