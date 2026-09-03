// CubicLM vendored fix (part 2 of 2 — see ../pubspec.yaml note).
//
// Upstream speech_to_text_windows ships no public plugin header under
// windows/include/<plugin>/, so the generated registrant's
//   #include <speech_to_text_windows/speech_to_text_windows_plugin.h>
// can never resolve (fatal C1083). The real header lives one level up;
// forward to it. Native code is untouched.
#include "../../speech_to_text_windows_plugin.h"
