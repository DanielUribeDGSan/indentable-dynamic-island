# Dynamic Island

Isla flotante para macOS. Se abre junto al puntero con tres pulsaciones de Comando, lee el texto que seleccionas y lo responde con el modelo de Gemini u OpenAI que guardes.

La ventana se ve en tu pantalla y queda fuera de las capturas, grabaciones y comparticiones que usan la API pública de exclusión de ventanas.

## Uso

1. `./run.sh`
2. Concede Accesibilidad cuando macOS lo pida.
3. Pulsa Comando tres veces. Otras tres la cierran.
4. En el engrane, pega la API key, carga los modelos y guarda.

La respuesta espera a que sueltes la selección. El texto llega con negritas, listas y bloques de código.

## Piezas

- SwiftUI / AppKit para la isla.
- Rust para listar modelos y pedir la respuesta.
