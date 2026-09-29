/*
 * Smoke test for an installed libnrsc5.
 *
 * Loads the library by absolute path, resolves the core entry points, opens
 * and closes a pipe-input decoder, and prints the library version and the
 * symbols it found.
 *
 * usage: smoketest /absolute/path/to/libnrsc5.(so|dylib|dll)
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include <nrsc5.h>

#ifdef _WIN32
#include <windows.h>
#ifndef LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR
#define LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR 0x00000100
#endif
#ifndef LOAD_LIBRARY_SEARCH_DEFAULT_DIRS
#define LOAD_LIBRARY_SEARCH_DEFAULT_DIRS 0x00001000
#endif
typedef HMODULE lib_t;
#else
#include <dlfcn.h>
typedef void *lib_t;
#endif

typedef void (*get_version_fn)(const char **version);
typedef int (*open_pipe_fn)(nrsc5_t **st);
typedef void (*close_fn)(nrsc5_t *st);

static int fail(const char *what, const char *detail)
{
    fprintf(stderr, "FAIL: %s%s%s\n", what, detail ? ": " : "", detail ? detail : "");
    return 1;
}

static int is_absolute(const char *path)
{
#ifdef _WIN32
    return (path[0] && path[1] == ':' && (path[2] == '\\' || path[2] == '/')) ||
           (path[0] == '\\' && path[1] == '\\');
#else
    return path[0] == '/';
#endif
}

static lib_t load_library(const char *path)
{
#ifdef _WIN32
    wchar_t wpath[32768];
    wchar_t *c;
    if (!MultiByteToWideChar(CP_UTF8, 0, path, -1, wpath, sizeof(wpath) / sizeof(wpath[0])))
        return NULL;
    /* LOAD_LIBRARY_SEARCH_* flags only accept backslashes in a full path */
    for (c = wpath; *c; c++)
        if (*c == L'/')
            *c = L'\\';
    return LoadLibraryExW(wpath, NULL, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
#else
    return dlopen(path, RTLD_NOW);
#endif
}

static void *find_symbol(lib_t lib, const char *name)
{
#ifdef _WIN32
    return (void *)GetProcAddress(lib, name);
#else
    return dlsym(lib, name);
#endif
}

static const char *load_error(void)
{
#ifdef _WIN32
    static char msg[64];
    snprintf(msg, sizeof(msg), "Windows error %lu", (unsigned long)GetLastError());
    return msg;
#else
    const char *err = dlerror();
    return err ? err : "unknown error";
#endif
}

int main(int argc, char *argv[])
{
    static const char *const required[] = {
        "nrsc5_get_version", "nrsc5_open_pipe", "nrsc5_set_mode", "nrsc5_set_callback", "nrsc5_close",
    };
    static const char *const optional[] = {
        "nrsc5_pipe_samples_cf32", "nrsc5_pipe_samples_cs16",
    };
    void *required_fn[sizeof(required) / sizeof(required[0])];
    lib_t lib;
    const char *version = NULL;
    nrsc5_t *st = NULL;
    size_t i;

    if (argc != 2)
        return fail("usage: smoketest /absolute/path/to/libnrsc5", NULL);
    if (!is_absolute(argv[1]))
        return fail("library path must be absolute", argv[1]);

    lib = load_library(argv[1]);
    if (!lib)
        return fail("cannot load library", load_error());

    printf("library: %s\n", argv[1]);
    printf("resolved:");
    for (i = 0; i < sizeof(required) / sizeof(required[0]); i++)
    {
        required_fn[i] = find_symbol(lib, required[i]);
        if (!required_fn[i])
        {
            printf("\n");
            return fail("missing symbol", required[i]);
        }
        printf(" %s", required[i]);
    }
    for (i = 0; i < sizeof(optional) / sizeof(optional[0]); i++)
    {
        if (find_symbol(lib, optional[i]))
            printf(" %s", optional[i]);
    }
    printf("\n");

    ((get_version_fn)required_fn[0])(&version);
    printf("version: %s\n", version ? version : "(null)");

    if (((open_pipe_fn)required_fn[1])(&st) != 0 || !st)
        return fail("nrsc5_open_pipe returned an error", NULL);
    ((close_fn)required_fn[4])(st);
    printf("open_pipe/close: ok\n");
    return 0;
}
