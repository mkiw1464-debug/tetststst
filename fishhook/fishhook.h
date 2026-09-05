#ifndef fishhook_h
#define fishhook_h

#include <stddef.h>
#include <stdint.h>

#if defined(__cplusplus)
extern "C" {
#endif

struct rebinding {
    const char *name;
    void *replacement;
    void **replaced;
};

#if defined(__cplusplus)
}
#endif

#if defined(__cplusplus)
extern "C" {
#endif

FISHHOOK_EXPORT int rebind_symbols(struct rebinding rebindings[],
                                   size_t rebindings_nel);

FISHHOOK_EXPORT int rebind_symbols_image(void *header,
                                         intptr_t slide,
                                         struct rebinding rebindings[],
                                         size_t rebindings_nel);

#if defined(__cplusplus)
}
#endif

#endif /* fishhook_h */
