/* Declarations OUTSIDE the file under test: what the tracking must report as used from sample.c */
#include <stddef.h>

#define SCALE(x) ((x) * 2)

typedef int count_t;

typedef struct point { int x; int y; } point_t;

typedef union value { int i; float f; } value_t;

extern int global_counter;

int helper(int v);
