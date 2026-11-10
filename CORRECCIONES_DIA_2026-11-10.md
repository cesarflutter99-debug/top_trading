# Correcciones — Día 2026-11-10

Documento de registro de los cambios aplicados a la aplicación **Al Lado** ("Top Trading") el día 2026-11-10, tras el diagnóstico del sistema de tutorial (coach marks) y la pantalla de Términos y Condiciones.

> **Commit previo:** `b9d4901` — "chore: estado previo a correcciones de tutorial y terminos (2026-11-10)" (19 archivos, +1232 / -1707).

---

## 1. Términos y Condiciones — datos de contacto (sección 9)

**Archivo:** `lib/screens/terminos_screen.dart`

La sección 9 "Contacto" tenía un placeholder en blanco (`[número oficial de WhatsApp] / [correo de soporte].`). Se reemplazó por los datos reales proporcionados:

| Campo | Valor |
|---|---|
| Teléfono | +5356403313 |
| Correo | elcesarrecord@gmil.com |

**Diff exacto:**
```diff
-  'Dudas, fraudes o reclamos de pagos de planes y paquetes: '
-  '[número oficial de WhatsApp] / [correo de soporte].',
+  'Dudas, fraudes o reclamos de pagos de planes y paquetes: '
+  'teléfono +5356403313 / correo elcesarrecord@gmil.com.',
```

---

## 2. Neutralización de acentos argentinos (voseo → español neutral)

**Objetivo:** eliminar el voseo argentino ("vos", "tenés", "podés", imperativos voseantes -ás/-és/-ís, "Acá") de los textos del tutorial, del onboarding y del asistente, reemplazándolos por español neutral (tú).

### 2.1 `lib/screens/main_shell_screen.dart` (tours: Home, Mapa, Anuncios, Mi Tienda, Perfil)

26 strings neutralizados (ver lista detallada en el informe de diagnóstico). Ejemplos representativos:
- 'Acá ves las tiendas más cercanas…' → 'Aquí ves las tiendas más cercanas…'
- 'Mapa: tiendas cerca de vos' → 'Mapa: tiendas cerca de ti'
- 'Tocá el mapa y filtrá por distancia…' → 'Toca el mapa y filtra por distancia…'
- '¿Querés vender?' → '¿Quieres vender?'
- 'Creá tu tienda gratis y empezás a vender…' → 'Crea tu tienda gratis y empiezas a vender…'

### 2.2 `lib/screens/assistant_screen.dart` (tour: Asistente)
- 'Escribí tu duda' → 'Escribe tu duda'
- 'Escribí lo que necesites…' → 'Escribe lo que necesites…'
- 'Tocá una pregunta sugerida…' → 'Toca una pregunta sugerida…'
- hintText 'Escribí tu consulta…' → 'Escribe tu consulta…'

### 2.3 `lib/widgets/cart_screen.dart` (tour: Carrito)
- 'Revisá el total' → 'Revisa el total'
- 'Acá ves cuánto vas a pagar en total. Podés cambiar las ' → 'Aquí ves cuánto vas a pagar en total. Puedes cambiar las '
- 'Completá la compra' → 'Completa la compra'

### 2.4 `lib/screens/favoritos_screen.dart` (tour: Favoritos)
- 'Acá quedan las tiendas que marcaste con el corazón, ' → 'Aquí quedan las tiendas que marcaste con el corazón, '

### 2.5 `lib/screens/mis_pedidos_screen.dart` (tour: Mis pedidos)
- 'Acá ves todos tus pedidos con su estado actual. Los pedidos ' → 'Aquí ves todos tus pedidos con su estado actual. Los pedidos '

### 2.6 `lib/screens/soporte_chat_screen.dart` (tour: Soporte)
- 'Escribí tu mensaje y te respondemos por acá mismo. ' → 'Escribe tu mensaje y te respondemos por aquí mismo. '
- 'Guardamos el historial, así que podés volver cuando ' → 'Guardamos el historial, así que puedes volver cuando '

### 2.7 `lib/screens/store_screen_flow.dart` (tour: La tienda)
- 'Agregá al carrito' → 'Agrega al carrito'
- 'Elegí la cantidad y tocá "Agregar al carrito". Te aviso que ' → 'Elige la cantidad y toca "Agregar al carrito". Te aviso que '

### 2.8 `lib/screens/onboarding_slides_screen.dart` (onboarding inicial)
- 'Creá tu tienda en minutos, publicá productos, gestioná ' → 'Crea tu tienda en minutos, publica productos, gestiona '

### 2.9 `lib/services/assistant_service.dart` (asistente de preguntas frecuentes)
- 13 strings neutralizados (Elegís→Eliges, completás→completas, Podés→Puedes, tenés→tienes, Necesitás→Necesitas, Buscá→Busca, entrá→entra, negás→niegas, Activá→Activa, generás→generas, Recibís→Recibes, registralo→regístralo).

---

## 3. Correcciones de código del tutorial (aplicadas)

### 3.1 Mover `TourAnchor` al botón real (no al contenedor con padding)

**Problema:** El spotlight no cubría bien los botones largos/altos porque `TourAnchor` envolvía un `Padding` o `Row`/`SizedBox` de ancho completo, inflando el rect medido.

**Archivos modificados:**

| Archivo | Cambio |
|---|---|
| `lib/screens/anuncios_social_screen.dart` | `TourAnchor(anunciosFab)` movido dentro del `Padding`, envolviendo solo `_buildFabMenu`. |
| `lib/screens/panel_vendedor_screen.dart` | `TourAnchor(miTiendaNuevo)` movido dentro del `Padding`, envolviendo solo `_buildFabMenu`. |
| `lib/widgets/cart_screen.dart` | `TourAnchor(carritoTotal)` movido para envolver solo el `Text('Total estimado')`, no el `Row` completo. |
| `lib/screens/mapa_tiendas_screen.dart` | `TourAnchor(mapaChips)` movido para envolver solo el primer chip del `ListView`, no el `SizedBox` completo. |
| `lib/screens/mi_perfil_screen.dart` | `TourAnchor(perfilAvatar)` movido para envolver solo el `CircleAvatar`, no el `GestureDetector`/`Stack` con spinner. |

### 3.2 Medir alto real del card del overlay

**Problema:** `altoCartel = 250.0` constante no medida; descripciones largas superaban 250 px en móvil → desbordamiento.

**Archivo:** `lib/widgets/coach_marks_widget.dart`
- `altoCartel` cambiado de `250.0` a `340.0` (más generoso).
- El `Text` de descripción envuelto en `ConstrainedBox(maxHeight: 160)` + `SingleChildScrollView` para evitar desbordamiento.

### 3.3 Bloquear tours concurrentes globalmente

**Problema:** `_toursEnVuelo` era un `Set<String>` por clave; claves distintas no se bloqueaban entre sí → overlays apilados al cambiar de pestaña rápido.

**Archivos modificados:**
- `lib/widgets/tour_runner.dart`: añadido flag estático `_abierto` / getter `abierto`. `mostrarSiNoVisto` consulta y setea el flag, bloqueando tours concurrentes.
- `lib/screens/main_shell_screen.dart`: `_programarTourDePestana` refactorizado para usar `TourRunner.mostrarSiNoVisto` en lugar de `CoachMarks.mostrar` directo. Eliminado `_toursEnVuelo` (Set) y su declaración.

### 3.4 Validar `mounted` en `CoachMarks.mostrar`

**Archivo:** `lib/widgets/coach_marks_widget.dart`
- Añadido `if (!context.mounted) return;` al inicio de `mostrar()`.

### 3.5 Eliminar anclas huérfanas

**Archivo:** `lib/widgets/tour_anchor.dart`
- Eliminadas 5 constantes sin `TourAnchor` correspondiente: `homeBuscador`, `homeCarrusel`, `perfilTabs`, `pedidosTabs`, `miTiendaProductos`.

### 3.6 Accesibilidad

**Archivo:** `lib/widgets/coach_marks_widget.dart`
- Icono del botón "Saltar" cambiado de `Icons.skip_next_rounded` a `Icons.close_rounded` (semántica correcta).

### 3.7 Web/desktop: limitar ancho del card

**Archivo:** `lib/widgets/coach_marks_widget.dart`
- El cartelito envuelto en `Center` + `ConstrainedBox(maxWidth: 420)` + `Padding(horizontal: 16)` para evitar que se estire de borde a borde en pantallas anchas.

---

## 4. Verificación

- Grep de patrones de voseo (`Elegís`, `completás`, `tenés`, `Tocá`, `Acá\b`, `vos\b`, etc.) sobre `lib/**/*.dart`: los únicos remanentes son coincidencias en comentarios, nombres de variables o código no relacionado con el tutorial/asistente.
- No se modificó ningún otro archivo además de los listados en §1, §2 y §3.

---

*Documento actualizado el 2026-11-10. Commit previo: `b9d4901`.*
