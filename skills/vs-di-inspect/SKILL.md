---
name: vs-di-inspect
description: Averigua qué implementación concreta hay detrás de las interfaces inyectadas (inyección de dependencias) en un punto de pausa de Visual Studio, usando vs-immediate. Usar cuando el usuario pregunta "qué implementación se está usando", "por qué se llama a esta clase y no a la otra" o qué hay realmente inyectado.
---

# vs-di-inspect

Responde "qué hay realmente detrás de esta interfaz" en un punto de pausa concreto. Scripts en `..\vs-immediate\scripts`. Requiere depurador en pausa (break mode).

## Cómo funciona

El depurador muestra las variables de tipo interfaz como `Ns.IFoo {Ns.Foo}`: antes de las llaves el tipo declarado, dentro la clase real. `vs-types.ps1` lo separa en `declaredType` y `runtimeType` y **solo lee lo que el depurador ya muestra: no ejecuta métodos de la aplicación**.

## Receta

1. Localiza en el código (Grep/Read) la clase que interesa y qué recibe por constructor. Ahí sabes qué interfaces buscar y dónde se registran (`AddScoped`, `AddTransient`, `services.Add...`).
2. Para en un punto donde `this` sea esa clase (un breakpoint dentro de un método suyo). Si no está parado ahí, propón el breakpoint y confirma antes de arrancar nada.
3. Inspecciona sus dependencias:
   - `vs-types.ps1 -This` lista los campos y propiedades (incluidos los privados) con tipo declarado y real.
   - `-Filter <texto>` reduce la lista a los miembros cuyo nombre o tipo contengan el texto (por ejemplo `-Filter Writer`).
   - `-Expressions "_writer;;_options.Value"` para variables o miembros concretos (separadas por `;;`).
4. Interpreta:
   - `runtimeType` vacío y `declaredType` de clase o tipo simple: no hay interfaz de por medio.
   - `isNull: true`: la dependencia no está inyectada o no se ha inicializado todavía.
   - Colecciones (`IEnumerable<IFoo>`, `List<IFoo>`): mira con `vs-eval.ps1 -Expression "<coleccion>" -Members` los elementos que muestra el depurador; cada uno trae su tipo real.
5. Contrasta con el registro en el código: si el tipo real no es el esperado, busca el `Add...` que gana (en DI de .NET, con varios registros de la misma interfaz, `GetService` devuelve el último registrado).

## Límites y cautelas

- Solo ves lo que hay en ese instante y en ese ámbito (scope). Una dependencia `Scoped` puede ser otra instancia en otra petición.
- No consultes el contenedor con `serviceProvider.GetService<...>()` ni con `GetServices`: resolver servicios ejecuta código de la aplicación y puede tener efectos secundarios (crear instancias, abrir conexiones). Si de verdad hace falta, pídelo expresamente al usuario antes.
- Los tipos de clases proxy (decoradores, interceptores, Castle) aparecerán como tipos generados: mira también sus campos internos para encontrar el objeto envuelto.

## Cómo presentar el resultado

Una lista corta: dependencia, interfaz declarada, clase real, y una línea con lo relevante (por ejemplo "esperabas ShopifyFeedWriter pero hay una versión de pruebas registrada en Program.cs"). No pegues el JSON completo.
