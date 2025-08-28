# Dev Test – AI Data Engineer Solution

Este repositorio contiene la solución al reto para el puesto de AI Data Engineer. Incluye workflow de ingestión de datos, modelado de KPIs en SQL, acceso para analistas, y una demo de agente para consultas en lenguaje natural.

## 1. Requisitos

- Python 3.8+ (si usas scripts complementarios)
- Javscript ES6 (ECMAScript 6 o superior)
- BigQuery (o el warehouse que elegiste)
- n8n (automatización de workflows SQL/API)

# Ingesta de Datos (ETL) con n8n

El proceso de ingesta está totalmente automatizado a través de un workflow en n8n, permitiendo cargar el dataset ads_spend.csv, limpiar, transformar y enriquecer los datos antes de almacenarlos en el warehouse (BigQuery/DuckDB).

## Descripción del Flujo 

- Disparador manual

El flujo inicia al hacer clic en Execute workflow.

- Nodo HTTP Request

Descarga el archivo CSV usando la URL pública del raw ads_spend.csv en GitHub.

Se configura la cabecera User-Agent para evitar restricciones al descargar.

- Nodo Code (JavaScript personalizado)

Procesa el contenido CSV desde texto plano, convirtiendo cada registro en un objeto JSON estructurado y enriquecido con métricas calculadas.

Valida la estructura de los datos y reporta errores si el CSV está vacío o corrupto.

Realiza parsing de los campos numéricos y calcula métricas clave para cada registro:

![alt text](image-1.png)

El código completo se incluye abajo para referencia y puede ser reutilizado/adaptado directamente en n8n.

```javascript
// PROCESAR CSV desde JSON - VERSIÓN PARA N8N (RECORDS INDIVIDUALES)
console.log('=== INICIANDO PROCESAMIENTO ===');

// Verificar estructura de items
if (!items || items.length === 0) {
  console.log('ERROR: No hay items disponibles');
  return [{ json: { error: 'No hay datos disponibles' } }];
}

// Buscar los datos CSV
let csvData = null;
if (items[0].data) {
  csvData = items[0].data;
} else if (items[0].binary && items[0].binary.data) {
  csvData = items[0].binary.data;
} else if (items[0].json && items[0].json.data) {
  csvData = items[0].json.data;
}

if (!csvData || typeof csvData !== 'string') {
  console.log('ERROR: No se encontraron datos CSV válidos');
  return [{ json: { error: 'Datos CSV no encontrados' } }];
}

console.log('✅ CSV Data encontrado');

// Procesar CSV
const lines = csvData.split('\n').filter(line => line.trim());
const headers = lines[0].split(',');
console.log('Headers:', headers);

// Convertir a objetos
const data = [];
for (let i = 1; i < lines.length; i++) {
  const values = lines[i].split(',');
  if (values.length === headers.length) {
    const row = {};
    headers.forEach((header, index) => {
      row[header.trim()] = values[index] ? values[index].trim() : '';
    });
    data.push(row);
  }
}

console.log(`✅ Procesadas ${data.length} filas`);

// RETORNAR RECORDS INDIVIDUALES CON MÉTRICAS CALCULADAS
return data.map(row => {
  // Convertir valores a números
  const spend = parseFloat(row.spend) || 0;
  const clicks = parseInt(row.clicks) || 0;
  const impressions = parseInt(row.impressions) || 0;
  const conversions = parseInt(row.conversions) || 0;
  
  // Calcular métricas por fila
  const ctr = impressions > 0 ? parseFloat((clicks / impressions * 100).toFixed(2)) : 0;
  const conversionRate = clicks > 0 ? parseFloat((conversions / clicks * 100).toFixed(2)) : 0;
  const cpc = clicks > 0 ? parseFloat((spend / clicks).toFixed(2)) : 0;
  const costPerConversion = conversions > 0 ? parseFloat((spend / conversions).toFixed(2)) : 0;
  
  return {
    json: {
      date: row.date,
      platform: row.platform,
      account: row.account,
      campaign: row.campaign,
      country: row.country,
      device: row.device,
      spend: spend,
      clicks: clicks,
      impressions: impressions,
      conversions: conversions,
      ctr: ctr,
      conversion_rate: conversionRate,
      cpc: cpc,
      cost_per_conversion: costPerConversion,
      // Campos adicionales útiles para análisis
      impression_share: impressions > 0 ? 1 : 0,
      revenue_estimate: conversions * 50, // Estimado $50 por conversión
      profit_estimate: (conversions * 50) - spend
    }
  };
});
```

Inserta los objetos resultantes en la tabla del warehouse con columnas estándar + metadatos adicionales si aplica.

Se incluye el campo de fecha de carga y nombre de archivo para trazabilidad.

Ejemplo de Métrica Calculada por Registro

| date       | platform | campaign   | spend | clicks | impressions | conversions | ctr (%) | conversion_rate (%) | cpc  | cost_per_conversion | revenue_estimate | profit_estimate |
|------------|----------|------------|-------|--------|-------------|-------------|---------|--------------------|------|---------------------|------------------|-----------------|
| 2025-08-01 | Google   | Brand Ad   | 25.10 | 40     | 1000        | 5           | 4.00    | 12.50              | 0.63 | 5.02                | 250              | 224.90          |

Trazabilidad y Metadatos
Cada registro almacenado incluye los campos load_date (fecha de ingestión) y source_file_name para asegurar la trazabilidad y el control de versiones del dataset.

Control y Validación
El workflow reporta automáticamente errores y estadísticos (número de filas procesadas, estructura de encabezados) vía consola/logs en n8n para facilitar el monitoreo.

## Modelado de KPIs en SQL

El proceso para calcular KPIs críticos de marketing—CAC (Costo de Adquisición de Cliente) y ROAS (Retorno sobre la Inversión Publicitaria)—se gestiona mediante dos nodos clave en el workflow de n8n: uno para preparar los parámetros y otro para ejecutar la consulta en BigQuery. Esto permite comparar el rendimiento entre los últimos 30 días y los 30 días previos de forma automatizada.

1. Parámetros Dinámicos: Node Code
Se define un nodo de código que toma la configuración de rangos de fecha enviada por el Webhook. Así, el análisis es dinámico y parametrizable desde la API:

```javascript
// Obtener el objeto 'query' de la entrada del webhook.
const query = $input.item.json.query;
const end_date = (query && query.end_date) ? query.end_date : '2025-07-01';
const days = (query && query.days) ? query.days : 30;
// Devolver el objeto JSON para el siguiente nodo (SQL)
return [{
  json: {
    end_date: end_date,
    days: parseInt(days, 10)
  }
}];

```

2. SQL Query Parametrizado
El nodo "Execute SQL query" utiliza los parámetros (end_date, days) para comparar los KPIs entre los dos periodos, agrupando y calculando todo en una sola consulta:

![alt text](image-2.png)

Resultado en formato tabla con valores actuales, previos y sus deltas (absoluto y porcentual):

```
sql
WITH date_ranges AS (
    SELECT
        DATE_SUB(CAST('{{ $json.end_date }}' AS DATE), INTERVAL {{ $json.days }} DAY) AS current_period_start,
        CAST('{{ $json.end_date }}' AS DATE) AS current_period_end,
        DATE_SUB(CAST('{{ $json.end_date }}' AS DATE), INTERVAL {{ $json.days }} * 2 DAY) AS prior_period_start,
        DATE_SUB(CAST('{{ $json.end_date }}' AS DATE), INTERVAL {{ $json.days }} + 1 DAY) AS prior_period_end
),
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
final_metrics AS (
    SELECT
        period,
        SAFE_DIVIDE(total_spend, total_conversions) AS cac,
        SAFE_DIVIDE(total_revenue, total_spend) AS roas
    FROM
        kpis_by_period
),
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
```

3. Resultado: Tabla Comparativa

| metric | last_30_days | prior_30_days | delta_absolute | delta_percentage |
|--------|--------------|---------------|----------------|------------------|
| CAC    | 5.02         | 4.65          | 0.37           | 7.96%            |
| ROAS   | 4.80         | 4.40          | 0.40           | 9.09%            |

Este enfoque permite análisis flexible y comparativo de KPIs en distintos periodos, facilitando la interpretación para analistas y decisores. Los resultados pueden consumirse vía API, integración n8n, o directamente en la base de datos.



# Exposición de Métricas para Analistas (Parte 3)
Para facilitar el acceso directo y simple a los KPIs, se ha implementado un endpoint API ligero con n8n. Los analistas pueden consultar las métricas realizando peticiones HTTP tipo GET, especificando rangos de fechas si lo desean. El resultado se entrega en formato JSON, listo para usarse en dashboards, reportes, o scripts de análisis.

Flujo API
El workflow de n8n expone un Webhook en la ruta:

text
GET https://ccartag1906.app.n8n.cloud/webhook-test/metrics
Permite parámetros como start y end para personalizar el rango temporal analizado.

Ejemplo de Consulta
Un analista puede obtener los KPIs haciendo un request GET al endpoint, recibiendo la respuesta en JSON estructurado:

```
json
{
  "metric": "CAC",
  "last_30_days": 29.81,
  "prior_30_days": 32.27,
  "delta_absolute": -2.46,
  "delta_percentage": "-7.63%"
}

```

![
](image-3.png)

- Integración

El acceso es abierto (sin autenticación para pruebas/demo).

El resultado incluye los valores relevantes para CAC y ROAS según el rango de fechas solicitado, junto con el delta absoluto y relativo.

Se puede visualizar y consumir fácilmente con herramientas como Postman, scripts Python/R, o dashboards BI.

Este enfoque simplifica el acceso y explotación de los KPIs desde cualquier entorno, eliminando la necesidad de conocimiento técnico avanzado para el usuario final.

# Agente IA: Demo de Preguntas en Lenguaje Natural (Bonus)

Como demostración adicional, se implementó un workflow en n8n para resolver preguntas típicas de analistas usando lenguaje natural. El flujo combina un modelo de chat (OpenAI) y una herramienta de consulta automática que traduce la petición del usuario en parámetros adecuados para calcular KPIs como CAC y ROAS.

Ejemplo de Pregunta
Un usuario puede enviar la pregunta:
```
“¿Compara CAC y ROAS para los últimos 30 días vs los 30 días anteriores?”
```

Mapeo y Ejecución Automática
El workflow detecta el mensaje recibido en el chat.

El agente IA interpreta la intención y prepara los parámetros necesarios (end_date, days).

Se realiza automáticamente una solicitud GET al endpoint /metrics, pasando los parámetros de fecha necesarios.

El API retorna una respuesta JSON con los valores comparativos para CAC y ROAS, incluyendo las diferencias absolutas y relativas (%).

Template de Mapeo

```
text
Pregunta: "Compara CAC y ROAS para los últimos 30 días vs los 30 días anteriores."
↓
Parámetros generados:
- end_date = Fecha actual
- days = 30

Solicitud API:
GET https://ccartag1906.app.n8n.cloud/webhook/metrics?end_date={hoy}&days=30

Respuesta:
{
  "metric": "CAC",
  "last_30_days": 29.81,
  "prior_30_days": 32.27,
  "delta_absolute": -2.46,
  "delta_percentage": "-7.63%"
}

```
## Ventajas
Permite a usuarios no técnicos obtener análisis avanzado simplemente escribiendo preguntas al agente.

El workflow puede ser extendido con otras métricas o modificar el rango temporal fácilmente.

Este ejemplo demuestra cómo conectar lenguaje natural y análisis de datos automatizado, facilitando la interpretación instantánea de KPIs en conversación con el agente IA.
