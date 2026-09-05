#pragma once
#include <stdint.h>
#include <dlfcn.h>
#include <mach/mach.h>

static uintptr_t GetImageBase() {
    static uintptr_t base = 0;
    if (!base) {
        Dl_info info;
        // Use a known symbol from the binary
        if (dladdr((void*)&GetImageBase, &info))
            base = (uintptr_t)info.dli_fbase;
    }
    return base;
}

static uintptr_t GetOffset(uintptr_t offset) {
    return GetImageBase() + offset;
}

template<typename T>
static T Read(uintptr_t addr) {
    if (!addr) return T{};
    return *reinterpret_cast<T*>(addr);
}

template<typename T>
static void Write(uintptr_t addr, T val) {
    if (!addr) return;
    *reinterpret_cast<T*>(addr) = val;
}
