#include <TargetConditionals.h>

#if TARGET_OS_SIMULATOR
#include <mach-o/arch.h>

// Rive 0.0.16 dereferences NXGetLocalArchInfo(), which returns NULL for newer
// Mac CPU subtypes. The Podfile redirects only Rive's simulator lookup here.
// Remove when Rive no longer relies on that deprecated host-CPU lookup.
const NXArchInfo *EnteRiveSimulatorArchInfo(void) {
#if defined(__arm64__)
  return NXGetArchInfoFromCpuType(CPU_TYPE_ARM64, CPU_SUBTYPE_MULTIPLE);
#elif defined(__x86_64__)
  return NXGetArchInfoFromCpuType(CPU_TYPE_X86_64, CPU_SUBTYPE_MULTIPLE);
#else
#error Unsupported iOS simulator architecture
#endif
}
#endif
