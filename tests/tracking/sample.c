/* File under test for the -t tracking smoke test (tests/tracking/run.sh) */
#include "sample.h"

static int local_only(int v) { return v + 1; }

count_t use_all(point_t *p, value_t v)
{
    count_t c = SCALE(p->x) + v.i;
    global_counter += c;
    return helper(local_only(c)) + (int)sizeof(value_t) + (p != NULL);
}
