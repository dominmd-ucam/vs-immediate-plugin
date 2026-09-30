---
name: vs-watch
description: Sigue cómo cambian uno o varios valores a lo largo de varias pausas del depurador de Visual Studio (por ejemplo un contador, el tamaño de una colección o un estado) usando vs-immediate. Usar cuando el usuario quiere ver la evolución de un valor entre ejecuciones de un mismo punto, o buscar en qué iteración cambia algo.
---

# vs-watch

Toma una instantánea de varias expresiones en la pausa actual, continúa, espera a la siguiente pausa y repite. Usa `vs-watch.ps1` de `..\vs-immediate\scripts`.

## Cuándo sirve

- "¿En qué iteración del bucle deja de valer lo que debería?"
- "¿Cómo va cambiando el estado de X cada vez que pasa por aquí?"
- Comparar valores entre peticiones sucesivas sin ir paso a paso a mano.

Si solo necesitas ver el valor una vez, usa `vs-eval`. Si el punto se ejecuta cientos de veces y solo quieres un rastro sin parar, mira `AddTracepoint` en `vs-control`.

## Preparación

1. Debe haber una pausa en el punto de interés (break mode). Usa un breakpoint en la línea donde el valor es significativo.
2. Si ese punto se ejecuta con tráfico ajeno, ponle una condición (`-Condition`) para que solo salte con el caso que investigas; si no, mezclarás datos de casos distintos.
3. Elige expresiones baratas y de solo lectura: campos, propiedades simples, `.Count` de colecciones. Evita llamadas a métodos.

## Uso

```
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<base>\..\vs-immediate\scripts\vs-watch.ps1" -Expressions "i,,lista.Count,,estado" -Iterations 8 -WaitSeconds 30
```

- Las expresiones van separadas por `,,` (un solo argumento).
- `-Iterations` máximo 50. `-WaitSeconds` es la espera máxima a que haya una nueva pausa.
- Continúa la ejecución real de la aplicación entre instantáneas: pide confirmación al usuario antes, sobre todo en servidores con peticiones vivas o con efectos externos.

## Resultado

Devuelve una lista de instantáneas (`n`, función, línea, valores). Si no vuelve a haber pausa dentro del tiempo de espera o la sesión termina, lo indica en `note`; en el primer caso la aplicación queda **en ejecución**, no en pausa.

## Cómo presentarlo

Una tabla corta con una fila por instantánea y una columna por expresión, y debajo la conclusión: en qué iteración cambia el patrón y qué hipótesis apoya. No pegues el JSON completo.
