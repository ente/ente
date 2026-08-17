#ifndef RUNNER_UTILS_H_
#define RUNNER_UTILS_H_

#include <string>
#include <vector>

void CreateAndAttachConsole();

std::string Utf8FromUtf16(const wchar_t* utf16_string);

std::vector<std::string> GetCommandLineArguments();

#endif  // RUNNER_UTILS_H_
