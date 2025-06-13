# Matomo Analytics Examples

This document provides practical SQL examples for analyzing e-commerce data with Matomo. These queries demonstrate real-world analytics patterns for tracking visitor behavior, conversions, and marketing attribution.

## Table of Contents

- [Visitor Conversion Analysis](#visitor-conversion-analysis)
- [Daily Website Metrics with Multi-Source Attribution](#daily-website-metrics-with-multi-source-attribution)
- [A/B Testing Analysis](#ab-testing-analysis)
- [Example Analysis Queries](#example-analysis-queries)

## Visitor Conversion Analysis

This analysis tracks the complete visitor journey from first visit to purchase, providing insights into customer behavior and attribution across different touchpoints.

### Visitor Profile and Conversion Funnel

The following query creates a comprehensive view of converted visitors, tracking their journey from first visit to purchase with detailed attribution information:

```sql
WITH visitor_profile AS (
    SELECT 
        hex(v.idvisitor) as visitor_id,
        min(v.idvisit) as first_visit_id, 
        max(v.idvisit) as max_visit_id,
        min(v.visit_first_action_time) as first_visit_time, 
        max(v.visit_last_action_time) as last_visit_time,
        count(distinct v.idvisit) as visits,
        sum(v.visit_total_actions) as total_actions,
        sum(v.visit_total_actions) / count(distinct v.idvisit) as actions_per_visit,
        sum(v.visit_goal_buyer) as buy_goals, 
        sum(v.visit_goal_converted) as converted_goal,
        count(distinct i.shopify_order_id) as shopify_orders,
        min(case when i.shopify_order_id then v.idvisit end) as first_purchase_idvisit,
        min(case when i.shopify_order_id then v.visit_first_action_time end) as purchase_visit_time
    FROM matomo.matomo_log_visit v
    JOIN matomo.matomo_log_conversion c ON c.idvisit = v.idvisit
    LEFT JOIN line_item_extended_materialized i ON i.shopify_order_id = c.idorder
    GROUP BY 1
)
SELECT 
    vp.*,
    fv.referer_name as first_visit_referer,
    CASE 
        WHEN fv.referer_type = 1 THEN 'direct' 
        WHEN fv.referer_type = 2 THEN 'organic'
        WHEN fv.referer_type = 3 THEN 'website'
        WHEN fv.referer_type = 6 AND fv.referer_name = 'evergreen' THEN 'share_a_sale'
        WHEN fv.referer_type = 6 THEN 'campaign' 
        ELSE 'other' 
    END as first_visit_referal_type,
    gv.referer_name as purchase_referer,
    CASE 
        WHEN gv.referer_type = 1 THEN 'direct' 
        WHEN gv.referer_type = 2 THEN 'organic'
        WHEN gv.referer_type = 3 THEN 'website'
        WHEN gv.referer_type = 6 AND gv.referer_name = 'evergreen' THEN 'share_a_sale' 
        WHEN gv.referer_type = 6 THEN 'campaign' 
        WHEN gv.referer_type IS NULL THEN NULL
        ELSE 'other' 
    END as purchase_referal_type,
    SUBSTRING_INDEX(a.`name`, '?', 1) as first_visit_landing_url,
    DATEDIFF(purchase_visit_time, first_visit_time) as considerastion_days
FROM visitor_profile vp
JOIN matomo.matomo_log_visit fv ON fv.idvisit = vp.first_visit_id
LEFT JOIN matomo.matomo_log_action a ON a.idaction = fv.visit_entry_idaction_url AND a.type = 1
LEFT JOIN matomo.matomo_log_visit gv ON gv.idvisit = vp.first_purchase_idvisit;
```

**Key Features:**
- Tracks visitor engagement metrics (visits, actions, time on site)
- Identifies first touch and last touch attribution
- Calculates customer consideration period (time from first visit to purchase)
- Integrates with e-commerce order data for revenue attribution

## Daily Website Metrics with Multi-Source Attribution

This comprehensive analysis combines Matomo session data with conversion events to provide a complete picture of daily website performance across different traffic sources.

### Source Classification and Daily Metrics

The query uses sophisticated logic to classify traffic sources and combine multiple data points into daily metrics:

```sql
WITH source_classification AS (
    SELECT 
        v.idvisit,
        v.visit_first_action_time,
        -- Session Medium Classification
        CASE 
            WHEN v.campaign_medium IN ('cpc', 'paid', 'paid_social') THEN 'paid'
            WHEN v.campaign_medium IN ('organic', 'product_sync') THEN 'organic'
            WHEN v.campaign_medium = 'email' THEN 'email'
            WHEN v.campaign_medium IN ('referral', 'affiliate') THEN 'referral'
            WHEN v.campaign_medium IN ('(none)', '(not set)', 'webview') THEN 'direct'
            WHEN v.campaign_medium IN ('facebook', 'social') THEN 'social'
            WHEN v.campaign_medium IS NULL THEN
                CASE 
                    WHEN v.referer_name IN ('Google', 'DuckDuckGo', 'Bing', 'Yahoo!', 'Brave') THEN 'organic'
                    WHEN v.referer_name IN ('Facebook', 'Instagram', 'YouTube', 'reddit', 'Pinterest') THEN 'social'
                    WHEN v.referer_url LIKE '%mydomain.com%' OR v.referer_name IS NULL THEN 'direct'
                    WHEN v.referer_name LIKE 'www%' THEN 'referral'
                    WHEN v.referer_name LIKE '%email%' THEN 'email'
                    WHEN v.referer_name LIKE '%app%' THEN 'direct'
                    WHEN v.referer_url LIKE '%google.com%' AND v.referer_name IS NOT NULL THEN 'paid'
                    WHEN v.referer_url LIKE '%facebook.com%' AND v.referer_name IS NOT NULL THEN 'paid'
                    WHEN v.referer_url LIKE '%shareasale%' AND v.referer_name IS NOT NULL THEN 'referral'
                    ELSE 'other-undefined'
                END
            ELSE 'other-undefined'
        END as session_medium,
        
        -- Session Source Classification
        CASE 
            WHEN v.campaign_medium IS NULL THEN
                CASE 
                    WHEN v.referer_name = 'Google' THEN 'google'
                    WHEN v.referer_name = 'DuckDuckGo' THEN 'duckduckgo'
                    WHEN v.referer_name = 'Bing' THEN 'bing'
                    WHEN v.referer_name = 'Yahoo!' THEN 'yahoo'
                    WHEN v.referer_name = 'Brave' THEN 'search.brave.com'
                    WHEN v.referer_name = 'Facebook' THEN 'facebook'
                    WHEN v.referer_name = 'Instagram' THEN 'instagram.com'
                    WHEN v.referer_name = 'YouTube' THEN 'youtube.com'
                    WHEN v.referer_name = 'reddit' THEN 'reddit.com'
                    WHEN v.referer_name = 'Pinterest' THEN 'pinterest.com'
                    WHEN v.referer_url = '' OR v.referer_url LIKE '%mydomain.com%' OR v.referer_url LIKE '%mydomain%' THEN '(direct)'
                    WHEN v.referer_url LIKE '%shareasale%' THEN 'share_a_sale'
                    WHEN v.referer_url LIKE '%google%' THEN 'google'
                    WHEN v.referer_url LIKE '%facebook%' THEN 'facebook'
                    WHEN v.referer_url LIKE '%instagram%' THEN 'instagram.com'
                    ELSE COALESCE(v.referer_name, 'undefined')
                END
            WHEN v.campaign_medium = 'affiliate' THEN 'share_a_sale'
            WHEN v.campaign_medium = 'webview' OR v.referer_name = 'app_cpg' THEN 'app'
            WHEN v.campaign_medium = 'klaviyo' OR v.referer_url LIKE '%klaviyo%' THEN 'Klaviyo'
            ELSE COALESCE(v.referer_name, 'undefined')
        END as session_source
    FROM matomo.matomo_log_visit v
),

sessions_data AS (
    -- Matomo sessions with source classification
    SELECT 
        DATE(sc.visit_first_action_time) as report_date,
        sc.session_medium,
        sc.session_source,
        NULL as session_campaign,
        NULL as sessions, 
        NULL as engaged_sessions,
        count(DISTINCT sc.idvisit) as matomo_sessions, 
        count(CASE WHEN v.visit_total_actions > 1 THEN sc.idvisit END) as matomo_engaged_sessions,
        NULL as pdp_sessions,
        NULL as matomo_pdp_sessions,
        NULL as matomo_add_to_cart,
        NULL as cost,
        NULL as revenue
    FROM source_classification sc
    JOIN matomo.matomo_log_visit v ON sc.idvisit = v.idvisit
    LEFT JOIN matomo.matomo_log_action lae ON v.visit_entry_idaction_url = lae.idaction 
    GROUP BY 1, 2, 3, 4
),

pdp_data AS (
    -- Matomo Product Detail Page (PDP) views
    SELECT 
        DATE(l.server_time) as report_date,
        sc.session_medium,
        sc.session_source,
        NULL as session_campaign,
        NULL as sessions, 
        NULL as engaged_sessions,
        NULL as matomo_sessions, 
        NULL as matomo_engaged_sessions,
        NULL as pdp_sessions,
        count(DISTINCT l.idvisit) as matomo_pdp_sessions,
        NULL as matomo_add_to_cart,
        NULL as cost,
        NULL as revenue
    FROM matomo.matomo_log_link_visit_action l 
    JOIN matomo.matomo_log_action a ON l.idaction_url = a.idaction
    JOIN source_classification sc ON l.idvisit = sc.idvisit
    WHERE a.type = 1 -- Page URL
      AND l.idsite = 1
      AND SUBSTRING_INDEX(a.name, '?', 1) = 'myproductpage'
    GROUP BY 1, 2, 3, 4
),

cart_data AS (
    -- Matomo Add to Cart events
    SELECT 
        DATE(l.server_time) as report_date,
        sc.session_medium,
        sc.session_source,
        NULL as session_campaign,
        NULL as sessions, 
        NULL as engaged_sessions,
        NULL as matomo_sessions, 
        NULL as matomo_engaged_sessions,
        NULL as pdp_sessions,
        NULL as matomo_pdp_sessions,
        count(DISTINCT l.idvisit) as matomo_add_to_cart,
        NULL as cost,
        NULL as revenue
    FROM matomo.matomo_log_link_visit_action l
    JOIN matomo.matomo_log_action a ON l.idaction_url_ref = a.idaction
    JOIN source_classification sc ON l.idvisit = sc.idvisit
    WHERE a.type = 1 -- Page URL off of url_ref
      AND l.idsite = 1
      AND SUBSTRING_INDEX(a.name, '?', 1) = 'myproductpage' -- referral page
      AND l.idaction_event_action = 55 -- add to cart
    GROUP BY 1, 2, 3, 4
),

conversion_data AS (
    SELECT 
        DATE(c.server_time) as report_date,
        sc.session_medium,
        sc.session_source,
        NULL as session_campaign,
        NULL as sessions, 
        NULL as engaged_sessions,
        NULL as matomo_sessions, 
        NULL as matomo_engaged_sessions,
        NULL as pdp_sessions,
        NULL as matomo_pdp_sessions,
        NULL as matomo_add_to_cart,
        NULL as cost,
        NULL as revenue
    FROM matomo.matomo_log_conversion c 
    JOIN customer.order_summary o ON c.idorder = o.shopify_order_id
    JOIN source_classification sc ON c.idvisit = sc.idvisit
    GROUP BY 1, 2, 3, 4
),

combined_data AS (
    SELECT * FROM sessions_data
    UNION ALL SELECT * FROM pdp_data
    UNION ALL SELECT * FROM cart_data
    UNION ALL SELECT * FROM conversion_data
)

SELECT 
    report_date,
    session_medium,
    session_source, 
    session_campaign,
    sum(sessions) as sessions,
    sum(engaged_sessions) as engaged_sessions,
    sum(matomo_sessions) as matomo_sessions,
    sum(matomo_engaged_sessions) as matomo_engaged_sessions,
    sum(pdp_sessions) as pdp_sessions,
    sum(matomo_pdp_sessions) as matomo_pdp_sessions,
    sum(matomo_add_to_cart) as matomo_add_to_cart,
    sum(cost) as cost,
    sum(revenue) as revenue
FROM combined_data 
WHERE report_date >= '2022-04-06'
GROUP BY 1, 2, 3, 4
ORDER BY 1, 2 DESC;
```

**Key Features:**
- **Smart Source Classification**: Automatically categorizes traffic into meaningful channels (paid, organic, direct, social, email, referral)
- **Multi-Touch Attribution**: Tracks the complete funnel from sessions to conversions
- **E-commerce Integration**: Links Matomo data with order/revenue data
- **Modular Design**: Uses CTEs for easy customization and maintenance

## A/B Testing Analysis

Track and analyze A/B test performance with detailed conversion metrics.

### A/B Test Performance Tracking

```sql
SELECT
    t.server_time, 
    CONCAT(e.name, '(', e.idexperiment, ')') as experiment, 
    e.idexperiment,
    t.idvisit, 
    t.idvariation,
    CASE 
        WHEN t.idvariation = 0 THEN 'Original(0)' 
        ELSE CONCAT('Test variant(', t.idvariation, ')') 
    END as variant,
    HEX(t.idvisitor) as visitor_id,
    t.entered,
    v.visit_goal_buyer,
    v.visit_goal_converted,
    i.shopify_id as shopify_order_id, 
    i.total_price as order_value
FROM matomo.matomo_log_abtesting t
JOIN matomo.matomo_experiments e ON t.idexperiment = e.idexperiment
JOIN matomo.matomo_log_visit v ON v.idvisit = t.idvisit
LEFT JOIN matomo.matomo_log_conversion c ON c.idvisit = v.idvisit
LEFT JOIN customer.order_extended_materialized i ON i.shopify_id = c.idorder;
```

**Key Features:**
- Links A/B test variations to actual conversions and revenue
- Tracks visitor-level experiment participation
- Enables statistical analysis of test performance

## Example Analysis Queries

These practical queries demonstrate how to use the above views for common analytics use cases.

### Conversion Funnel Analysis by Traffic Source

Analyze how different traffic sources perform through your conversion funnel:

```sql
SELECT 
    report_date,
    session_medium,
    matomo_sessions,
    matomo_pdp_sessions,
    matomo_add_to_cart,
    CASE WHEN matomo_sessions > 0 THEN matomo_pdp_sessions / matomo_sessions ELSE 0 END as session_to_pdp_rate,
    CASE WHEN matomo_pdp_sessions > 0 THEN matomo_add_to_cart / matomo_pdp_sessions ELSE 0 END as pdp_to_cart_rate
FROM daily_key_website_metrics
WHERE report_date >= '2024-01-01'
AND matomo_sessions > 0
ORDER BY report_date DESC, matomo_sessions DESC;
```

### A/B Test Performance Comparison

Compare conversion rates and revenue across test variants:

```sql
SELECT 
    experiment,
    variant,
    count(distinct visitor_id) as visitors,
    count(distinct idvisit) as visits,
    sum(visit_goal_converted) as conversions,
    sum(order_value) as total_revenue,
    sum(visit_goal_converted) / count(distinct idvisit) as conversion_rate,
    sum(order_value) / count(distinct idvisit) as revenue_per_visit
FROM ab_testing_details
GROUP BY experiment, variant
ORDER BY experiment, variant;
```

### Customer Consideration Period Analysis

Understand how long customers take to make purchasing decisions:

```sql
SELECT 
    CASE 
        WHEN considerastion_days = 0 THEN 'Same day'
        WHEN considerastion_days <= 7 THEN '1-7 days'
        WHEN considerastion_days <= 14 THEN '8-14 days'
        WHEN considerastion_days <= 30 THEN '15-30 days'
        ELSE '30+ days'
    END as consideration_period,
    count(*) as customers
FROM matomo_converted_visitors
GROUP BY 
    CASE 
        WHEN considerastion_days = 0 THEN 'Same day'
        WHEN considerastion_days <= 7 THEN '1-7 days'
        WHEN considerastion_days <= 14 THEN '8-14 days'
        WHEN considerastion_days <= 30 THEN '15-30 days'
        ELSE '30+ days'
    END
ORDER BY customers DESC;
```

## Implementation Notes

### Database Schema Requirements

These queries assume the following Matomo database tables:
- `matomo_log_visit` - Visitor session data
- `matomo_log_conversion` - Conversion/goal tracking
- `matomo_log_action` - Page URLs and actions
- `matomo_log_link_visit_action` - Link between visits and actions
- `matomo_log_abtesting` - A/B test participation data
- `matomo_experiments` - A/B test configuration

### Customization Guidelines

1. **Domain References**: Replace `mydomain.com` and `myproductpage` with your actual domain and product page URLs
2. **Order Integration**: Adapt the order table joins to match your e-commerce platform
3. **Source Classification**: Modify the source classification logic to match your traffic sources
4. **Date Ranges**: Adjust date filters based on your data retention and analysis needs

### Performance Considerations

- Create indexes on frequently joined columns (`idvisit`, `idorder`, `server_time`)
- Consider materialized views for frequently accessed data
- Use appropriate date partitioning for large datasets
- Monitor query performance and optimize as needed

These examples provide a solid foundation for comprehensive e-commerce analytics with Matomo, enabling data-driven decisions about marketing attribution, user experience optimization, and conversion rate improvements.