/*
  ==================================================================================
  Análisis de KPIs - SOLUCIÓN DEFINITIVA CON FECHA DE ANÁLISIS CORRECTA (2025)
  ==================================================================================
*/

-- Paso 1: CORREGIR la fecha de análisis para que coincida con los datos reales.
WITH static_analysis_date AS (
    SELECT DATE('2025-07-01') AS analysis_date -- <-- ¡ESTA ES LA CORRECCIÓN CLAVE!
),

-- Paso 2: Definir los rangos de fechas (ahora para Mayo y Junio de 2025).
date_ranges AS (
    SELECT
        DATE_SUB((SELECT analysis_date FROM static_analysis_date), INTERVAL 30 DAY) AS current_period_start,
        (SELECT analysis_date FROM static_analysis_date) AS current_period_end,
        DATE_SUB((SELECT analysis_date FROM static_analysis_date), INTERVAL 60 DAY) AS prior_period_start,
        DATE_SUB((SELECT analysis_date FROM static_analysis_date), INTERVAL 31 DAY) AS prior_period_end
),

-- Paso 3: Agregar las métricas por período (no se necesita PARSE_DATE).
kpis_by_period AS (
    SELECT
        CASE
            WHEN date BETWEEN (SELECT current_period_start FROM date_ranges) AND (SELECT current_period_end FROM date_ranges) THEN 'Last 30 Days'
            WHEN date BETWEEN (SELECT prior_period_start FROM date_ranges) AND (SELECT prior_period_end FROM date_ranges) THEN 'Prior 30 Days'
        END AS period,
        SUM(spend) AS total_spend,
        SUM(conversions) AS total_conversions,
        SUM(conversions * 100) AS total_revenue 
    FROM
        `assesmentia.ads_spend.campaign_data`
    GROUP BY
        period
    HAVING 
        period IS NOT NULL
),

-- Paso 4: Calcular KPIs finales.
final_metrics AS (
    SELECT
        period,
        SAFE_DIVIDE(total_spend, total_conversions) AS cac,
        SAFE_DIVIDE(total_revenue, total_spend) AS roas
    FROM
        kpis_by_period
),

-- Paso 5: Pivotar la tabla para la comparación.
comparison_table AS (
    SELECT
        'CAC' AS metric,
        MAX(IF(period = 'Last 30 Days', cac, NULL)) AS current_period_value,
        MAX(IF(period = 'Prior 30 Days', cac, NULL)) AS prior_period_value
    FROM final_metrics
    GROUP BY metric
    
    UNION ALL
    
    SELECT
        'ROAS' AS metric,
        MAX(IF(period = 'Last 30 Days', roas, NULL)) AS current_period_value,
        MAX(IF(period = 'Prior 30 Days', roas, NULL)) AS prior_period_value
    FROM final_metrics
    GROUP BY metric
)

-- Paso 6: Generar la tabla final con deltas.
SELECT
    metric,
    ROUND(current_period_value, 2) AS last_30_days,
    ROUND(prior_period_value, 2) AS prior_30_days,
    ROUND(current_period_value - prior_period_value, 2) AS delta_absolute,
    CONCAT(
        CAST(ROUND(SAFE_DIVIDE(current_period_value - prior_period_value, prior_period_value) * 100, 2) AS STRING), 
        '%'
    ) AS delta_percentage
FROM
    comparison_table;


