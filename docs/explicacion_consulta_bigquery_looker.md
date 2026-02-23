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

### Fórmulas recomendadas en Looker Studio (USD)

**% Participación Real Mes (USD)**
```text
SAFE_DIVIDE(SUM(Real_Mes_USD), SUM(Venta_Real_Mes_USD))
```

**% Participación Ppto Mes (USD)**
```text
SAFE_DIVIDE(SUM(Ppto_Mes_USD), SUM(Venta_Ppto_Mes_USD))
```

### Fórmulas recomendadas en Looker Studio (SOL)

**% Participación Real Mes (SOL)**
```text
SAFE_DIVIDE(SUM(Real_Mes_SOL), SUM(Venta_Real_Mes_SOL))
```

**% Participación Ppto Mes (SOL)**
```text
SAFE_DIVIDE(SUM(Ppto_Mes_SOL), SUM(Venta_Ppto_Mes_SOL))
```

### Resultado esperado

- En la fila `INGRESOS DE LA EXPLOTACION`, el % debe ser ~`100%`.
- En `COSTO VARIABLE`, `MARGEN BRUTO`, `EBITDA`, etc., el % refleja su participación del mismo mes contra ventas del mes.
- Si un rubro es negativo, el % será negativo (esto es correcto financieramente).

### Importante para evitar errores de agregación

No uses un cálculo sin agregación explícita como:
```text
Real_Mes_USD / Venta_Real_Mes_USD
```

En tablas con más detalle (por ejemplo incluyendo `cuenta_contable`), ese enfoque puede terminar en agregaciones inconsistentes. Siempre usa **ratio de sumas** con `SUM(...)`.

### Configuración sugerida de la tabla

- Dimensiones: `partida_general` (y opcionalmente `partida_analitica`, `cuenta_contable`).
- Métricas base: `SUM(Ppto_Mes_USD)`, `SUM(Real_Mes_USD)` y `VAR = SUM(Real_Mes_USD) - SUM(Ppto_Mes_USD)`.
- Métricas de %: usar las fórmulas de participación anteriores.
- Orden: `orden_partida` para mantener la secuencia P&L.

## Recomendaciones prácticas para Looker Studio Free

1. Usa **campos calculados a nivel de fuente** para variaciones y porcentajes, con `SAFE_DIVIDE` (o lógica de divisor ≠ 0).
2. Define controles por dimensión: división, unidad de negocio, región, agencia y mes.
3. Para scorecards de cierre, usa `*_Cierre_*` para mostrar un único valor del período.
4. Trabaja en una sola moneda por página (USD o SOL) para evitar mezcla conceptual.
5. Si el volumen crece, considera materializar esta consulta en una tabla o vista programada en BigQuery para acelerar tiempos.
