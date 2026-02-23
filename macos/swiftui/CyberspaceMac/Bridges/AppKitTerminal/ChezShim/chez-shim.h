/*
 * chez-shim.h - Chez Scheme API declarations for Swift
 * Library of Cyberspace
 *
 * Forward-declares the Chez Scheme C API functions that Swift needs.
 * We declare these directly rather than importing <scheme.h> because
 * scheme.h uses macros, complex typedefs, and conditional compilation
 * that Swift's Clang importer cannot fully handle.
 *
 * Most functions live directly in libkernel.a. Four are macros in
 * scheme.h (Sstringp, Sstring_length, Sstring_ref, Seof_object) --
 * chez-shim.c wraps them as callable C functions.
 *
 * Types are ABI-compatible with Chez's ptr/iptr (both long on ARM64).
 *
 * Copyright (c) 2026 Yoyodyne. See LICENSE.
 */

#ifndef CHEZ_SHIM_H
#define CHEZ_SHIM_H

#include <stddef.h>

/* Chez Scheme's ptr: a tagged machine word (long on 64-bit) */
typedef long ChezPtr;
typedef long ChezIptr;

/* Runtime lifecycle */
void Sscheme_init(void (*custom_init)(void));
void Sregister_boot_file(const char *path);
void Sbuild_heap(const char *exec_name, void (*custom_init)(void));
void Sscheme_deinit(void);

/* Symbol and string creation */
ChezPtr Sstring_to_symbol(const char *s);
ChezPtr Sstring(const char *s);

/* Top-level value lookup */
ChezPtr Stop_level_value(ChezPtr sym);

/* Procedure calls (0-2 args) */
ChezPtr Scall0(ChezPtr proc);
ChezPtr Scall1(ChezPtr proc, ChezPtr arg);
ChezPtr Scall2(ChezPtr proc, ChezPtr a1, ChezPtr a2);

/* String inspection -- macros in scheme.h, wrapped in chez-shim.c */
int chez_is_string(ChezPtr s);
ChezIptr chez_string_length(ChezPtr s);
int chez_string_ref(ChezPtr s, ChezIptr i);

/* EOF sentinel -- macro in scheme.h, wrapped in chez-shim.c */
ChezPtr chez_eof_object(void);

/* GC pinning -- prevent collection/relocation of long-lived objects */
void Slock_object(ChezPtr x);
void Sunlock_object(ChezPtr x);

#endif /* CHEZ_SHIM_H */
