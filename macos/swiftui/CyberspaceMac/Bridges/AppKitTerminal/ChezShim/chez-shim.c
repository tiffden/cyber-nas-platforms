/*
 * chez-shim.c - Minimal C shim for Chez Scheme macros
 * Library of Cyberspace
 *
 * 4 functions. Zero stdlib. Zero malloc.
 * Wraps Chez Scheme preprocessor macros (Sstring_length, Sstring_ref,
 * Seof_object) as callable C functions for Swift.
 *
 * Everything else in the Chez API is already exported as functions
 * from libkernel.a and can be called directly from Swift.
 *
 * Copyright (c) 2026 Yoyodyne. See LICENSE.
 */

#include <scheme.h>

long chez_string_length(long s) {
    return (long)Sstring_length((ptr)s);
}

int chez_string_ref(long s, long i) {
    return (int)Sstring_ref((ptr)s, (iptr)i);
}

int chez_is_string(long s) {
    return Sstringp((ptr)s);
}

long chez_eof_object(void) {
    return (long)Seof_object;
}
