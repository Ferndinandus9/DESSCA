-- ==========================================================
-- CONSULTA SIMPLIFICADA (2026 / Opt_26) - SOLO USD
-- Nivel: PARTIDA_GENERAL + dimensiones mandatorias
-- Objetivo: reducir volumen para Looker Studio
-- ==========================================================

CREATE OR REPLACE VIEW `data-warehouse-445921.pruebas_tpp.vw_pl_reporte_pg_simple_2026` AS
WITH
-- -----------------------------
-- 1) BASE REAL (agrupada)
-- -----------------------------
base_sofia_pg AS (
  SELECT
    IFNULL(NULLIF(TRIM(ParGeneral), ''), '*') AS partida_general,
    CASE WHEN Division = 'AYL' THEN 'NNL' ELSE Division END AS division,
    UNegocio AS unidad_de_negocio,
    CASE
      WHEN Region = 'Callao' THEN 'CALLAO'
      WHEN Region = 'Sur'    THEN 'SUR'
      WHEN Region = 'Norte'  THEN 'NORTE'
      ELSE Region
    END AS region,
    IFNULL(NULLIF(TRIM(Agencia), ''), '*') AS agencia,
    SAFE_CAST(Anio AS INT64) AS anio,
    SAFE_CAST(Mes  AS INT64) AS mes,
    SUM(DistribuidoD) AS real_mes_usd
  FROM `data-warehouse-445921.pruebas_tpp.sofia_autom_completo`
  WHERE Anio = 2026
  GROUP BY 1,2,3,4,5,6,7
),

-- -----------------------------
-- 2) BASE PPTO (agrupada)
-- -----------------------------
base_ppto_pg AS (
  SELECT
    IFNULL(NULLIF(TRIM(partida_general), ''), '*') AS partida_general,
    CASE WHEN division = 'AYL' THEN 'NNL' ELSE division END AS division,
    un AS unidad_de_negocio,
    CASE
      WHEN region = 'Callao' THEN 'CALLAO'
      WHEN region = 'Sur'    THEN 'SUR'
      WHEN region = 'Norte'  THEN 'NORTE'
      ELSE region
    END AS region,
    IFNULL(NULLIF(TRIM(un_detalle), ''), '*') AS agencia,
    SAFE_CAST(anio AS INT64) AS anio,
    CASE UPPER(mes)
      WHEN 'ENERO'      THEN 1  WHEN 'FEBRERO'    THEN 2
      WHEN 'MARZO'      THEN 3  WHEN 'ABRIL'      THEN 4
      WHEN 'MAYO'       THEN 5  WHEN 'JUNIO'      THEN 6
      WHEN 'JULIO'      THEN 7  WHEN 'AGOSTO'     THEN 8
      WHEN 'SETIEMBRE'  THEN 9  WHEN 'SEPTIEMBRE' THEN 9
      WHEN 'OCTUBRE'    THEN 10 WHEN 'NOVIEMBRE'  THEN 11
      WHEN 'DICIEMBRE'  THEN 12
    END AS mes,
    SUM(monto_dolares) AS ppto_mes_usd
  FROM `data-warehouse-445921.pruebas_tpp.ppto_completo`
  WHERE anio = 2026
    AND version_ppto = 'Opt_26'
  GROUP BY 1,2,3,4,5,6,7
),

-- -----------------------------
-- 3) CASCADA REAL (solo partida_general)
-- -----------------------------
r_mc AS (
  SELECT 'MARGEN DE CONTRIBUCION' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(real_mes_usd) AS real_mes_usd
  FROM base_sofia_pg
  WHERE partida_general IN ('INGRESOS DE LA EXPLOTACION','COSTO VARIABLE')
  GROUP BY 2,3,4,5,6,7
),
r_base1 AS (SELECT * FROM base_sofia_pg UNION ALL SELECT * FROM r_mc),

r_mb AS (
  SELECT 'MARGEN BRUTO' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(real_mes_usd) AS real_mes_usd
  FROM r_base1
  WHERE partida_general IN ('MARGEN DE CONTRIBUCION','COSTO FIJO')
  GROUP BY 2,3,4,5,6,7
),
r_base2 AS (SELECT * FROM r_base1 UNION ALL SELECT * FROM r_mb),

r_m1 AS (
  SELECT 'M1' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(real_mes_usd) AS real_mes_usd
  FROM r_base2
  WHERE partida_general IN ('MARGEN BRUTO','GASTOS CON EL PERSONAL FIJO','GASTOS CON EL PERSONAL VARIABLE','GASTOS CON EL PERSONAL OTROS')
  GROUP BY 2,3,4,5,6,7
),
r_base3 AS (SELECT * FROM r_base2 UNION ALL SELECT * FROM r_m1),

r_ebitda AS (
  SELECT 'EBITDA' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(real_mes_usd) AS real_mes_usd
  FROM r_base3
  WHERE partida_general IN ('M1','GASTOS INDIRECTOS')
  GROUP BY 2,3,4,5,6,7
),
r_base4 AS (SELECT * FROM r_base3 UNION ALL SELECT * FROM r_ebitda),

r_m2 AS (
  SELECT 'M2' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(real_mes_usd) AS real_mes_usd
  FROM r_base4
  WHERE partida_general IN ('EBITDA','GASTOS POR AMORT. Y DEPREC.')
  GROUP BY 2,3,4,5,6,7
),
r_base5 AS (SELECT * FROM r_base4 UNION ALL SELECT * FROM r_m2),

r_rai AS (
  SELECT 'RESULTADOS ANTES DE IMPUESTOS' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(real_mes_usd) AS real_mes_usd
  FROM r_base5
  WHERE partida_general IN (
    'INGRESOS DE LA EXPLOTACION','COSTO VARIABLE','COSTO FIJO','GASTOS CON EL PERSONAL FIJO',
    'GASTOS CON EL PERSONAL VARIABLE','GASTOS CON EL PERSONAL OTROS','GASTOS INDIRECTOS',
    'GASTOS POR AMORT. Y DEPREC.','GASTOS/INGRESO NO OPERACIONALES')
  GROUP BY 2,3,4,5,6,7
),
real_pg AS (
  SELECT * FROM r_base5
  UNION ALL SELECT * FROM r_rai
),

-- -----------------------------
-- 4) CASCADA PPTO (solo partida_general)
-- -----------------------------
p_mc AS (
  SELECT 'MARGEN DE CONTRIBUCION' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(ppto_mes_usd) AS ppto_mes_usd
  FROM base_ppto_pg
  WHERE partida_general IN ('INGRESOS DE LA EXPLOTACION','COSTO VARIABLE')
  GROUP BY 2,3,4,5,6,7
),
p_base1 AS (SELECT * FROM base_ppto_pg UNION ALL SELECT * FROM p_mc),

p_mb AS (
  SELECT 'MARGEN BRUTO' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(ppto_mes_usd) AS ppto_mes_usd
  FROM p_base1
  WHERE partida_general IN ('MARGEN DE CONTRIBUCION','COSTO FIJO')
  GROUP BY 2,3,4,5,6,7
),
p_base2 AS (SELECT * FROM p_base1 UNION ALL SELECT * FROM p_mb),

p_m1 AS (
  SELECT 'M1' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(ppto_mes_usd) AS ppto_mes_usd
  FROM p_base2
  WHERE partida_general IN ('MARGEN BRUTO','GASTOS CON EL PERSONAL FIJO','GASTOS CON EL PERSONAL VARIABLE','GASTOS CON EL PERSONAL OTROS')
  GROUP BY 2,3,4,5,6,7
),
p_base3 AS (SELECT * FROM p_base2 UNION ALL SELECT * FROM p_m1),

p_ebitda AS (
  SELECT 'EBITDA' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(ppto_mes_usd) AS ppto_mes_usd
  FROM p_base3
  WHERE partida_general IN ('M1','GASTOS INDIRECTOS')
  GROUP BY 2,3,4,5,6,7
),
p_base4 AS (SELECT * FROM p_base3 UNION ALL SELECT * FROM p_ebitda),

p_m2 AS (
  SELECT 'M2' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(ppto_mes_usd) AS ppto_mes_usd
  FROM p_base4
  WHERE partida_general IN ('EBITDA','GASTOS POR AMORT. Y DEPREC.')
  GROUP BY 2,3,4,5,6,7
),
p_base5 AS (SELECT * FROM p_base4 UNION ALL SELECT * FROM p_m2),

p_rai AS (
  SELECT 'RESULTADOS ANTES DE IMPUESTOS' AS partida_general, division, unidad_de_negocio, region, agencia, anio, mes,
         SUM(ppto_mes_usd) AS ppto_mes_usd
  FROM p_base5
  WHERE partida_general IN (
    'INGRESOS DE LA EXPLOTACION','COSTO VARIABLE','COSTO FIJO','GASTOS CON EL PERSONAL FIJO',
    'GASTOS CON EL PERSONAL VARIABLE','GASTOS CON EL PERSONAL OTROS','GASTOS INDIRECTOS',
    'GASTOS POR AMORT. Y DEPREC.','GASTOS/INGRESO NO OPERACIONALES')
  GROUP BY 2,3,4,5,6,7
),
ppto_pg AS (
  SELECT * FROM p_base5
  UNION ALL SELECT * FROM p_rai
),

-- -----------------------------
-- 5) PPTO ANUAL (mismo grano simple)
-- -----------------------------
ppto_anual AS (
  SELECT
    partida_general, division, unidad_de_negocio, region, agencia, anio,
    SUM(ppto_mes_usd) AS ppto_anual_usd
  FROM ppto_pg
  GROUP BY 1,2,3,4,5,6
),

-- -----------------------------
-- 6) REAL + PPTO mes (densificada por partida_general)
--    Esto evita que el denominador cambie por fila al agrupar en Looker.
-- -----------------------------
partidas_catalogo AS (
  SELECT DISTINCT partida_general FROM real_pg
  UNION DISTINCT
  SELECT DISTINCT partida_general FROM ppto_pg
),

dim_mes AS (
  SELECT DISTINCT division, unidad_de_negocio, region, agencia, anio, mes FROM real_pg
  UNION DISTINCT
  SELECT DISTINCT division, unidad_de_negocio, region, agencia, anio, mes FROM ppto_pg
),

base_densificada AS (
  SELECT
    pc.partida_general,
    dm.division,
    dm.unidad_de_negocio,
    dm.region,
    dm.agencia,
    dm.anio,
    dm.mes
  FROM dim_mes dm
  CROSS JOIN partidas_catalogo pc
),

merged_mes AS (
  SELECT
    bd.partida_general,
    bd.division,
    bd.unidad_de_negocio,
    bd.region,
    bd.agencia,
    bd.anio,
    bd.mes,
    DATE(bd.anio, bd.mes, 1) AS periodo_mes,
    IFNULL(r.real_mes_usd, 0) AS real_mes_usd,
    IFNULL(p.ppto_mes_usd, 0) AS ppto_mes_usd
  FROM base_densificada bd
  LEFT JOIN real_pg r
    ON  r.partida_general   = bd.partida_general
    AND r.division          = bd.division
    AND r.unidad_de_negocio = bd.unidad_de_negocio
    AND r.region            = bd.region
    AND r.agencia           = bd.agencia
    AND r.anio              = bd.anio
    AND r.mes               = bd.mes
  LEFT JOIN ppto_pg p
    ON  p.partida_general   = bd.partida_general
    AND p.division          = bd.division
    AND p.unidad_de_negocio = bd.unidad_de_negocio
    AND p.region            = bd.region
    AND p.agencia           = bd.agencia
    AND p.anio              = bd.anio
    AND p.mes               = bd.mes
),

-- denominadores ventas al grano exacto
venta_denom AS (
  SELECT
    anio, mes, division, unidad_de_negocio, region, agencia,
    SUM(real_mes_usd) AS venta_real_mes_usd,
    SUM(ppto_mes_usd) AS venta_ppto_mes_usd
  FROM merged_mes
  WHERE partida_general = 'INGRESOS DE LA EXPLOTACION'
  GROUP BY 1,2,3,4,5,6
),

-- fallback denominadores sin agencia
venta_denom_sa AS (
  SELECT
    anio, mes, division, unidad_de_negocio, region,
    SUM(real_mes_usd) AS venta_real_mes_usd_sa,
    SUM(ppto_mes_usd) AS venta_ppto_mes_usd_sa
  FROM merged_mes
  WHERE partida_general = 'INGRESOS DE LA EXPLOTACION'
  GROUP BY 1,2,3,4,5
)

SELECT
  m.partida_general,
  m.division,
  m.unidad_de_negocio,
  m.region,
  m.agencia,
  m.anio,
  m.mes,
  m.mes AS mes_orden,
  FORMAT('%04d-%02d', m.anio, m.mes) AS mes_clave,
  m.periodo_mes,

  m.ppto_mes_usd AS Ppto_Mes_USD,
  m.real_mes_usd AS Real_Mes_USD,
  m.real_mes_usd - m.ppto_mes_usd AS Var_Mes_USD,

  SUM(m.real_mes_usd) OVER (
    PARTITION BY m.partida_general, m.division, m.unidad_de_negocio, m.region, m.agencia, m.anio
    ORDER BY m.mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS Real_YTD_USD,

  SUM(m.ppto_mes_usd) OVER (
    PARTITION BY m.partida_general, m.division, m.unidad_de_negocio, m.region, m.agencia, m.anio
    ORDER BY m.mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
  ) AS Ppto_YTD_USD,

  IFNULL(pa.ppto_anual_usd, 0) AS Ppto_Anual_USD,

  SAFE_DIVIDE(
    SUM(m.real_mes_usd) OVER (
      PARTITION BY m.partida_general, m.division, m.unidad_de_negocio, m.region, m.agencia, m.anio
      ORDER BY m.mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ),
    IFNULL(pa.ppto_anual_usd, 0)
  ) AS Avance_Real_vs_Ppto_Anual_USD,

  SAFE_DIVIDE(
    SUM(m.ppto_mes_usd) OVER (
      PARTITION BY m.partida_general, m.division, m.unidad_de_negocio, m.region, m.agencia, m.anio
      ORDER BY m.mes ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ),
    IFNULL(pa.ppto_anual_usd, 0)
  ) AS Avance_Ppto_vs_Ppto_Anual_USD,

  COALESCE(vd.venta_real_mes_usd, vds.venta_real_mes_usd_sa) AS Venta_Real_Mes_USD_Denom,
  COALESCE(vd.venta_ppto_mes_usd, vds.venta_ppto_mes_usd_sa) AS Venta_Ppto_Mes_USD_Denom,

  SAFE_DIVIDE(
    m.ppto_mes_usd,
    NULLIF(COALESCE(vd.venta_ppto_mes_usd, vds.venta_ppto_mes_usd_sa), 0)
  ) AS Pct_Ppto_vs_IOS_Mes_USD,
  SAFE_DIVIDE(
    m.real_mes_usd,
    NULLIF(COALESCE(vd.venta_real_mes_usd, vds.venta_real_mes_usd_sa), 0)
  ) AS Pct_Real_vs_IOS_Mes_USD

FROM merged_mes m
LEFT JOIN ppto_anual pa
  ON  pa.partida_general   = m.partida_general
  AND pa.division          = m.division
  AND pa.unidad_de_negocio = m.unidad_de_negocio
  AND pa.region            = m.region
  AND pa.agencia           = m.agencia
  AND pa.anio              = m.anio
LEFT JOIN venta_denom vd
  ON  vd.anio              = m.anio
  AND vd.mes               = m.mes
  AND vd.division          = m.division
  AND vd.unidad_de_negocio = m.unidad_de_negocio
  AND vd.region            = m.region
  AND vd.agencia           = m.agencia
LEFT JOIN venta_denom_sa vds
  ON  vds.anio              = m.anio
  AND vds.mes               = m.mes
  AND vds.division          = m.division
  AND vds.unidad_de_negocio = m.unidad_de_negocio
  AND vds.region            = m.region;
