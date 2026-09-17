#ifndef LaunchDockSwipe_h
#define LaunchDockSwipe_h

#include <stdbool.h>
#include <stdint.h>

bool LaunchDockSwipePrepare(void);
bool LaunchDockSwipePost(double progress, double velocity, uint32_t phase);

#endif
