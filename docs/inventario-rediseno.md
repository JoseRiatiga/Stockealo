# Inventario del re-diseño (0.13.0)

> Revisión **archivo por archivo** de toda la interfaz de Stockealo, hecha el 11 nov 2026 antes de programar. El dueño la pidió así: en cambios anteriores varias pantallas quedaron con el **primer diseño** o con mezclas.
> El objetivo es que **ninguna pantalla, ventana, hoja, aviso o pieza** quede fuera del re-diseño. Cada archivo tiene un bloque asignado (`docs/plan-rediseno.md`, sección 9).
> Cómo se midió: un script lee cada archivo `.dart` que dibuja algo y cuenta las señales del diseño viejo. Los casos dudosos se revisaron a mano.

## 1. Resumen

| | Cantidad |
|---|---|
| Archivos que dibujan interfaz o abren ventanas | **135** |
| Con el **primer diseño** (sin fichas de color) | **15** |
| **Mezcla** (V1 con partes viejas: claro/oscuro a mano, sombras, colores fijos) | **17** |
| Marcados V1 pero con **restos escondidos** | **20** |
| V1 limpios | 78 |
| Sin uso en ninguna parte (se **borran**) | **2** |

Señales del diseño viejo en toda la app:

| Señal | Veces | Cómo queda en el diseño nuevo |
|---|---|---|
| Colores escritos a mano (`Color(0x…)`, `Colors.x`) | 553 | Solo fichas del sistema. Se permiten únicamente en «colores de datos» (banderas, paleta del negocio, dibujo de Stocky) |
| Claro u oscuro decidido a mano (`isDark`, `Brightness.dark`) | 332 | Ninguno: las fichas ya cambian solas con el tema |
| Tamaños de letra sueltos (`fontSize: 13`…) | 859, con **25 tamaños distintos** (de 7 a 28, incluidos 12,5 · 13,5 · 14,5) | Una escala fija: 12 · 13 · 14 · 15 · 16 · 20 · 26 · 32, y 40 para cifras grandes |
| Estilos de texto del sistema (`AppText`) | solo 56 usos | Todos los textos usan la escala |
| Esquinas sueltas (`BorderRadius.circular(14)`) | 174 | Fichas: 10 · 12 · 16 · 22 y redondo |
| Espacios sueltos (`EdgeInsets` con números) | 329 | Fichas `AppSpace` (ya hay 1.529 usos) |
| Sombras | 11 | Ninguna: borde de 1 px |
| Degradados | 3 | Solo en las barras de color, que son datos |
| Ventanas: `AlertDialog` directo | 48 en 34 archivos | **Una sola ventana** del sistema |
| Ventanas con el `ModernDialog` viejo | 4 archivos | Se reemplaza y se borra `modern_dialog.dart` |
| Hojas que suben | 40 archivos; 21 dibujan su propia asa | **Una sola hoja** del sistema, con su asa |
| Avisos viejos (`SnackBar`) fuera de `AppToast` | 9 archivos | Solo `AppToast` |
| Íconos | 3 familias mezcladas: 470 redondeados, 257 de línea y 119 simples | **Una sola familia** de línea, como en el diseño aprobado |
| Emojis en textos | En Stocky y en mensajes de WhatsApp (se dejan, decidido antes); sueltos en Inicio y en los textos legales | Se quitan los sueltos; se dejan los de Stocky y WhatsApp |

## 2. Problemas de texto encontrados

**Dos palabras para lo mismo:** «negocio» aparece 170 veces, «empresa» 24 y «comercio» 5. En el diseño nuevo se usa **siempre «negocio»**.
- Por ejemplo, «Papelera de Empresas» pasa a «Papelera de negocios» y «Unirse a Empresa» pasa a «Unirse a un negocio».

**Textos en «Mayúsculas Al Estilo Inglés»** (en español solo va mayúscula la primera palabra). Encontrados:

| Hoy | Queda |
|---|---|
| Actualizar Ahora | Actualizar ahora |
| Foto de Perfil | Foto de perfil |
| Papelera de Empresas | Papelera de negocios |
| Vaciar Todo · Destruir Definitivamente | Vaciar todo · Borrar para siempre |
| Unirse a Empresa · Código de Invitación | Unirse a un negocio · Código de invitación |
| Abono Registrado · Registrar Abono a Fiado | Abono registrado · Registrar abono |
| Deuda Pendiente Actual · Pagar Todo | Deuda actual · Pagar todo |
| Centro de Notificaciones | Avisos |
| Escanear Código | Escanear código |
| Confirmar y Facturar (Cotizaciones) | Convertir en venta |
| Personalizar y Ordenar · Guardar Orden y Accesos | (ya corregido en la 0.12.1) |

La revisión final de textos se hace con un script en el bloque 9, para que no quede ninguno.

## 3. Lo que se borra

- `features/profile/presentation/screens/supabase_sync_screen.dart` (405 líneas, primer diseño). Ninguna pantalla la abre.
- `features/dashboard/presentation/widgets/radial_gauge_card.dart` (215 líneas, primer diseño). Nadie la usa.
- `core/widgets/modern_dialog.dart`, cuando sus 4 usos pasen a la ventana del sistema.
- Las 21 asas de hoja dibujadas a mano y los `SnackBar` sueltos.

## 4. Regla para dar un archivo por terminado

Un archivo queda **re-diseñado** solo si cumple todo esto:

1. Ningún color escrito a mano, salvo «colores de datos» marcados con un comentario.
2. Ningún `isDark` ni `Brightness.dark`: se ve bien en claro y oscuro sin código propio.
3. Letra de la escala, esquinas y espacios de las fichas.
4. Ventanas, hojas y avisos con las piezas del sistema.
5. Íconos de la familia elegida.
6. Textos en español con mayúscula solo al inicio, y siempre «negocio».
7. Prueba a 360 y 1200 px, en claro y en oscuro, sin desbordes.

**Para que no vuelva a pasar:** la prueba que hoy limita los colores fijos (`Color(0x` ≤ 512) se amplía con candados que **solo pueden bajar** y llegan a cero al terminar:
- colores a mano;
- `isDark`;
- `fontSize` suelto;
- `SnackBar`;
- `AlertDialog` directo;
- `ModernDialog`.

Si alguien agrega uno, la prueba falla.

## 5. Respuestas del dueño (11 nov)

1. **El panel admin SÍ entra** al re-diseño de la 0.13.0. Va como **bloque 8b**, después de la tienda (los 19 archivos de la tabla «Panel admin»).
2. **La portada stockealo.online (`web_site/`) SÍ entra** en la 0.13.0, en el bloque 8, junto a la tienda.
3. **Íconos: una sola familia de línea fina** para toda la app, como en el diseño aprobado. Se cambia en el bloque 1 (base) y se aplica en cada bloque. El candado de prueba revisa que no queden íconos de otra familia.

## 6. Archivo por archivo

### Bloque 0 · Borrar (2 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/dashboard/presentation/widgets/radial_gauge_card.dart` | VIEJO | 215 | No se usa en ninguna parte: se borra |
| `features/profile/presentation/screens/supabase_sync_screen.dart` | VIEJO | 405 | No se usa en ninguna parte: se borra |

### Bloque 1 · Base (20 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `core/design/country_flag.dart` | V1 (datos) | 140 | colores de datos (banderas), están bien |
| `core/widgets/formatted_changelog_view.dart` | VIEJO | 253 | 14 colores a mano; claro/oscuro a mano ×7; sombra ×1 |
| `core/widgets/modern_dialog.dart` | VIEJO | 231 | 21 colores a mano; claro/oscuro a mano ×15 |
| `core/widgets/stocky_empty_state.dart` | VIEJO | 83 | 6 colores a mano; claro/oscuro a mano ×5 |
| `core/widgets/update_dialog.dart` | VIEJO | 317 | 39 colores a mano; claro/oscuro a mano ×19 |
| `core/design/color_sliders.dart` | V1 (datos) | 133 | colores de datos (barras de color), están bien; sombra ×1; degradado ×1 |
| `core/design/color_swatch_dot.dart` | V1 (datos) | 77 | colores de datos (muestras de color), están bien; degradado ×1 |
| `core/design/app_card.dart` | V1 | 39 | limpio |
| `core/design/app_pagination.dart` | V1 | 85 | limpio |
| `core/design/glass_surface.dart` | V1 | 64 | 1 colores a mano |
| `core/design/phone_field.dart` | V1 | 141 | limpio |
| `core/design/primary_action_button.dart` | V1 | 71 | limpio |
| `core/design/quick_access_row.dart` | V1 | 87 | limpio |
| `core/design/segmented_gauge.dart` | V1 | 88 | 1 colores a mano; claro/oscuro a mano ×2 |
| `core/design/skeleton.dart` | V1 | 93 | limpio |
| `core/widgets/image_source_picker_modal.dart` | V1 | 252 | limpio |
| `core/widgets/maintenance_gate.dart` | V1 | 215 | 1 colores a mano |
| `core/widgets/theme_mode_button.dart` | V1 | 29 | claro/oscuro a mano ×2 |
| `core/design/content_width.dart` | sin color | 21 | limpio |
| `core/design/pro_crown.dart` | sin color | 51 | limpio |

### Bloque 2 · Navegación (8 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/home/presentation/widgets/notifications_modal.dart` | MEZCLA | 279 | 3 colores a mano; claro/oscuro a mano ×7 |
| `features/home/presentation/screens/main_navigation_screen.dart` | V1 | 468 | aviso viejo (SnackBar) |
| `features/home/presentation/widgets/app_header_bar.dart` | V1 | 142 | limpio |
| `features/home/presentation/widgets/app_sidebar_pro.dart` | V1 | 321 | 1 colores a mano; claro/oscuro a mano ×2 |
| `features/home/presentation/widgets/global_search_dialog.dart` | V1 | 341 | limpio |
| `features/home/presentation/widgets/where_things_moved_sheet.dart` | V1 | 75 | limpio |
| `features/onboarding/presentation/welcome_screen.dart` | V1 | 248 | limpio |
| `main.dart` | sin color | 172 | claro/oscuro a mano ×1 |

### Bloque 3 · Inicio (8 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/dashboard/presentation/widgets/spline_area_chart.dart` | MEZCLA | 420 | claro/oscuro a mano ×2; degradado ×1 |
| `features/dashboard/presentation/widgets/top_products_section.dart` | MEZCLA | 170 | 3 colores a mano; claro/oscuro a mano ×5; sombra ×1 |
| `features/dashboard/presentation/screens/dashboard_screen.dart` | V1 | 434 | limpio |
| `features/dashboard/presentation/widgets/cloud_sync_reminder.dart` | V1 | 155 | limpio |
| `features/dashboard/presentation/widgets/dashboard_desktop_charts.dart` | V1 | 86 | limpio |
| `features/dashboard/presentation/widgets/dashboard_metrics_grid.dart` | V1 | 248 | 1 colores a mano; claro/oscuro a mano ×2 |
| `features/dashboard/presentation/widgets/quick_actions_section.dart` | V1 | 350 | emoji ×1 |
| `features/dashboard/presentation/widgets/segmented_progress_card.dart` | V1 | 127 | limpio |

### Bloque 4 · Vender y Caja (4 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/sales/presentation/screens/sales_history_screen.dart` | MEZCLA | 677 | 7 colores a mano; claro/oscuro a mano ×4 |
| `features/sales/presentation/widgets/quick_sale_dialog.dart` | MEZCLA | 1375 | 8 colores a mano; claro/oscuro a mano ×9; 37 tamaños de letra sueltos |
| `features/cash/presentation/screens/cash_register_screen.dart` | V1 | 582 | 10 tamaños de letra sueltos |
| `features/cash/presentation/widgets/cash_status_card.dart` | V1 | 95 | limpio |

### Bloque 5 · Comprobante (1 archivo, y `digital_ticket_modal.dart`, que solo le pasa los datos)

Además de este archivo, el bloque cubre los comprobantes que hoy salen como texto por WhatsApp: cierre de caja (`cash_register_screen.dart`), abono (`record_payment_modal.dart`), liquidación (Servicios) y pedido de la tienda.

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/sales/presentation/widgets/sale_document.dart` | V1 | 393 | 2 colores a mano; 15 tamaños de letra sueltos |

### Bloque 6 · Códigos (2 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/products/presentation/screens/barcode_scanner_screen.dart` | VIEJO | 109 | 6 colores a mano |
| `features/products/presentation/widgets/barcode_modal.dart` | VIEJO | 161 | 14 colores a mano; claro/oscuro a mano ×9; sombra ×1 |

### Bloque 7 · Resto de pantallas (68 archivos)

Es el bloque más grande. Se hace por módulo, en este orden: Productos y Stock · Clientes y proveedores · Reportes · Ajustes (perfil, negocio, equipo, apariencia) · Servicios · Stocky · Entrar, crear negocio, Pro y textos legales.

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/dashboard/presentation/widgets/stocky_face_button.dart` | VIEJO | 166 | 14 colores a mano; claro/oscuro a mano ×6; sombra ×2 |
| `features/products/presentation/widgets/manage_categories_modal.dart` | VIEJO | 284 | 30 colores a mano; claro/oscuro a mano ×14 |
| `features/products/presentation/widgets/product_image_view.dart` | VIEJO | 128 | 9 colores a mano; claro/oscuro a mano ×7 |
| `features/products/presentation/widgets/quick_stock_dialog.dart` | VIEJO | 95 | 6 colores a mano |
| `features/profile/presentation/widgets/change_password_dialog.dart` | VIEJO | 114 | 10 colores a mano; claro/oscuro a mano ×5; aviso viejo (SnackBar) |
| `features/profile/presentation/widgets/up_to_date_dialog.dart` | VIEJO | 106 | 19 colores a mano; claro/oscuro a mano ×10 |
| `features/business/presentation/widgets/business_selector_modal.dart` | MEZCLA | 538 | 20 colores a mano; claro/oscuro a mano ×10; aviso viejo (SnackBar) |
| `features/business/presentation/widgets/business_trash.dart` | MEZCLA | 614 | 38 colores a mano; claro/oscuro a mano ×24; aviso viejo (SnackBar); 18 tamaños de letra sueltos |
| `features/business/presentation/widgets/join_business_dialog.dart` | MEZCLA | 180 | 3 colores a mano; claro/oscuro a mano ×2; aviso viejo (SnackBar) |
| `features/customers/presentation/screens/customers_screen.dart` | MEZCLA | 633 | 21 colores a mano; claro/oscuro a mano ×27; 17 tamaños de letra sueltos |
| `features/customers/presentation/widgets/record_payment_modal.dart` | MEZCLA | 462 | 18 colores a mano; claro/oscuro a mano ×25; 16 tamaños de letra sueltos; emoji ×10 |
| `features/dashboard/presentation/widgets/stocky_assistant_modal.dart` | MEZCLA | 881 | 2 colores a mano; claro/oscuro a mano ×4; sombra ×1; 13 tamaños de letra sueltos; emoji ×10 |
| `features/products/presentation/screens/product_form_screen.dart` | MEZCLA | 982 | 44 colores a mano; claro/oscuro a mano ×18; sombra ×1; aviso viejo (SnackBar); 11 tamaños de letra sueltos |
| `features/products/presentation/widgets/catalog_generator_modal.dart` | MEZCLA | 1240 | 9 colores a mano; 23 tamaños de letra sueltos |
| `features/products/presentation/widgets/photo_color_picker.dart` | V1 (datos) | 177 | colores de datos (color tomado de la foto), están bien; sombra ×1 |
| `features/profile/presentation/screens/profile_screen.dart` | MEZCLA | 1414 | 27 colores a mano; claro/oscuro a mano ×8; aviso viejo (SnackBar); 17 tamaños de letra sueltos |
| `features/auth/presentation/screens/login_screen.dart` | V1 | 601 | 1 colores a mano; claro/oscuro a mano ×2 |
| `features/auth/presentation/widgets/forgot_password_dialog.dart` | V1 | 878 | claro/oscuro a mano ×18; aviso viejo (SnackBar); 21 tamaños de letra sueltos |
| `features/auth/presentation/widgets/stockealo_splash_screen.dart` | V1 | 97 | limpio |
| `features/business/presentation/business_identity.dart` | V1 | 543 | colores de datos (paleta de colores del negocio), están bien |
| `features/business/presentation/screens/business_info_screen.dart` | V1 | 369 | 1 colores a mano |
| `features/business/presentation/screens/create_initial_business_screen.dart` | V1 | 606 | 4 colores a mano; 16 tamaños de letra sueltos |
| `features/business/presentation/screens/modules_screen.dart` | V1 | 192 | limpio |
| `features/business/presentation/widgets/create_business_sheet.dart` | V1 | 407 | 6 colores a mano |
| `features/customers/presentation/widgets/debt_reminder_schedule_sheet.dart` | V1 | 155 | limpio |
| `features/customers/presentation/widgets/new_customer_sheet.dart` | V1 | 133 | limpio |
| `features/dashboard/presentation/widgets/stocky_floating_button.dart` | V1 | 536 | emoji ×8 |
| `features/feedback/presentation/feedback_screen.dart` | V1 | 208 | limpio |
| `features/legal/presentation/screens/legal_document_screen.dart` | V1 | 404 | emoji ×5 |
| `features/pro/presentation/screens/pro_screen.dart` | V1 | 760 | 26 tamaños de letra sueltos |
| `features/pro/presentation/widgets/pro_upsell_sheet.dart` | V1 | 239 | limpio |
| `features/products/presentation/screens/product_detail_screen.dart` | V1 | 836 | 1 colores a mano; aviso viejo (SnackBar); 30 tamaños de letra sueltos |
| `features/products/presentation/screens/products_list_screen.dart` | V1 | 845 | limpio |
| `features/products/presentation/widgets/category_filter_bar.dart` | V1 | 50 | limpio |
| `features/products/presentation/widgets/category_name_dialog.dart` | V1 | 115 | limpio |
| `features/products/presentation/widgets/product_card.dart` | V1 | 243 | limpio |
| `features/products/presentation/widgets/product_sort_filter_sheet.dart` | V1 | 104 | limpio |
| `features/products/presentation/widgets/restock_order_modal.dart` | V1 | 775 | 19 tamaños de letra sueltos |
| `features/products/presentation/widgets/stock_status_badge.dart` | V1 | 68 | limpio |
| `features/products/presentation/widgets/story_catalog_modal.dart` | V1 | 504 | colores de datos (colores de la plantilla de historia), están bien; 12 tamaños de letra sueltos |
| `features/products/presentation/widgets/variant_editor.dart` | V1 | 1189 | 16 tamaños de letra sueltos |
| `features/profile/presentation/widgets/settings_cards.dart` | V1 | 400 | claro/oscuro a mano ×2 |
| `features/reports/presentation/screens/guided_import_screen.dart` | V1 | 336 | limpio |
| `features/reports/presentation/screens/profit_report_screen.dart` | V1 | 417 | 14 tamaños de letra sueltos |
| `features/reports/presentation/screens/reports_screen.dart` | V1 | 331 | limpio |
| `features/sales/presentation/widgets/quotations_list_modal.dart` | V1 | 409 | 3 colores a mano |
| `features/sales/presentation/widgets/sale_card.dart` | V1 | 172 | limpio |
| `features/sales/presentation/widgets/sales_summary_card.dart` | V1 | 85 | limpio |
| `features/services/presentation/screens/services_tab.dart` | V1 | 243 | limpio |
| `features/services/presentation/widgets/attendance_view.dart` | V1 | 148 | limpio |
| `features/services/presentation/widgets/board_view.dart` | V1 | 622 | 11 tamaños de letra sueltos |
| `features/services/presentation/widgets/catalog_view.dart` | V1 | 331 | limpio |
| `features/services/presentation/widgets/checkout_sheet.dart` | V1 | 182 | limpio |
| `features/services/presentation/widgets/commissions_view.dart` | V1 | 260 | limpio |
| `features/services/presentation/widgets/history_view.dart` | V1 | 193 | limpio |
| `features/services/presentation/widgets/messages_view.dart` | V1 | 180 | limpio |
| `features/services/presentation/widgets/receive_sheet.dart` | V1 | 236 | limpio |
| `features/services/presentation/widgets/staff_section.dart` | V1 | 227 | limpio |
| `features/suppliers/presentation/screens/purchase_detail_screen.dart` | V1 | 442 | 10 tamaños de letra sueltos |
| `features/suppliers/presentation/screens/purchase_entry_screen.dart` | V1 | 1058 | 17 tamaños de letra sueltos |
| `features/suppliers/presentation/screens/supplier_form_screen.dart` | V1 | 267 | limpio |
| `features/suppliers/presentation/screens/supplier_orders_screen.dart` | V1 | 195 | limpio |
| `features/suppliers/presentation/screens/suppliers_screen.dart` | V1 | 517 | limpio |
| `features/suppliers/presentation/widgets/supplier_picker.dart` | V1 | 197 | limpio |
| `features/suppliers/presentation/widgets/visit_today_banner.dart` | V1 | 82 | limpio |
| `features/team/presentation/screens/activity_screen.dart` | V1 | 288 | limpio |
| `features/team/presentation/screens/employees_screen.dart` | V1 | 843 | 29 tamaños de letra sueltos |
| `features/auth/presentation/widgets/stocky_mascot.dart` | V1 (datos) | 393 | colores de datos (dibujo de Stocky), están bien; emoji ×1 |

### Bloque 8 · Tienda (3 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `features/store/presentation/screens/online_store_screen.dart` | V1 | 369 | limpio |
| `store_web/store_page.dart` | V1 | 685 | 16 tamaños de letra sueltos |
| `main_store.dart` | sin color | 32 | limpio |

### Bloque 8b · Panel admin (19 archivos)

| Archivo | Estado hoy | Líneas | Lo que tiene del diseño viejo |
|---|---|---|---|
| `admin/admin_businesses_page.dart` | V1 | 162 | limpio |
| `admin/admin_codes_screen.dart` | V1 | 367 | limpio |
| `admin/admin_config_page.dart` | V1 | 289 | limpio |
| `admin/admin_feedback_page.dart` | V1 | 229 | limpio |
| `admin/admin_health_section.dart` | V1 | 227 | 10 tamaños de letra sueltos |
| `admin/admin_login_screen.dart` | V1 | 131 | limpio |
| `admin/admin_maintenance_page.dart` | V1 | 483 | limpio |
| `admin/admin_payments_page.dart` | V1 | 107 | limpio |
| `admin/admin_search_dialog.dart` | V1 | 172 | limpio |
| `admin/admin_shell.dart` | V1 | 218 | limpio |
| `admin/admin_stores_page.dart` | V1 | 109 | limpio |
| `admin/admin_subscriptions_page.dart` | V1 | 351 | limpio |
| `admin/admin_summary_page.dart` | V1 | 175 | limpio |
| `admin/admin_team_page.dart` | V1 | 239 | limpio |
| `admin/admin_usage_section.dart` | V1 | 227 | 12 tamaños de letra sueltos |
| `admin/admin_user_detail.dart` | V1 | 327 | limpio |
| `admin/admin_users_page.dart` | V1 | 125 | limpio |
| `admin/admin_widgets.dart` | V1 | 190 | limpio |
| `main_admin.dart` | V1 | 109 | limpio |

## 7. Avance

**11 nov · Bloque 0 (hecho):** se borraron `supabase_sync_screen.dart` y `radial_gauge_card.dart` (620 líneas del primer diseño), y después `modern_dialog.dart`.

**11 nov · Bloque 1, primera parte (hecha):**
- **Colores nuevos** en `app_tokens.dart`, con los mismos nombres de siempre: gris frío y limpio en claro, oscuro completo y estados nuevos. Se midió el contraste de todo (texto 4,5 o más, principal 7 o más). El color del negocio se oscurece solo si el texto blanco no se leería encima (`AppPalette.readable`).
- **Escala de letra** (`AppText`: caption 12 · small 13 · body 14 · bodyLarge 15 · title 16 · heading 20 · page 26 · display 32 · figure 40), letra de máquina del sistema, esquinas (8 · 10 · 12 · 16 · 22) y movimiento (`AppMotion`, respeta «reducir movimiento»).
- **Tema** (`app_theme.dart`) reescrito:
  - los textos de Material siguen la escala;
  - botones de 44 px;
  - ventanas y hojas con esquinas de 22;
  - menús sin sombra;
  - categorías elegidas en negro;
  - encabezado sólido con su línea;
  - interruptor, casilla y opción con el color del negocio.
- **Sin cristal ni desenfoque** (`useGlassEffect` siempre es no). El botón principal es sólido.
- **Íconos:** toda la app pasó a la familia de línea (850 íconos `_outlined`, 0 redondeados).
- **Piezas nuevas:** `StatusPill`, `DeltaPill`, `SectionLabel` y `MiniBars` (`status_pill.dart`); `StatCard` y `AttentionRow` (`stat_card.dart`); `AppDialog`, `AppDialog.confirm` y `AppSheet` (`app_dialog.dart`).
- **La ventana vieja ya no existe:** sus 6 usos pasaron a `AppDialog`, con los títulos corregidos.
- **Candados** en `test/core/design/design_locks_test.dart`. Puntos de partida: colores a mano 257 · Colors.x 63 · isDark 257 · fontSize 824 · SnackBar 58 · AlertDialog 48 · redondeados 0 · ventana vieja 0.
- Análisis sin errores y 392 pruebas OK (con Flutter 3.47.9).

**Sigue del bloque 1:** pasar al diseño nuevo los archivos base del inventario:
- `update_dialog`, `formatted_changelog_view` y `stocky_empty_state` (primer diseño);
- `segmented_gauge`, `theme_mode_button`, `maintenance_gate`, `image_source_picker_modal` y `quick_access_row`;
- el buscador con Ctrl K.

Después vienen el bloque 2 y los siguientes.

**11 nov · Bloque 1, segunda parte (hecha). El bloque 1 está terminado.**
- Pasaron al diseño nuevo los tres archivos base que tenían el primer diseño: `stocky_empty_state`, `formatted_changelog_view` (ya no recibe `isDark`) y `update_dialog` (ahora usa `AppDialog`; «Actualizar ahora», «Hay una versión nueva»).
- `segmented_gauge` ya no aclara el color a mano. `theme_mode_button` usa `context.isDarkTheme`, que sirve solo para lógica (qué ícono mostrar) y nunca para colores.
- `maintenance_gate`, `image_source_picker_modal` (ahora con la hoja del sistema y su asa, sin la asa dibujada a mano), `quick_access_row` y `app_pagination` quedaron con la escala de letra y las fichas.
- **`lib/core` quedó limpio:** solo quedan colores de datos (banderas, muestras y barras de color) y el tema.
- Candados bajados: colores a mano 205 · Colors.x 60 · isDark 222 · fontSize 791.
- **Revisado en el navegador:** la pantalla de entrada ya toma la base nueva en claro y en oscuro (gris frío, campos blancos con borde, íconos de línea y botón sólido).
- El buscador con Ctrl K pasa al bloque 2, porque va en el encabezado nuevo.

**11 nov · Bloque 2, navegación (hecho en código; falta probarlo con sesión iniciada):**
- **Mapa de lugares** (`lib/features/home/navigation/app_places.dart`): una sola lista para el menú, los títulos, el buscador, los accesos, Stocky y los avisos. Los números 0 a 5 conservan su significado (el 1 pasa de «Inventario» a Productos). Nuevos: 6 Vender · 7 Caja · 8 Stock · 9 Clientes y proveedores · 10 Tienda en línea. Visibilidad: Tienda y Reportes solo para dueño y administrador, Servicios solo con el plan.
- **Menú único** (`app_menu.dart`, reemplaza a `app_sidebar_pro.dart`, borrado):
  - agrupado en DÍA A DÍA · INVENTARIO · PERSONAS Y MÁS, con el negocio arriba y Ajustes y la persona abajo;
  - espacio para contadores;
  - fijo y plegable en el computador; con ☰ en el celular. **Se quitó la barra de pestañas de abajo y el «Más».**
- **Encabezado único** (`app_header_bar.dart`): título y contexto, pastilla de la caja (`CashPill`, se actualiza sola con `DataEvents.cashVersion`), buscador con Ctrl K, avisos, tema y «Nueva venta». En el celular va compacto, en dos filas.
- **Las pantallas ya no dibujan su barra propia:** Inicio, Productos y Ventas. Clientes, Proveedores, Caja y Tienda tienen `embedded`.
- **Cada cosa en su lugar nuevo, sin copias:**
  - Ventas = historial + Cotizaciones (sin Clientes, Caja ni «Nueva venta» propia);
  - Productos = catálogo (sin Tienda ni Proveedores) y su «por reponer» lleva a Stock;
  - Stock = la lista en modo Stock (por reponer, «Pedir al proveedor» y el aviso del proveedor que pasa hoy);
  - Clientes y proveedores = dos pestañas (el cajero solo ve Clientes);
  - Caja propia (o una explicación de cómo encenderla);
  - Vender: punto de partida provisional hasta el bloque 4.
- **Saltos actualizados:** buscador (`app_functions.dart`, con la función nueva «Stock por reponer»), accesos de Inicio (Caja, Clientes, Proveedores y Tienda llevan a su lugar en vez de abrir copias), Stocky («Ir a Vender», «Ir a Stock», «Ir a Clientes y proveedores») y la campana (venta → Ventas, stock → Stock).
- **Textos corregidos:** los que decían «Ventas › Caja», «Inventario › Tienda», etc.
- **«Dónde quedó cada cosa» v2:** con el mapa nuevo y la hoja del sistema. Sale una vez por versión del menú y solo a quien ya usaba la app.
- Pruebas del marco con imágenes (computador y celular, claro y oscuro, menú ☰ abierto, cajero sin Tienda ni Reportes). Análisis sin errores y 395 pruebas OK. Candados: isDark 220 · fontSize 775 · AlertDialog 47.

**11 nov · Bloque 2 probado con sesión:** el dueño entró en la copia local (Chrome) y funciona. Ajustes de paso:
- Pantalla de carga de la web (`web/index.html`) con el diseño nuevo: clara u oscura según el equipo, logo sin degradados, barra fina que respeta «reducir movimiento».
- `.gitattributes`: `web/sqflite_sw.js` siempre con saltos de línea LF y `*.wasm` binario.
- El ingreso ya no muestra errores crudos: `AuthRepository.translateAuthError` traduce también los de la base del dispositivo.
- La copia local se prueba en Chrome: el panel de navegador de la app no deja cargar la base desde 127.0.0.1.

**11 nov · Bloque 3, Inicio (hecho en código; falta que el dueño lo revise con sus datos):**
- **Datos nuevos** (`dashboard/data/home_data.dart`, `HomeRepository`):
  - cifras de hoy (una venta = una factura) frente al mismo día de la semana pasada, y ventas por hora;
  - ganancia del mes frente a los mismos días del mes anterior;
  - fiados con vencidos (más de 30 días sin abonar);
  - por reponer y agotados;
  - gráfico de 14 días, mes o año;
  - lo más vendido en 7 días.
  - `DashboardRepository.getDashboardSummary` se queda: lo usan Stocky y las alertas del celular.
- **«Necesita atención»**, de lo más urgente a lo menos: agotados (los que más se venden primero) → caja abierta de un día anterior → fiados vencidos → los que están en el mínimo. Muestra 5 y enlaza al resto.
- **Panel «Resolver»** (`attention_panel.dart`) con «Por qué pasó», «Si nadie hace nada» y la solución sugerida:
  - agotado → «Pedir al proveedor», que abre el pedido por WhatsApp con su proveedor;
  - fiado → «Enviar cobro por WhatsApp», con el mensaje a la vista;
  - caja → «Ir a la caja».
- **Pieza nueva del sistema:** `AppSidePanel`. En el computador entra por la derecha; en el celular es la hoja del sistema.
- **Pantalla** (`dashboard_screen.dart`, reescrita):
  - saludo con la fecha y el resumen;
  - tarjetas «Ventas de hoy» (en el color del negocio, con mini barras por hora), «Ganancia» (solo dueño y administrador), «Fiados» y, según el negocio, «Efectivo en caja» o «Por reponer»;
  - gráfico con detalle al pasar o tocar;
  - lo más vendido, actividad del equipo (dueño y administrador) y servicios de hoy (con el plan).
  - En el celular: tarjetas compactas de a dos, y «Necesita atención» antes del gráfico.
- **Se conservan**, al estilo nuevo: los accesos rápidos (pedidos en la 0.12.1; su hoja ahora es `AppSheet`) y el recordatorio de la nube.
- **Borrado:** `dashboard_metrics_grid`, `dashboard_desktop_charts`, `spline_area_chart`, `segmented_progress_card`, `top_products_section`, `cash_status_card` y `core/design/segmented_gauge`, con sus pruebas. La regla «caja cerrada al cobrar en efectivo» pasó a `cash_register_repository.dart`.
- **Pendiente para otros bloques:**
  - «Pedido de la tienda por confirmar» llega con el bloque 8 (hoy los pedidos no se guardan en la app).
  - Los interruptores «Recordarme si no llega» y «Ocultarlo en Vender» del diseño no existen todavía.
  - «Aplicar» el mínimo sugerido queda como consejo.
- **Pruebas** (`test/features/dashboard/home_test.dart`): cuentas, orden de urgencia y gráfico, más la pantalla completa con imágenes en computador y celular, claro y oscuro. Análisis limpio y 394 pruebas OK.
- **Candados:** la regla de `Colors.x` contaba `ToneColors.of` por error; se corrigió y queda en 42. isDark 211 · fontSize 740.

**11 nov · Bloque 4, Vender y Caja (hecho en código; falta que el dueño lo pruebe y aplicar la migración de la nube):**
- **Vender = punto de venta** (`sales/presentation/screens/sell_screen.dart`), igual al diseño aprobado:
  - computador: buscador grande (también lector USB: código + Enter entra solo), categorías, cuadrícula con precio y «62 u.», «Quedan 5» o «Sin stock», y la cuenta fija a la derecha;
  - celular: lista grande con cámara para escanear y la barra «3 productos · \$ · Cobrar» que sube la cuenta.
- **En la cuenta:**
  - cliente (obligatorio para fiar), descuento a toda la venta (con «máximo sin perder»), total en grande;
  - formas de pago: Efectivo (con «Recibí» y el vuelto), Nequi, Transferencia, Tarjeta, Fiado y **Mixto**;
  - Cobrar con F9, Esc vacía y F2 va al buscador;
  - «Para después» (ventas en espera) y «Cotizar».
- **Después de cobrar,** la cuenta queda vacía y lista; el aviso «✓ Venta registrada» trae el vuelto y «Enviar recibo».
- **Lo que protege la venta:** venta bajo el costo bloqueada para el cajero y con permiso del dueño.
- **La cuenta** (`sales/data/sell_cart.dart`) vive mientras la app está abierta y se vacía al cambiar de negocio.
- **Una sola forma de vender:**
  - se borró `quick_sale_dialog.dart` (1.375 líneas) y el «Vender» provisional;
  - «Nueva venta» del encabezado, los accesos rápidos, el buscador y el detalle de un producto llevan a Vender. Los últimos dos agregan el producto a la cuenta, preguntando talla o color con `VariantPicker`, sacado de la venta rápida.
- `AppPlace.go(lugar)`: una sola forma de pedir «llévame a…» desde una pantalla que está encima del marco.
- **Formas de pago en un solo lugar** (`sales/models/payment_method.dart`): reemplaza 6 listas repetidas (Ventas, comprobante, reportes, exportación, estado de cuenta, actividad y caja).
- **Caja obligatoria:**
  - `CashRegisterRepository.requireOpen` la exigen la venta, el cobro de servicios y convertir una cotización;
  - `CashGate` muestra «Abre la caja para vender» con la base, atajos (\$ 50.000, \$ 100.000, «Igual que ayer») y el aviso si no coincide con lo contado al cerrar;
  - `OpenCashForm` es la única forma de abrir la caja (también en la pantalla Caja).
- **Pantalla Caja** reescrita:
  - «Debería haber en la caja» en grande, con el detalle, Entrada, Salida y Cerrar caja;
  - lo cobrado por forma de pago con barras y los cierres anteriores con «Justa / Faltan / Sobran»;
  - el cierre muestra el resultado en grande mientras se cuenta.
  - La caja cuenta solo la parte en efectivo de un pago mixto.
- **Anular sin borrar:**
  - `SalesRepository.voidSale` anula la venta completa (todas sus líneas), devuelve el stock, baja el fiado y guarda motivo y quién;
  - Ventas la muestra tachada con «Anulada», pide el motivo y tiene el filtro «Anuladas».
  - Base local versión 13: columnas `voided_at`, `void_reason`, `voided_by` y `payment_split`, y la vista `sales_ok`, de la que leen todos los totales (Inicio, reportes, Stocky, caja, exportación y estado de cuenta).
- **Nube:** `supabase/migrations/20261129000000_sales_void_split.sql`, escrita y **sin aplicar** (requiere permiso). La subida ya manda los datos nuevos y, si la nube aún no tiene esas columnas, sube la venta sin ellos (no falla). La descarga conserva la marca de anulada de este equipo.
- **Cambio de comportamiento a revisar:** anular un servicio desde Ventas anula todo el cobro de esa orden (antes, solo esa línea).
- **Pendiente:** el descuento por línea («Desc.») no se hizo; queda el descuento a toda la venta. Las ventas en espera no sobreviven a cerrar la app.
- **Pruebas** (`test/features/sales/sell_test.dart`): caja obligatoria, pago mixto en la caja, anular sin borrar (fuera de Inicio, caja y resumen; stock de vuelta), la cuenta (stock, pérdida, en espera) e imágenes de Vender en computador y celular, claro y oscuro. 402 pruebas OK y análisis limpio.
- **Candados:** Color(0x 199 · Colors.x 41 · isDark 198 · fontSize 680 · AlertDialog 44.

**11 nov · Bloque 5, Comprobante (hecho en código; falta que el dueño lo vea en Chrome):**
- **Un solo tiquete de papel** (`sales/presentation/widgets/sale_document.dart`) para todos los comprobantes:
  - `TicketPaper`: blanco siempre, letra de máquina, líneas punteadas, nombre del negocio espaciado, número, fecha, cliente y quién atendió, lo vendido, el total en grande y el pago;
  - sello redondo y girado en su color: PAGADO, FIADO (con «Debe \$…»), ANULADA, COTIZACIÓN («Hasta…»), CAJA JUSTA / FALTAN / SOBRAN;
  - código de barras real (Code 128, con `barcode_widget`, que ya estaba) con el número, «¡Gracias por tu compra!» y el borde cortado.
  - Reemplaza `SaleDocumentCard` y `SaleDocumentSheet`.
- **`TicketViewer`:**
  - fondo oscuro, «Venta registrada · \$ 41.500 en efectivo» y la ranura de impresora de donde **sale el papel** (menos de 1 s; sin animación si se pidió menos movimiento);
  - «Enviar por WhatsApp como imagen» (con el texto adjunto; si la imagen falla, sale el texto), «Ver de nuevo», «Copiar texto» y «Cerrar» o «Nueva venta»;
  - en el computador va centrado.
- **Dónde sale:**
  - Vender: al cobrar en el celular sale solo; en el computador, «Ver recibo» en el aviso. Trae recibido, vuelto, el detalle del pago mixto y el saldo del fiado.
  - Ventas: el comprobante es de la venta completa (`SalesRepository.linesOf`), con ANULADA si se anuló.
  - Cotizaciones: compartir y convertir en venta.
  - Cierre de caja: reemplaza la pregunta y el texto (`cashTicket`).
- **Pendiente para sus bloques:**
  - abono a un fiado (bloque 7, Clientes);
  - liquidación de comisiones y orden de servicio (bloque 7, Servicios);
  - pedido de la tienda (bloque 8);
  - escanear el código del tiquete para abrir la venta (bloque 6).
  - NIT, dirección, teléfono y mensaje propio de despedida: el negocio todavía no tiene esos datos.
- **Pruebas:** `ticket_preview_test.dart` (5 tiquetes y el visor, con imágenes) y `sale_document_test.dart` actualizado (sellos, recibido, vuelto y saldo). 409 pruebas OK y análisis limpio. Candado fontSize 665.

**11 nov · Bloque 6, Leer códigos (hecho en código; falta probar la cámara y la foto en equipos reales):**
- **Un solo lector** (`core/codes/code_reader.dart`), como la referencia «Lince» del diseño aprobado:
  - pestañas **Cámara · Foto · A mano**; cada pestaña sale solo si el equipo puede usarla;
  - visor oscuro con las esquinas en el color del negocio y una línea de ayuda que cambia según el paso;
  - pastilla «Lector USB listo».
  - El lector USB escribe en el campo y da Enter.
- **Dos usos:**
  - `CodeReader.scan`: lee y sigue. Lo usan Vender, buscar en Productos, la entrada de mercancía y unirse a un negocio con su QR.
  - `CodeReader.pick`: el código de un producto, revisado: cada número en su cajita con su peso, la cuenta en palabras («la suma da 52, faltan 8…»), formato, «Leído con», «Usar 8» si no cuadra y el aviso si otro producto ya lo tiene. Lo usan crear o editar un producto y el código de una talla o un color.
- **Revisión del último número** (`core/codes/barcode_check.dart`): EAN-13, EAN-8 y UPC-A; los códigos propios (STK-…) y QR se aceptan tal cual.
- **Leer desde una foto** (`core/codes/photo_barcode*.dart`): en la web, con el lector que traen Chrome y Edge; en Android e iOS, con el mismo lector de la cámara. En Windows no hay cámara ni foto: queda el lector USB o escribirlo.
- **Al guardar un producto** se revisan el último número y que el código no esté repetido, aunque se haya escrito sin abrir el lector.
- **Se borró** `barcode_scanner_screen.dart`; sus 8 usos pasaron al lector nuevo.
- **Pendiente:**
  - arrastrar o pegar (Ctrl V) una foto en el visor: hoy se elige con «Toca para elegir una foto»;
  - escanear el número del tiquete para abrir la venta: queda para Ventas, en el bloque 7.
- **Pruebas** (`test/core/codes/code_reader_test.dart`): la cuenta con el ejemplo del diseño, EAN-8, UPC-A, códigos propios, y el lector con «Usar 8» que se corrige y se acepta, con imágenes en computador y celular. 415 pruebas OK y análisis limpio. Candados: Color(0x 195 · fontSize 663.

**11 nov · Bloque 7, el resto de pantallas (hecho en código; falta que el dueño las recorra en Chrome):**
- **Pasado al sistema de diseño en todas las pantallas de la app** (los 68 archivos del bloque, y lo que quedaba en los demás):
  - **Colores a mano:** 195 → 0. Los del primer diseño (esmeralda, pizarra, morados) pasaron a las fichas (`context.colors`), que cambian solas con el tema. El verde de WhatsApp quedó en la paleta como `AppPalette.whatsapp`.
  - **Colores de Material a mano:** 41 → 0.
  - **Claro/oscuro decidido a mano:** 198 → 1. Lo que queda es la lógica del tema, en `lib/core/theme` y `main.dart`.
  - **Tamaños de letra sueltos:** 663 → 121. Todos se ajustaron al más cercano de la escala de `AppText`. Los 121 que quedan son del panel admin (bloque 8b), la tienda (bloque 8) y los 2 PDF impresos, que tienen tamaños de papel.
  - **Avisos viejos (SnackBar):** 58 → 0. Ahora todos son `AppToast`, que suma `showWith(messenger)` para cuando se espera algo antes de avisar.
  - **Ventanas armadas a mano (AlertDialog):** 44 → 8 (las 8 son del panel admin). Las demás usan `AppDialog`, con ícono, tono, título y subtítulo.
- **Cómo se hizo** (scripts guardados en la carpeta temporal de la sesión, para repetirlos en el bloque 8b):
  - `estilo.py`: tamaños, avisos y ventanas;
  - `colores.py`: tabla de equivalencias del primer diseño a las fichas; `isDark ? oscuro : claro` → la ficha del claro;
  - `ventanas_titulo.py`: ventanas con ícono en el título;
  - `quitar_const.py`: quita el `const` que ya no aplica.
  - Lo que no reconocían se hizo a mano: los fondos blancos que cambiaban con el tema pasaron a `surface`, los `isDark` pasados entre funciones se quitaron y las transparencias según el tema quedaron fijas.
- **Comprobante de abono:** ahora es el tiquete, con sello ABONO y lo que queda debiendo, o CUENTA AL DÍA. El texto de WhatsApp de siempre va con la imagen.
- **Ventas:** botón «Escanear un tiquete», que abre esa venta por su número.
- **Textos:** viñetas en lugar de emojis en los textos legales; «Unirse a un negocio», «Abono registrado», «Ajustar stock», «¿Mover a la papelera?».
- **Cuidado:**
  - al ajustar la letra a la escala, algunos títulos crecieron (18 → 20) y uno se desbordó (recuperar contraseña, ya corregido); puede haber otro que no cubran las pruebas;
  - este bloque cambió colores, letra, avisos y ventanas, pero no rehízo la distribución de cada pantalla.
- **Para el bloque 9 (textos):** los textos legales todavía mencionan «Pro Global» (ya no existe) y quedan usos de «empresa» por «negocio».
- 415 pruebas OK y análisis limpio. Candados: Color(0x 0 · Colors.x 0 · isDark 1 · fontSize 121 · SnackBar 0 · AlertDialog 8.

**11 nov · Bloque 8, tienda en línea (hecho en código):**
- Dos plantillas en `store_web/store_page.dart`:
  - **Clásica:** la de siempre, mejorada, con categorías con miniatura y un botón «Filtros».
  - **Moda:** oscura, con menú arriba y el nombre espaciado, portada con título y 3 fotos, filtros a un lado (categoría con miniatura y cantidad, talla, color, precio y solo ofertas), tarjetas grandes con «OFERTA» y el precio de antes tachado.
- En las dos:
  - si el producto tiene tallas o colores, se elige al agregar;
  - «Hacer el pedido» muestra el tiquete **POR CONFIRMAR** con «Enviar pedido por WhatsApp», «Como imagen» y «Copiar texto».
- **El dueño, en Tienda en línea,** elige la plantilla (Clásica o Moda) y el título de la portada.
- **Producto:** nuevo campo «Precio de antes» para la oferta (`compare_price`), en la base local versión 13 y en la subida a la nube (si la nube no lo tiene, sube sin él).
- **Nube:** `supabase/migrations/20261129100000_store_templates.sql` agrega plantilla, título, precio de antes, y las tallas y colores en la tienda pública. Sin ella, la tienda sale Clásica y sin ofertas, y no falla.
- Candados: isDark 2 (el tema y la plantilla Moda, oscura a propósito) · fontSize 105.

## 8. Publicación parcial 0.13.0 (11 nov) y lo que falta

El dueño pidió publicar lo hecho para una presentación y anotar lo que falta. **Se publica la 0.13.0 con los bloques 0 a 8.**

**Lo que falta del re-diseño (para la 0.13.x):**
1. **Bloque 8b · Panel admin y portada (stockealo.online):**
   - ~~el panel admin (19 archivos) todavía tiene tamaños sueltos y 8 ventanas armadas a mano;~~ **hecho el 14 nov (rama feat/0.13.2):** 79 tamaños pasados a la escala de AppText y las 8 ventanas a AppDialog. Candados: fontSize 26 (solo los 2 PDF impresos) · AlertDialog 0. Falta mirarlo en Chrome;
   - ~~la portada (`web_site/`) no se ha tocado.~~ **hecho el 14 nov (feat/0.13.2):** `site.css` y `pago/` con la paleta nueva (gris claro, tarjetas con sombra suave, botones de esquina 12, pestañas como en la app); «Pro Global» cambiado por «Pro Servicios» en la portada, los términos de la web y los de la app. Mirado en claro y oscuro.
   - Repetir los scripts del bloque 7 (`estilo.py`, `colores.py`, `ventanas_titulo.py`, `quitar_const.py`).
2. **Bloque 7, segunda pasada:** HECHA en la 0.13.4: Clientes y proveedores, Productos y Stock con cifras en tarjetas, pestañas `FilterTabs` en Reportes y Servicios, sin botones flotantes.
   - las pantallas ya usan colores, letra, avisos y ventanas del sistema, pero no se rehízo la distribución de cada una (Productos, Stock, Clientes, Reportes, Ajustes, Servicios);
   - el dueño señaló (14 nov) que **Clientes y proveedores** se ve con diseño viejo: la tarjeta amarilla de «Fiados por cobrar», el buscador y los filtros «Todos / Con deuda / Al día». Empezar la segunda pasada por esa pantalla;
   - revisar en Chrome si algún título que creció (18 → 20) se corta.
3. **Bloque 9 · Cierre:**
   - ~~textos: «empresa» → «negocio»;~~ **hecho el 14 nov (feat/0.13.2):** papelera, eliminar negocio, perfil, equipo y roles. Quedan solo comentarios del código y la palabra clave «empresa» del tipo Oficina (sirve para buscar);
   - ~~los textos legales todavía mencionan «Pro Global»~~ **hecho:** términos de la web y de la app, portada, crear códigos del panel y mensaje de error. Se dejan las etiquetas que muestran suscripciones viejas guardadas como «global»;
   - revisión en la web y el APK.
4. **Pendientes pequeños anotados en cada bloque:**
   - descuento por línea en Vender;
   - las ventas en espera se pierden al cerrar la app;
   - arrastrar o pegar una foto en el lector de códigos;
   - «Pedido de la tienda por confirmar» en Inicio: los pedidos no se guardan en la app, llegan por WhatsApp;
   - interruptores «Recordarme si no llega» y «Ocultarlo en Vender» del panel Resolver;
   - NIT, dirección y despedida propia del negocio en el tiquete;
   - liquidación de comisiones y orden de servicio como tiquete.
5. **Probar en equipos reales:** la cámara y la foto del lector de códigos, y el tiquete compartido como imagen en el celular.
6. **Comportamiento nuevo a confirmar con el dueño:** anular un servicio desde Ventas anula todo el cobro de esa orden.

7. **Anotación del dueño (11 nov):** poder agregar personas que hacen los servicios desde el mismo módulo Servicios (Asistencia o tablero), no solo desde Ajustes › Equipo. Para la 0.14.0, reutilizando la misma hoja de «Agregar» (nada duplicado).
8. **Anotación del dueño (11 nov):** en el tablero de Servicios la tarjeta del vehículo se mueve completa; pidió que cada servicio sea individual (0.14.0). Y el tablero se ve cortado a la izquierda (sin margen) en la 0.13.0: corregir en la 0.13.x.

## 9. PRIORIDAD ALTA (11 nov, tras la presentación al cliente interesado)

Van antes que todo lo de la sección 8:
1. Agregar empleados desde el mismo módulo Servicios (una sola hoja, también en Ajustes › Equipo).
2. Horarios de los empleados: global del negocio o individual por empleado (ej. Juan de 8 a. m. a 12 p. m.).
3. Un empleado puede tener varios servicios a la vez si es el único disponible.
4. «Asistencia» pasa a «Empleados», con las comisiones de cada uno a la vista sin cerrar la caja (alguien se puede ir antes).
