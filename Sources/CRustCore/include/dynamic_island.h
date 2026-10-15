#ifndef dynamic_island_h
#define dynamic_island_h

#include <stdint.h>

typedef void (*IslandStreamFn)(const char *chunk, int is_error, int is_done, void *ctx);

/// Cadena estática. No liberar.
const char *island_engine_version(void);

/// JSON: {"ok":true,"models":[{"id":"...","label":"..."}]} o {"ok":false,"error":"..."}.
/// Liberar el resultado con island_free_string.
char *island_list_models(const char *provider, const char *api_key);

/// Llama al modelo y entrega la respuesta por trozos. Bloquea hasta terminar.
void island_ask(
    const char *provider,
    const char *api_key,
    const char *model,
    const char *text,
    IslandStreamFn callback,
    void *ctx
);

void island_free_string(char *value);

#endif
