#ifndef ALTIVEC_MODEL_H
#define ALTIVEC_MODEL_H
#ifdef __cplusplus
extern "C" {
#endif
/* A tiny public API; returns the new value, saturating at integer limits. */
int model_add(int value, int delta);
const char *model_version(void);
#ifdef __cplusplus
}
#endif
#endif
