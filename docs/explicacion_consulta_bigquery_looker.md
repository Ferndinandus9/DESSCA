# Explicación de consulta BigQuery para P&L (Real vs Presupuesto)

## ¿Qué hace la consulta?

Esta consulta construye una tabla financiera lista para visualización en Looker Studio, combinando información **Real (SOFIA)** y **Presupuesto (V1Op)** para el año 2025.

### 1) Normaliza y agrega bases de datos
- `base_sofia`: limpia dimensiones (partidas, cuenta, agencia), estandariza división (`AYL -> NNL`) y región (Callao/Sur/Norte en mayúsculas), convierte año/mes a entero y suma montos mensuales en USD/SOL.
- `base_ppto`: hace la misma estandarización para presupuesto, convierte el mes de texto a número y agrega montos mensuales USD/SOL.

### 2) Construye una cascada financiera (P&L) en ambos mundos
Sobre Real y sobre Presupuesto crea niveles calculados vía `UNION ALL` + `SUM`:
- Margen de Contribución
- Margen Bruto
- M1
- EBITDA
- M2
- Resultados Antes de Impuestos

Esto permite tener en un solo dataset tanto líneas contables base como líneas gerenciales derivadas del estado de resultados.

### 3) Calcula presupuesto anual
`ppto_anual` suma los 12 meses por combinación de dimensiones para facilitar métricas de avance anual.

### 4) Densifica el calendario hasta mes de corte
- `mes_corte`: obtiene el último mes con datos reales por año.
- `keys`: arma combinaciones únicas de dimensiones presentes en real o presupuesto.
- `densificada`: genera todos los meses desde 1 hasta `mes_corte` por cada combinación de `keys`, rellenando faltantes con 0.

Resultado: series mensuales completas (sin huecos) para gráficos y acumulados confiables.

### 5) Calcula acumulados YTD
En `final` usa funciones ventana para `Real_YTD` y `Ppto_YTD` (USD y SOL) por cada combinación dimensional.

### 6) Crea denominadores de venta para porcentajes
`venta_denominadores` toma la línea `INGRESOS DE LA EXPLOTACION` y calcula ventas mes/YTD (real y ppto) por dimensión de negocio, para usar como denominador en ratios (% sobre ventas).

### 7) Entrega dataset final listo para BI
Incluye:
- orden P&L (`orden_partida`) para ordenar filas en reportes.
- montos mes y YTD.
- presupuesto anual.
- métricas de cierre en el mes de corte.
- denominadores de venta mes/YTD.

## ¿Qué te permite calcular en Looker Studio Free?

Con este dataset puedes construir indicadores sin necesidad de blended data compleja:

### A) Variaciones Real vs Presupuesto
- Variación mes: `Real_Mes - Ppto_Mes`
- Variación % mes: `(Real_Mes - Ppto_Mes) / Ppto_Mes`
- Variación YTD y variación % YTD

### B) Márgenes y ratios sobre ventas
Usando campos `Venta_*` como denominador:
- `% Margen Contribución Mes = Real_Mes / Venta_Real_Mes`
- `% EBITDA Mes = Real_Mes / Venta_Real_Mes`
- `% M2 YTD = Real_YTD / Venta_Real_YTD`
- y equivalentes de presupuesto.

### C) Cumplimiento/avance del presupuesto anual
- `% Avance Anual = Real_YTD / Ppto_Anual`

### D) Lectura de cierre del período
Con campos `*_Cierre_*` puedes mostrar KPIs solo en el último mes cargado, evitando duplicidad en scorecards.

### E) Tableros P&L ordenados
`orden_partida` permite ordenar el estado de resultados en secuencia financiera estándar.

## Corrección importante: por qué el `%VAR` puede salir mal en Looker Studio

Si creas el campo así:

```text
( Real_Mes_USD - Ppto_Mes_USD ) / Ppto_Mes_USD
```

Looker Studio puede agregarlo como **suma de porcentajes por fila detalle** (por ejemplo por `cuenta_contable`) en vez de calcular el porcentaje sobre los **totales agregados** de la fila visible (`partida_general`).

Eso produce resultados distorsionados (como `-278,39%`) aun cuando el valor correcto del mes 6 para la línea de ingresos es `-11,87%`.

### Fórmula correcta para `%VAR` mensual

Crea el campo calculado con agregación explícita:

```text
SAFE_DIVIDE(SUM(Real_Mes_USD) - SUM(Ppto_Mes_USD), SUM(Ppto_Mes_USD))
```

Con los valores del ejemplo:
- `Ppto_Mes_USD = 6.002.495`
- `Real_Mes_USD = 5.289.813`
- `VAR = -712.682`
- `%VAR = -712.682 / 6.002.495 = -11,87%`

### Fórmula correcta para `%VAR` YTD

```text
SAFE_DIVIDE(SUM(Real_YTD_USD) - SUM(Ppto_YTD_USD), SUM(Ppto_YTD_USD))
```

### Recomendación de configuración en la tabla

- Métricas base como **SUM**: `Real_Mes_USD`, `Ppto_Mes_USD`, `Real_YTD_USD`, `Ppto_YTD_USD`.
- `%VAR` como **campo calculado de ratio de sumas** (no suma de ratios).
- Si desglosas por más detalle (`cuenta_contable`), el cálculo seguirá correcto porque el ratio se hace sobre agregados.



## Cómo calcular % de participación contra INGRESOS DE LA EXPLOTACION (mes)

Objetivo: que cada fila (cuenta contable, partida analítica o partida general) se divida entre el **total mensual de ventas** de `INGRESOS DE LA EXPLOTACION`, respetando filtros de:
- `mes`
- `division`
- `unidad_de_negocio`
- `region`
- `agencia`

Tu consulta ya trae ese denominador listo en estos campos:
- `Venta_Real_Mes_USD`
- `Venta_Ppto_Mes_USD`
- `Venta_Real_Mes_SOL`
- `Venta_Ppto_Mes_SOL`

Estos campos se calculan por `division + unidad_de_negocio + region + agencia + anio + mes`, por lo que cuando filtras mes 6 (u otro), el denominador se ajusta al filtro activo.

**Clave:** en la tabla final ese denominador viene repetido en muchas filas (una por cada cuenta/partida). Por eso, si usas `SUM(Venta_Real_Mes_USD)`, inflas el denominador y el % queda artificialmente bajo (ejemplo típico: `2,40%` en vez de `100,00%` para ingresos).
Usa `MAX(...)` (o `MIN(...)`) para tomar una sola vez el denominador del contexto filtrado.

### Fórmulas recomendadas en Looker Studio (USD)

**% Participación Real Mes (USD)**
```text
SAFE_DIVIDE(SUM(Real_Mes_USD), MAX(Venta_Real_Mes_USD))
```

**% Participación Ppto Mes (USD)**
```text
SAFE_DIVIDE(SUM(Ppto_Mes_USD), MAX(Venta_Ppto_Mes_USD))
```

### Fórmulas recomendadas en Looker Studio (SOL)

**% Participación Real Mes (SOL)**
```text
SAFE_DIVIDE(SUM(Real_Mes_SOL), MAX(Venta_Real_Mes_SOL))
```

**% Participación Ppto Mes (SOL)**
```text
SAFE_DIVIDE(SUM(Ppto_Mes_SOL), MAX(Venta_Ppto_Mes_SOL))
```



### Ajuste clave en Looker Studio (evita el 3080% y similares)

Si la fórmula ya usa agregaciones (`SUM`, `MAX`, `SAFE_DIVIDE`), **no vuelvas a agregar ese campo como SUM en la tabla**.

- Campo calculado recomendado:
```text
SAFE_DIVIDE(SUM(Real_Mes_USD), MAX(Venta_Real_Mes_USD))
```
- En la métrica del gráfico, configura agregación de `% Participación` como **Auto** (o **Promedio**), **no SUM**.

Cuando se deja en SUM, Looker puede sumar varias veces el mismo porcentaje agregado y aparecen valores inflados como `3080,51%` en vez de `100,00%`.



### Corrección definitiva para tu caso (columna fija en 315,12%)

Con la configuración que compartiste, el problema principal no está en la fórmula sino en la propiedad del gráfico:

- **Cálculo acumulativo = Máximo continuo**

Ese ajuste transforma el resultado del campo y termina mostrando un valor casi constante/inflado (como `315,12%`) en varias filas.

#### Cómo dejarlo correcto en Looker Studio

Para la métrica `% Participación Real Mes (USD)` configura:

1. **Fórmula** (puedes mantener la tuya):
```text
CASE
  WHEN SUM(Venta_Real_Mes_USD) = 0 THEN 0
  ELSE SUM(Real_Mes_USD) / MAX(Venta_Real_Mes_USD)
END
```
2. **Agregación**: `Automática` (o `Promedio`), no `SUM`.
3. **Cálculo acumulativo**: **Ninguno** (este punto es crítico).
4. **Cálculo de comparación**: `Ninguna`.
5. Tipo de dato: `Porcentaje`.

#### Validación esperada

Al aplicar lo anterior:
- `INGRESOS DE LA EXPLOTACION` debe quedar en ~`100,00%`.
- Las demás filas deben coincidir con la distribución correcta (ej. `-69,38%`, `30,62%`, `-5,68%`, etc.).
- El valor no debe repetirse como constante para todas las filas.



### Diagnóstico real del error que aún ves (315,12% con configuración aparentemente correcta)

Si ya tienes:
- fórmula con `SUM(Real_Mes_USD) / MAX(Venta_Real_Mes_USD)`
- agregación `Automática`
- cálculo acumulativo `Ninguno`

y todavía sale mal, la causa suele ser esta:

**La tabla está agregando varias combinaciones internas (por ejemplo varias `agencia`) que no están como dimensión visible, y `MAX(Venta_Real_Mes_USD)` solo toma una de ellas.**

Entonces el numerador suma varias agencias, pero el denominador toma solo la mayor agencia:
- Numerador: `SUM(Real_Mes_USD)` de varias agencias.
- Denominador: `MAX(Venta_Real_Mes_USD)` de una sola agencia.
- Resultado: % inflado (como `315,12%`).

### Solución recomendada (robusta)

Construir el denominador en una **fuente separada** (o vista BigQuery separada) agregada al nivel de filtros de negocio:
- `anio, mes, division, unidad_de_negocio, region, agencia` (o el nivel que usarás en controles)
- y unirla por esas dimensiones al dataset principal.

En el gráfico, usa:
```text
SAFE_DIVIDE(SUM(Real_Mes_USD), SUM(Venta_Real_Mes_USD_Denom))
```

donde `Venta_Real_Mes_USD_Denom` viene de esa fuente separada (una sola fila por combinación de filtros), no repetida por `partida_general/partida_analitica/cuenta_contable`.

### Solución rápida (si no harás blend/vista separada)

Para que la métrica no se infle con `MAX(...)`, debes forzar que los filtros de negocio queden en **un solo valor** por dimensión clave (especialmente `agencia`, además de división/UN/región/mes).

Si hay multiselección en esas dimensiones y la tabla no las muestra, el `%` volverá a distorsionarse.

### Alternativas adicionales

1. **Tabla a nivel de agencia**: agrega `agencia` como dimensión visible. Ahí `MAX(Venta_Real_Mes_USD)` sí representa correctamente esa fila.
2. **Métrica precomputada en BigQuery** para cada grano de reporte (por ejemplo, una vista para tabla de `partida_general` y otra para `partida_analitica`).
3. **Páginas separadas por nivel de análisis** (P&L general vs detalle de cuenta), cada una con su denominador modelado al grano correcto.

### Resultado esperado

- En la fila `INGRESOS DE LA EXPLOTACION`, el % debe ser ~`100%` cuando el denominador está modelado al mismo grano de agregación del gráfico.
- En `COSTO VARIABLE`, `MARGEN BRUTO`, `EBITDA`, etc., el % refleja su participación del mismo mes contra ventas del mes.
- Si un rubro es negativo, el % será negativo (esto es correcto financieramente).

### Importante para evitar errores de agregación

No uses un cálculo sin agregación explícita como:
```text
Real_Mes_USD / Venta_Real_Mes_USD
```

En tablas con más detalle (por ejemplo incluyendo `cuenta_contable`), ese enfoque puede terminar en agregaciones inconsistentes. Usa **SUM(...)** en el numerador y **MAX(...)** (o `MIN(...)`) en el denominador de ventas preagregado.

### Configuración sugerida de la tabla

- Dimensiones: `partida_general` (y opcionalmente `partida_analitica`, `cuenta_contable`).
- Métricas base: `SUM(Ppto_Mes_USD)`, `SUM(Real_Mes_USD)` y `VAR = SUM(Real_Mes_USD) - SUM(Ppto_Mes_USD)`.
- Métricas de %: usar las fórmulas de participación anteriores y dejar su agregación como **Auto** (o **Promedio**), no **SUM**.
- Orden: `orden_partida` para mantener la secuencia P&L.

## Recomendaciones prácticas para Looker Studio Free

1. Usa **campos calculados a nivel de fuente** para variaciones y porcentajes, con `SAFE_DIVIDE` (o lógica de divisor ≠ 0).
2. Define controles por dimensión: división, unidad de negocio, región, agencia y mes.
3. Para campos de %, revisa siempre que **Cálculo acumulativo = Ninguno** y **Comparación = Ninguna**.
4. Trabaja en una sola moneda por página (USD o SOL) para evitar mezcla conceptual.
5. Si el volumen crece, considera materializar esta consulta en una tabla o vista programada en BigQuery para acelerar tiempos.

## Ajuste para evitar `NULL` en `% PPTO IOS` / `% REAL IOS`

Si en Looker construyes el campo con un `CASE` que solo devuelve valor para `INGRESOS DE LA EXPLOTACION`,
las demás partidas quedarán en `NULL` (tal como en tu captura).

Para evitarlo, la vista simplificada ahora expone campos ya calculados por fila:
- `Pct_Ppto_vs_IOS_Mes_USD`
- `Pct_Real_vs_IOS_Mes_USD`

Estos campos dividen cada partida entre el denominador de ventas del mismo contexto de filtros
(`anio, mes, division, unidad_de_negocio, region, agencia`) con fallback sin agencia.

## Ajuste de consistencia de % cuando agregas varias agencias

Se densificó la base mensual por `partida_general` para cada combinación de
`division, unidad_de_negocio, region, agencia, anio, mes`.
Con esto, aunque una partida no tenga movimiento en una agencia, se conserva la fila en 0,
y el denominador de ventas queda consistente al calcular:

```text
SAFE_DIVIDE(SUM(Ppto_Mes_USD), SUM(Venta_Ppto_Mes_USD_Denom))
```

Este era el origen de la diferencia entre montos correctos y porcentajes distorsionados.

## Optimización aplicada: vista solo USD

Para reducir carga en Looker Studio, el modelo principal quedó materializado en `tbl_pl_reporte_pg_simple_2026` y en **solo USD**.
Se retiraron del SQL los campos y cálculos en SOL (mensual, YTD, anual, denominadores y %),
con lo cual baja el número de columnas y operaciones ventana que el conector debe procesar.

Esto ayuda a disminuir errores de recursos, aunque si el volumen por filtros sigue alto,
la recomendación adicional es materializar la vista en tabla y consultar esa tabla en Looker.

## Nuevos campos para % acumulado (YTD) sobre ventas

La vista ahora incluye denominadores acumulados en USD para participación YTD:
- `Venta_Real_YTD_USD_Denom`
- `Venta_Ppto_YTD_USD_Denom`

Y también los porcentajes acumulados listos para usar:
- `Pct_Real_vs_IOS_YTD_USD`
- `Pct_Ppto_vs_IOS_YTD_USD`

Con esto puedes mostrar % acumulado sin tener que construir ventanas en Looker Studio.

## Materialización recomendada en tablas (no solo vista)

Se propone trabajar con tablas materializadas para mejorar estabilidad en Looker Studio:
- `tbl_pl_reporte_pg_simple_2026` (resumen por `partida_general`, con porcentajes y denominadores).
- `tbl_pl_reporte_detalle_2026` (detalle por `partida_analitica` + `cuenta_contable`, sin porcentajes).

**¿Por qué tabla?**
Porque Looker consulta resultados ya precomputados y evita recalcular toda la lógica (cascadas,
ventanas, densificación) en cada render. Esto reduce errores de recursos y tiempos de carga.

