# Sistema de diseño de Stockealo (V1)

Base híbrida: **contenido sólido y limpio, cristal solo en lo que flota**.

## Principios

1. **Fondo cálido tipo papel** y tarjetas blancas con borde fino. Sin sombras ni degradados.
2. **Cristal solo en barras flotantes** (encabezado y pestañas). El cristal **verde** (el acento) solo en el botón principal y en la pestaña o sección activa.
3. **Un solo botón de color por pantalla**: la acción principal (`PrimaryActionButton`).
4. **Nada de íconos sin texto** para acciones importantes. El encabezado lleva el título y el selector de negocio, nada más.
5. **Textos en minúscula normal** ("Nueva venta", no "Nueva Venta") y sin emojis en la interfaz.
6. **Accesible**: contraste AA comprobado por pruebas, letra grande del sistema sin cortes, sin animaciones si el sistema pide reducirlas.

## Colores

Nunca escribas `Color(0x...)` en una pantalla. Usa `context.colors`:

| Token | Uso |
|---|---|
| `paper` | Fondo de las pantallas |
| `surface` | Tarjetas, diálogos, hojas inferiores |
| `surfaceMuted` | Rellenos suaves, esqueletos de carga |
| `line` / `lineStrong` | Bordes y divisores |
| `ink` / `inkMuted` / `inkFaint` | Texto principal, secundario y de ayuda |
| `accent` / `onAccent` | Botón principal, pestaña activa, enlaces. Verde de Stockealo o el color del negocio |
| `success` · `warning` · `danger` · `info` | Estados (ganancia, fiado, pérdida, información) |
| `successSoft` · `warningSoft` · `dangerSoft` · `infoSoft` | Fondos suaves de esos estados |
| `glass` | Fondo de las barras de cristal |
| `toast` / `onToast` | Avisos |

Los valores están en `lib/core/theme/app_tokens.dart` (`AppPalette`) para modo claro y oscuro.
Una prueba (`test/core/theme/app_tokens_test.dart`) impide que crezca la cantidad de colores escritos a mano fuera del tema: al rediseñar una pantalla, baja el número `baseline`.

### Color del negocio

Si el usuario activa "Usar el color del negocio en la app", `accent` pasa a ser el color del negocio (solo de `AppPalette.businessColors`, todos con texto blanco legible). Cambia el botón principal, la pestaña activa y los detalles; fondos y textos no. Es gratis para todos.

## Espacios, radios y texto

- Espacios: `AppSpace.xs/sm/md/lg/xl/xxl` = 4/8/12/16/24/32.
- Radios: `AppRadius.control` 12 (campos y botones), `card` 16, `sheet` 24 (diálogos, hojas, botón principal), `pill`.
- Letra: Inter (`AppText.fontFamily`). Montos y cantidades con `AppText.amount(context)`, que usa números de ancho fijo para que las cifras queden alineadas.

## Componentes (`lib/core/design/`)

| Componente | Para qué |
|---|---|
| `AppCard` | Tarjeta sólida con borde fino; acepta `onTap` |
| `GlassSurface` | Cristal para lo que flota; con `tint` se tiñe del acento. Se vuelve sólido si el usuario activa "Reducir transparencias" o el sistema pide alto contraste o reducir animaciones |
| `PrimaryActionButton` | La acción principal de la pantalla ("+ Nueva venta") |
| `AppPagination` | Paginación de todas las listas: `compact: true` arriba y completa abajo, con la misma página. Al cambiar desde abajo, la pantalla vuelve arriba |
| `SkeletonBox` / `SkeletonListTile` | Formas grises mientras carga, en vez de un círculo girando |
| `AppToast` (`lib/core/widgets/`) | Avisos: barra oscura y discreta con ícono según el tipo. No uses `SnackBar` directamente |

## Preferencias (`ThemeController`)

- Modo claro, oscuro o del sistema.
- `useBusinessColor`: acento con el color del negocio activo.
- `reduceTransparency`: barras sólidas en vez de cristal.
