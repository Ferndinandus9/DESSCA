-- ==========================================================
-- OPCIÓN RECOMENDADA: DENOMINADOR EN FUENTE SEPARADA
-- ==========================================================
-- Objetivo:
-- 1) Construir una vista base de detalle (sin denominador repetido por fila)
-- 2) Construir una vista separada con el denominador de ventas mensual
--    al grano de filtros de negocio: anio, mes, division, unidad_de_negocio, region, agencia
-- 3) Unir ambas para usar en Looker Studio:
--      SAFE_DIVIDE(SUM(Real_Mes_USD), SUM(Venta_Real_Mes_USD_Denom))
--
-- Nota:
-- Implementado para tu entorno: `data-warehouse-445921.pruebas_tpp`.

-- ==========================================================
-- VISTA 1: BASE DE REPORTE (NUMERADOR)
-- ==========================================================
CREATE OR REPLACE VIEW `data-warehouse-445921.pruebas_tpp.vw_pl_base_reporte` AS
WITH
base_sofia AS (
  SELECT
    IFNULL(NULLIF(TRIM(ParGeneral),  ''), '*') AS partida_general,
    IFNULL(NULLIF(TRIM(ParAnalitic), ''), '*') AS partida_analitica,
    IFNULL(NULLIF(TRIM(AcctName),    ''), '*') AS cuenta_contable,
    CASE WHEN Division = 'AYL' THEN 'NNL' ELSE Division END AS division,
    UNegocio                                                 AS unidad_de_negocio,
    CASE
      WHEN Region = 'Callao' THEN 'CALLAO'
      WHEN Region = 'Sur'    THEN 'SUR'
      WHEN Region = 'Norte'  THEN 'NORTE'
      ELSE Region
    END                                                      AS region,
    IFNULL(NULLIF(TRIM(Agencia), ''), '*')                  AS agencia,
    SAFE_CAST(Anio AS INT64)                                AS anio,
    SAFE_CAST(Mes  AS INT64)                                AS mes,
    SUM(DistribuidoD)                                       AS real_mes_usd,
    SUM(Distribuido)                                        AS real_mes_sol
  FROM `data-warehouse-445921.pruebas_tpp.sofia_autom_completo`
  WHERE Anio = 2025
  GROUP BY 1,2,3,4,5,6,7,8,9
),

base_ppto AS (
  SELECT
    IFNULL(NULLIF(TRIM(partida_general),                    ''), '*') AS partida_general,
    IFNULL(NULLIF(TRIM(partida_analitica),                  ''), '*') AS partida_analitica,
    IFNULL(NULLIF(TRIM(descripcion_cuenta_contable_tercero),''), '*') AS cuenta_contable,
    CASE WHEN division = 'AYL' THEN 'NNL' ELSE division END           AS division,
    un                                                                AS unidad_de_negocio,
    CASE
      WHEN region = 'Callao' THEN 'CALLAO'
      WHEN region = 'Sur'    THEN 'SUR'
      WHEN region = 'Norte'  THEN 'NORTE'
      ELSE region
    END                                                               AS region,
    IFNULL(NULLIF(TRIM(un_detalle), ''), '*')                         AS agencia,
    SAFE_CAST(anio AS INT64)                                          AS anio,
    CASE UPPER(mes)
      WHEN 'ENERO'      THEN 1  WHEN 'FEBRERO'    THEN 2
      WHEN 'MARZO'      THEN 3  WHEN 'ABRIL'      THEN 4
      WHEN 'MAYO'       THEN 5  WHEN 'JUNIO'      THEN 6
      WHEN 'JULIO'      THEN 7  WHEN 'AGOSTO'     THEN 8
      WHEN 'SETIEMBRE'  THEN 9  WHEN 'SEPTIEMBRE' THEN 9
      WHEN 'OCTUBRE'    THEN 10 WHEN 'NOVIEMBRE'  THEN 11
      WHEN 'DICIEMBRE'  THEN 12
    END                                                               AS mes,
    SUM(monto_dolares)                                                AS ppto_mes_usd,
    SUM(monto_soles)                                                  AS ppto_mes_sol
  FROM `data-warehouse-445921.pruebas_tpp.ppto_completo`
  WHERE anio = 2025
    AND version_ppto = 'V1Op'
  GROUP BY 1,2,3,4,5,6,7,8,9
),

-- CASCADA REAL
r_mc AS (
  SELECT 'MARGEN DE CONTRIBUCION' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(real_mes_usd) AS real_mes_usd, SUM(real_mes_sol) AS real_mes_sol
  FROM base_sofia
  WHERE partida_general IN ('INGRESOS DE LA EXPLOTACION','COSTO VARIABLE')
  GROUP BY 2,3,4,5,6,7,8,9
),
r_base1 AS (SELECT * FROM base_sofia UNION ALL SELECT * FROM r_mc),

r_mb AS (
  SELECT 'MARGEN BRUTO' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(real_mes_usd) AS real_mes_usd, SUM(real_mes_sol) AS real_mes_sol
  FROM r_base1
  WHERE partida_general IN ('MARGEN DE CONTRIBUCION','COSTO FIJO')
  GROUP BY 2,3,4,5,6,7,8,9
),
r_base2 AS (SELECT * FROM r_base1 UNION ALL SELECT * FROM r_mb),

r_m1 AS (
  SELECT 'M1' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(real_mes_usd) AS real_mes_usd, SUM(real_mes_sol) AS real_mes_sol
  FROM r_base2
  WHERE partida_general IN (
    'MARGEN BRUTO','GASTOS CON EL PERSONAL FIJO',
    'GASTOS CON EL PERSONAL VARIABLE','GASTOS CON EL PERSONAL OTROS')
  GROUP BY 2,3,4,5,6,7,8,9
),
r_base3 AS (SELECT * FROM r_base2 UNION ALL SELECT * FROM r_m1),

r_ebitda AS (
  SELECT 'EBITDA' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(real_mes_usd) AS real_mes_usd, SUM(real_mes_sol) AS real_mes_sol
  FROM r_base3
  WHERE partida_general IN ('M1','GASTOS INDIRECTOS')
  GROUP BY 2,3,4,5,6,7,8,9
),
r_base4 AS (SELECT * FROM r_base3 UNION ALL SELECT * FROM r_ebitda),

r_m2 AS (
  SELECT 'M2' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(real_mes_usd) AS real_mes_usd, SUM(real_mes_sol) AS real_mes_sol
  FROM r_base4
  WHERE partida_general IN ('EBITDA','GASTOS POR AMORT. Y DEPREC.')
  GROUP BY 2,3,4,5,6,7,8,9
),
r_base5 AS (SELECT * FROM r_base4 UNION ALL SELECT * FROM r_m2),

r_rai AS (
  SELECT 'RESULTADOS ANTES DE IMPUESTOS' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(real_mes_usd) AS real_mes_usd, SUM(real_mes_sol) AS real_mes_sol
  FROM r_base5
  WHERE partida_general IN (
    'INGRESOS DE LA EXPLOTACION','COSTO VARIABLE','COSTO FIJO',
    'GASTOS CON EL PERSONAL FIJO','GASTOS CON EL PERSONAL VARIABLE',
    'GASTOS CON EL PERSONAL OTROS','GASTOS INDIRECTOS',
    'GASTOS POR AMORT. Y DEPREC.','GASTOS/INGRESO NO OPERACIONALES')
  GROUP BY 2,3,4,5,6,7,8,9
),
real_consolidado AS (
  SELECT * FROM r_base5
  UNION ALL SELECT * FROM r_rai
),

-- CASCADA PPTO
p_mc AS (
  SELECT 'MARGEN DE CONTRIBUCION' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(ppto_mes_usd) AS ppto_mes_usd, SUM(ppto_mes_sol) AS ppto_mes_sol
  FROM base_ppto
  WHERE partida_general IN ('INGRESOS DE LA EXPLOTACION','COSTO VARIABLE')
  GROUP BY 2,3,4,5,6,7,8,9
),
p_base1 AS (SELECT * FROM base_ppto UNION ALL SELECT * FROM p_mc),

p_mb AS (
  SELECT 'MARGEN BRUTO' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(ppto_mes_usd) AS ppto_mes_usd, SUM(ppto_mes_sol) AS ppto_mes_sol
  FROM p_base1
  WHERE partida_general IN ('MARGEN DE CONTRIBUCION','COSTO FIJO')
  GROUP BY 2,3,4,5,6,7,8,9
),
p_base2 AS (SELECT * FROM p_base1 UNION ALL SELECT * FROM p_mb),

p_m1 AS (
  SELECT 'M1' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(ppto_mes_usd) AS ppto_mes_usd, SUM(ppto_mes_sol) AS ppto_mes_sol
  FROM p_base2
  WHERE partida_general IN (
    'MARGEN BRUTO','GASTOS CON EL PERSONAL FIJO',
    'GASTOS CON EL PERSONAL VARIABLE','GASTOS CON EL PERSONAL OTROS')
  GROUP BY 2,3,4,5,6,7,8,9
),
p_base3 AS (SELECT * FROM p_base2 UNION ALL SELECT * FROM p_m1),

p_ebitda AS (
  SELECT 'EBITDA' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(ppto_mes_usd) AS ppto_mes_usd, SUM(ppto_mes_sol) AS ppto_mes_sol
  FROM p_base3
  WHERE partida_general IN ('M1','GASTOS INDIRECTOS')
  GROUP BY 2,3,4,5,6,7,8,9
),
p_base4 AS (SELECT * FROM p_base3 UNION ALL SELECT * FROM p_ebitda),

p_m2 AS (
  SELECT 'M2' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(ppto_mes_usd) AS ppto_mes_usd, SUM(ppto_mes_sol) AS ppto_mes_sol
  FROM p_base4
  WHERE partida_general IN ('EBITDA','GASTOS POR AMORT. Y DEPREC.')
  GROUP BY 2,3,4,5,6,7,8,9
),
p_base5 AS (SELECT * FROM p_base4 UNION ALL SELECT * FROM p_m2),

p_rai AS (
  SELECT 'RESULTADOS ANTES DE IMPUESTOS' AS partida_general,
    partida_analitica, cuenta_contable, division, unidad_de_negocio, region, agencia, anio, mes,
    SUM(ppto_mes_usd) AS ppto_mes_usd, SUM(ppto_mes_sol) AS ppto_mes_sol
  FROM p_base5
  WHERE partida_general IN (
    'INGRESOS DE LA EXPLOTACION','COSTO VARIABLE','COSTO FIJO',
    'GASTOS CON EL PERSONAL FIJO','GASTOS CON EL PERSONAL VARIABLE',
    'GASTOS CON EL PERSONAL OTROS','GASTOS INDIRECTOS',
    'GASTOS POR AMORT. Y DEPREC.','GASTOS/INGRESO NO OPERACIONALES')
  GROUP BY 2,3,4,5,6,7,8,9
),
ppto_consolidado AS (
  SELECT * FROM p_base5
  UNION ALL SELECT * FROM p_rai
),

mes_corte AS (
  SELECT anio, MAX(mes) AS mes_corte
  FROM real_consolidado
  GROUP BY anio
),

keys AS (
  SELECT DISTINCT partida_general, partida_analitica, cuenta_contable,
    division, unidad_de_negocio, region, agencia, anio
  FROM real_consolidado
  UNION DISTINCT
  SELECT DISTINCT partida_general, partida_analitica, cuenta_contable,
    division, unidad_de_negocio, region, agencia, anio
  FROM ppto_consolidado
),

densificada AS (
  SELECT
    k.partida_general, k.partida_analitica, k.cuenta_contable,
    k.division, k.unidad_de_negocio, k.region, k.agencia, k.anio,
    m                         AS mes,
    DATE(k.anio, m, 1)        AS periodo_mes,
    IFNULL(r.real_mes_usd, 0) AS real_mes_usd,
    IFNULL(r.real_mes_sol, 0) AS real_mes_sol,
    IFNULL(p.ppto_mes_usd, 0) AS ppto_mes_usd,
    IFNULL(p.ppto_mes_sol, 0) AS ppto_mes_sol,
    mc.mes_corte
  FROM keys k
  JOIN mes_corte mc ON mc.anio = k.anio
  CROSS JOIN UNNEST(GENERATE_ARRAY(1, mc.mes_corte)) AS m
  LEFT JOIN real_consolidado r
    ON  r.partida_general   = k.partida_general
    AND r.partida_analitica = k.partida_analitica
    AND r.cuenta_contable   = k.cuenta_contable
    AND r.division          = k.division
    AND r.unidad_de_negocio = k.unidad_de_negocio
    AND r.region            = k.region
    AND r.agencia           = k.agencia
    AND r.anio              = k.anio
    AND r.mes               = m
  LEFT JOIN ppto_consolidado p
    ON  p.partida_general   = k.partida_general
    AND p.partida_analitica = k.partida_analitica
    AND p.cuenta_contable   = k.cuenta_contable
    AND p.division          = k.division
    AND p.unidad_de_negocio = k.unidad_de_negocio
    AND p.region            = k.region
    AND p.agencia           = k.agencia
    AND p.anio              = k.anio
    AND p.mes               = m
)
SELECT
  partida_general,
  partida_analitica,
  cuenta_contable,
  division,
  unidad_de_negocio,
  region,
  agencia,
  anio,
  mes,
  periodo_mes,
  mes_corte,
  real_mes_usd AS Real_Mes_USD,
  real_mes_sol AS Real_Mes_SOL,
  ppto_mes_usd AS Ppto_Mes_USD,
  ppto_mes_sol AS Ppto_Mes_SOL,
  SUM(real_mes_usd) OVER (
    PARTITION BY partida_general, partida_analitica, cuenta_contable,
      division, unidad_de_negocio, region, agencia, anio
    ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS Real_YTD_USD,
  SUM(real_mes_sol) OVER (
    PARTITION BY partida_general, partida_analitica, cuenta_contable,
      division, unidad_de_negocio, region, agencia, anio
    ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS Real_YTD_SOL,
  SUM(ppto_mes_usd) OVER (
    PARTITION BY partida_general, partida_analitica, cuenta_contable,
      division, unidad_de_negocio, region, agencia, anio
    ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS Ppto_YTD_USD,
  SUM(ppto_mes_sol) OVER (
    PARTITION BY partida_general, partida_analitica, cuenta_contable,
      division, unidad_de_negocio, region, agencia, anio
    ORDER BY mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS Ppto_YTD_SOL
FROM densificada;


-- ==========================================================
-- VISTA 2: DENOMINADOR SEPARADO (VENTAS MES + YTD)
-- ==========================================================
CREATE OR REPLACE VIEW `data-warehouse-445921.pruebas_tpp.vw_pl_denominador_ventas_mes` AS
SELECT
  anio,
  mes,
  division,
  unidad_de_negocio,
  region,
  agencia,
  SUM(Real_Mes_USD) AS Venta_Real_Mes_USD_Denom,
  SUM(Real_Mes_SOL) AS Venta_Real_Mes_SOL_Denom,
  SUM(Ppto_Mes_USD) AS Venta_Ppto_Mes_USD_Denom,
  SUM(Ppto_Mes_SOL) AS Venta_Ppto_Mes_SOL_Denom,
  SUM(Real_YTD_USD) AS Venta_Real_YTD_USD_Denom,
  SUM(Real_YTD_SOL) AS Venta_Real_YTD_SOL_Denom,
  SUM(Ppto_YTD_USD) AS Venta_Ppto_YTD_USD_Denom,
  SUM(Ppto_YTD_SOL) AS Venta_Ppto_YTD_SOL_Denom
FROM `data-warehouse-445921.pruebas_tpp.vw_pl_base_reporte`
WHERE partida_general = 'INGRESOS DE LA EXPLOTACION'
GROUP BY 1,2,3,4,5,6;


-- ==========================================================
-- VISTA 3 (OPCIONAL): DATASET FINAL YA UNIDO
-- ==========================================================
CREATE OR REPLACE VIEW `data-warehouse-445921.pruebas_tpp.vw_pl_reporte_con_denominador` AS
SELECT
  b.*,
  d.Venta_Real_Mes_USD_Denom,
  d.Venta_Real_Mes_SOL_Denom,
  d.Venta_Ppto_Mes_USD_Denom,
  d.Venta_Ppto_Mes_SOL_Denom,
  d.Venta_Real_YTD_USD_Denom,
  d.Venta_Real_YTD_SOL_Denom,
  d.Venta_Ppto_YTD_USD_Denom,
  d.Venta_Ppto_YTD_SOL_Denom
FROM `data-warehouse-445921.pruebas_tpp.vw_pl_base_reporte` b
LEFT JOIN `data-warehouse-445921.pruebas_tpp.vw_pl_denominador_ventas_mes` d
  ON  d.anio              = b.anio
  AND d.mes               = b.mes
  AND d.division          = b.division
  AND d.unidad_de_negocio = b.unidad_de_negocio
  AND d.region            = b.region
  AND d.agencia           = b.agencia;


-- ==========================================================
-- USO EN LOOKER STUDIO (campo calculado)
-- ==========================================================
-- % Participación Real Mes (USD)
-- SAFE_DIVIDE(SUM(Real_Mes_USD), SUM(Venta_Real_Mes_USD_Denom))
--
-- % Participación Real Mes (SOL)
-- SAFE_DIVIDE(SUM(Real_Mes_SOL), SUM(Venta_Real_Mes_SOL_Denom))
--
-- % Participación Ppto Mes (USD)
-- SAFE_DIVIDE(SUM(Ppto_Mes_USD), SUM(Venta_Ppto_Mes_USD_Denom))
--
-- % Participación Ppto Mes (SOL)
-- SAFE_DIVIDE(SUM(Ppto_Mes_SOL), SUM(Venta_Ppto_Mes_SOL_Denom))

--
-- % Participación Real YTD (USD)
-- SAFE_DIVIDE(SUM(Real_YTD_USD), SUM(Venta_Real_YTD_USD_Denom))
--
-- % Participación Real YTD (SOL)
-- SAFE_DIVIDE(SUM(Real_YTD_SOL), SUM(Venta_Real_YTD_SOL_Denom))
--
-- % Participación Ppto YTD (USD)
-- SAFE_DIVIDE(SUM(Ppto_YTD_USD), SUM(Venta_Ppto_YTD_USD_Denom))
--
-- % Participación Ppto YTD (SOL)
-- SAFE_DIVIDE(SUM(Ppto_YTD_SOL), SUM(Venta_Ppto_YTD_SOL_Denom))
