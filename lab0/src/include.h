#include <errno.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

#define DEBUG

#ifdef DEBUG
#define dprint(...) (printf(__VA_ARGS__))
#else
#define dprint(...)
#endif

/**
 * @brief Evaluates an expression and handles errors if the result is -1.
 *
 * This macro evaluates `expr` and checks if it results in
 * `-1`. If the result is `-1`, it prints an error message using `perror` with
 * the string repr of `expr` and exits with the error code stored in `errno`.
 *
 * @param expr The expression to evaluate. Used for syscalls or
 *             functions that return `-1` to indicate failure.
 *
 * @return The result of the evaluated expression if it does not equal `-1`.
 */
#define try(expr)               \
  ({                            \
    typeof(expr) _val = (expr); \
    if (_val == -1) {           \
      perror(#expr);            \
      exit(errno);              \
    }                           \
    _val;                       \
  })

#define ERROR(expr)               \
  ({                              \
    dprint("Error: %s\n", #expr); \
    exit(EXIT_FAILURE);           \
  })
