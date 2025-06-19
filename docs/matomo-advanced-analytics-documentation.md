# Matomo Advanced Analytics SQL Queries Documentation

This document provides comprehensive documentation for advanced SQL queries designed to extract deep insights from Matomo analytics data. These queries have been tested and corrected to work with standard Matomo installations.

## Table of Contents

1. [Visitor Behavior & Segmentation](#1-visitor-behavior--segmentation)
2. [Advanced Cohort Analysis](#2-advanced-cohort-analysis)
3. [Content Performance Analytics](#3-content-performance-analytics)
4. [Real-time Analytics](#4-real-time-analytics)
5. [Custom Event & Goal Tracking](#5-custom-event--goal-tracking)
6. [Technical Performance](#6-technical-performance)
7. [Marketing Attribution Models](#7-marketing-attribution-models)
8. [Security & Fraud Detection](#8-security--fraud-detection)
9. [Usage Notes & Customization](#usage-notes--customization)

---

## 1. Visitor Behavior & Segmentation

### User Engagement Scoring

Calculates a comprehensive engagement score (0-100) for each visitor based on visit frequency, actions, time spent, and conversions.

**Key Metrics:**
- Visit count and frequency
- Average actions per visit
- Session duration
- Conversion events
- Days active on site

**Business Value:** Identify your most engaged users for targeted marketing campaigns and retention strategies.

```sql
WITH user_engagement AS (
    SELECT 
        hex(idvisitor) as visitor_id,
        COUNT(DISTINCT idvisit) as visit_count,
        AVG(visit_total_actions) as avg_actions_per_visit,
        AVG(visit_total_time) as avg_session_duration,
        SUM(visit_total_actions) as total_actions,
        MAX(visit_total_time) as longest_session,
        COUNT(CASE WHEN visit_goal_converted > 0 THEN 1 END) as conversion_visits,
        DATEDIFF(MAX(visit_first_action_time), MIN(visit_first_action_time)) as days_active
    FROM matomo_log_visit 
    WHERE visit_first_action_time >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
    GROUP BY idvisitor
)
SELECT 
    visitor_id,
    visit_count,
    avg_actions_per_visit,
    avg_session_duration,
    -- Engagement Score Calculation (0-100)
    LEAST(100, ROUND(
        (visit_count * 10) + 
        (avg_actions_per_visit * 5) + 
        (avg_session_duration / 60 * 2) + 
        (conversion_visits * 25) +
        (CASE WHEN days_active > 30 THEN 20 ELSE days_active * 0.67 END)
    )) as engagement_score,
    CASE 
        WHEN visit_count >= 10 AND avg_actions_per_visit >= 5 THEN 'High Engagement'
        WHEN visit_count >= 5 AND avg_actions_per_visit >= 3 THEN 'Medium Engagement'
        WHEN visit_count >= 2 AND avg_actions_per_visit >= 2 THEN 'Low Engagement'
        ELSE 'One-time Visitor'
    END as engagement_segment
FROM user_engagement
ORDER BY engagement_score DESC;
```

### Visitor Lifetime Value Analysis

Analyzes customer lifetime value (CLV) and segments visitors by revenue contribution.

**Key Metrics:**
- Total revenue per visitor
- Order frequency and value
- Customer lifespan
- Revenue per visit

**Business Value:** Identify high-value customers and optimize acquisition costs based on predicted CLV.

```sql
SELECT 
    hex(v.idvisitor) as visitor_id,
    MIN(v.visit_first_action_time) as first_visit,
    MAX(v.visit_last_action_time) as last_visit,
    COUNT(DISTINCT v.idvisit) as total_visits,
    SUM(v.visit_total_actions) as total_page_views,
    COUNT(DISTINCT c.idorder) as total_orders,
    COALESCE(SUM(c.revenue), 0) as total_revenue,
    COALESCE(AVG(c.revenue), 0) as avg_order_value,
    COALESCE(SUM(c.revenue) / COUNT(DISTINCT v.idvisit), 0) as revenue_per_visit,
    DATEDIFF(MAX(v.visit_last_action_time), MIN(v.visit_first_action_time)) + 1 as customer_lifespan_days,
    CASE 
        WHEN SUM(c.revenue) >= 1000 THEN 'High Value'
        WHEN SUM(c.revenue) >= 500 THEN 'Medium Value'
        WHEN SUM(c.revenue) >= 100 THEN 'Low Value'
        WHEN SUM(c.revenue) > 0 THEN 'Minimal Value'
        ELSE 'No Purchase'
    END as value_segment
FROM matomo_log_visit v
LEFT JOIN matomo_log_conversion c ON v.idvisit = c.idvisit
GROUP BY v.idvisitor
HAVING total_visits > 1
ORDER BY total_revenue DESC;
```

### Page Flow & Path Analysis

Tracks user navigation patterns to understand how visitors move through your site.

**Key Metrics:**
- Page-to-page transitions
- Time spent on each page
- Most common user paths

**Business Value:** Optimize site navigation and identify content gaps in user journeys.

```sql
WITH page_flows AS (
    SELECT 
        l1.idvisit,
        a1.name as entry_page,
        a2.name as next_page,
        l1.time_spent_ref_action,
        ROW_NUMBER() OVER (PARTITION BY l1.idvisit ORDER BY l1.server_time) as step_number
    FROM matomo_log_link_visit_action l1
    JOIN matomo_log_action a1 ON l1.idaction_url_ref = a1.idaction
    LEFT JOIN matomo_log_link_visit_action l2 ON l1.idvisit = l2.idvisit 
        AND l2.server_time > l1.server_time
    LEFT JOIN matomo_log_action a2 ON l2.idaction_url = a2.idaction
    WHERE a1.type = 1 AND (a2.type = 1 OR a2.type IS NULL)
)
SELECT 
    SUBSTRING_INDEX(entry_page, '?', 1) as from_page,
    SUBSTRING_INDEX(next_page, '?', 1) as to_page,
    COUNT(*) as flow_count,
    AVG(time_spent_ref_action) as avg_time_on_page,
    COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () as flow_percentage
FROM page_flows
WHERE entry_page IS NOT NULL
GROUP BY from_page, to_page
HAVING flow_count >= 10
ORDER BY flow_count DESC
LIMIT 50;
```

---

## 2. Advanced Cohort Analysis

### Monthly Retention Cohorts

Tracks visitor retention rates by acquisition month to understand long-term engagement patterns.

**Key Metrics:**
- Cohort size by acquisition month
- Retention rates at 1, 3, 6, and 12 months
- Month-over-month retention comparison

**Business Value:** Measure product-market fit and the effectiveness of onboarding processes.

```sql
WITH monthly_cohorts AS (
    SELECT 
        hex(idvisitor) as visitor_id,
        DATE_FORMAT(MIN(visit_first_action_time), '%Y-%m') as cohort_month,
        MIN(visit_first_action_time) as first_visit_date
    FROM matomo_log_visit
    GROUP BY idvisitor
),
cohort_activity AS (
    SELECT 
        mc.visitor_id,
        mc.cohort_month,
        mc.first_visit_date,
        v.visit_first_action_time,
        PERIOD_DIFF(
            DATE_FORMAT(v.visit_first_action_time, '%Y%m'),
            DATE_FORMAT(mc.first_visit_date, '%Y%m')
        ) as period_number
    FROM monthly_cohorts mc
    JOIN matomo_log_visit v ON hex(v.idvisitor) = mc.visitor_id
)
SELECT 
    cohort_month,
    COUNT(DISTINCT CASE WHEN period_number = 0 THEN visitor_id END) as cohort_size,
    COUNT(DISTINCT CASE WHEN period_number = 1 THEN visitor_id END) as month_1,
    COUNT(DISTINCT CASE WHEN period_number = 2 THEN visitor_id END) as month_2,
    COUNT(DISTINCT CASE WHEN period_number = 3 THEN visitor_id END) as month_3,
    COUNT(DISTINCT CASE WHEN period_number = 6 THEN visitor_id END) as month_6,
    COUNT(DISTINCT CASE WHEN period_number = 12 THEN visitor_id END) as month_12,
    -- Retention Rates
    ROUND(COUNT(DISTINCT CASE WHEN period_number = 1 THEN visitor_id END) * 100.0 / 
          COUNT(DISTINCT CASE WHEN period_number = 0 THEN visitor_id END), 2) as retention_month_1,
    ROUND(COUNT(DISTINCT CASE WHEN period_number = 3 THEN visitor_id END) * 100.0 / 
          COUNT(DISTINCT CASE WHEN period_number = 0 THEN visitor_id END), 2) as retention_month_3
FROM cohort_activity
GROUP BY cohort_month
ORDER BY cohort_month;
```

### Revenue Cohort Analysis

Analyzes revenue patterns and conversion rates by customer acquisition cohorts.

**Key Metrics:**
- Conversion rates by cohort
- Revenue per user (RPU) and revenue per buyer
- Total cohort revenue contribution

**Business Value:** Understand the revenue impact of different acquisition periods and optimize marketing spend timing.

```sql
WITH revenue_cohorts AS (
    SELECT 
        hex(v.idvisitor) as visitor_id,
        DATE_FORMAT(MIN(v.visit_first_action_time), '%Y-%m') as acquisition_month,
        MIN(v.visit_first_action_time) as first_visit_date,
        COUNT(DISTINCT c.idorder) as total_orders,
        COALESCE(SUM(c.revenue), 0) as total_revenue
    FROM matomo_log_visit v
    LEFT JOIN matomo_log_conversion c ON v.idvisit = c.idvisit
    GROUP BY v.idvisitor
)
SELECT 
    acquisition_month,
    COUNT(DISTINCT visitor_id) as cohort_size,
    COUNT(DISTINCT CASE WHEN total_orders > 0 THEN visitor_id END) as buyers,
    ROUND(COUNT(DISTINCT CASE WHEN total_orders > 0 THEN visitor_id END) * 100.0 / 
          COUNT(DISTINCT visitor_id), 2) as conversion_rate,
    ROUND(AVG(total_revenue), 2) as avg_revenue_per_user,
    ROUND(AVG(CASE WHEN total_orders > 0 THEN total_revenue END), 2) as avg_revenue_per_buyer,
    SUM(total_revenue) as cohort_total_revenue
FROM revenue_cohorts
WHERE acquisition_month >= DATE_FORMAT(DATE_SUB(CURDATE(), INTERVAL 24 MONTH), '%Y-%m')
GROUP BY acquisition_month
ORDER BY acquisition_month;
```

---

## 3. Content Performance Analytics

### Page Performance Metrics

Comprehensive page-level analytics including engagement metrics and conversion tracking.

**Key Metrics:**
- Unique visitors and pageviews
- Bounce and exit rates
- Time on page and engagement rates
- Page value scoring

**Business Value:** Identify top-performing content and pages that need optimization.

```sql
WITH page_metrics AS (
    SELECT 
        SUBSTRING_INDEX(a.name, '?', 1) as page_url,
        COUNT(DISTINCT l.idvisit) as unique_visitors,
        COUNT(*) as total_pageviews,
        AVG(l.time_spent_ref_action) as avg_time_on_page,
        COUNT(CASE WHEN l.time_spent_ref_action > 0 THEN 1 END) as engaged_pageviews,
        -- Bounce rate calculation (single page sessions)
        COUNT(DISTINCT CASE WHEN v.visit_total_actions = 1 THEN l.idvisit END) as bounces,
        -- Exit rate calculation
        COUNT(CASE WHEN l.idaction_url_ref = 0 OR l.idaction_url_ref IS NULL THEN 1 END) as exits
    FROM matomo_log_link_visit_action l
    JOIN matomo_log_action a ON l.idaction_url = a.idaction
    JOIN matomo_log_visit v ON l.idvisit = v.idvisit
    WHERE a.type = 1 -- Page URLs only
    AND l.server_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    GROUP BY SUBSTRING_INDEX(a.name, '?', 1)
    HAVING total_pageviews >= 50
)
SELECT 
    page_url,
    unique_visitors,
    total_pageviews,
    ROUND(total_pageviews / unique_visitors, 2) as pageviews_per_visitor,
    ROUND(avg_time_on_page, 0) as avg_time_seconds,
    ROUND(engaged_pageviews * 100.0 / total_pageviews, 2) as engagement_rate,
    ROUND(bounces * 100.0 / unique_visitors, 2) as bounce_rate,
    ROUND(exits * 100.0 / total_pageviews, 2) as exit_rate,
    -- Page value score
    ROUND((avg_time_on_page * 0.1) + (engaged_pageviews * 100.0 / total_pageviews), 2) as page_value_score
FROM page_metrics
ORDER BY page_value_score DESC;
```

### Internal Search Analysis

Analyzes site search behavior and performance using Matomo's site search tracking.

**Key Metrics:**
- Search term frequency
- Post-search user behavior
- Search-to-conversion rates
- Click-through rates from search results

**Business Value:** Understand what users are looking for and optimize search functionality and content strategy.

```sql
SELECT 
    la.name as search_term,
    COUNT(*) as search_count,
    COUNT(DISTINCT l.idvisit) as unique_searchers,
    COUNT(DISTINCT v.idvisitor) as unique_visitors,
    AVG(v.visit_total_actions) as avg_actions_after_search,
    AVG(v.visit_total_time) as avg_session_duration,
    -- Post-search behavior
    COUNT(CASE WHEN v.visit_total_actions > 1 THEN 1 END) as searches_with_next_action,
    ROUND(COUNT(CASE WHEN v.visit_total_actions > 1 THEN 1 END) * 100.0 / COUNT(*), 2) as click_through_rate,
    -- Search to conversion
    COUNT(DISTINCT CASE WHEN c.idorder IS NOT NULL THEN l.idvisit END) as converting_search_sessions,
    ROUND(COUNT(DISTINCT CASE WHEN c.idorder IS NOT NULL THEN l.idvisit END) * 100.0 / 
          COUNT(DISTINCT l.idvisit), 2) as search_conversion_rate
FROM matomo_log_link_visit_action l
JOIN matomo_log_action la ON l.idaction_name = la.idaction
JOIN matomo_log_visit v ON l.idvisit = v.idvisit
LEFT JOIN matomo_log_conversion c ON l.idvisit = c.idvisit 
    AND c.server_time >= l.server_time
WHERE l.idaction_name IS NOT NULL 
AND la.type = 8 -- Site search actions
AND l.server_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY la.name
HAVING search_count >= 5
ORDER BY search_count DESC;
```

---

## 4. Real-time Analytics

### Live Visitor Tracking

Shows current active sessions with detailed visitor information.

**Key Metrics:**
- Active sessions in last 30 minutes
- Visitor location and technology details
- Current page and session activity
- Traffic source information

**Business Value:** Monitor real-time user activity for immediate insights and customer support.

```sql
SELECT 
    hex(v.idvisitor) as visitor_id,
    v.idvisit,
    v.visit_first_action_time as session_start,
    v.visit_last_action_time as last_activity,
    TIMESTAMPDIFF(MINUTE, v.visit_last_action_time, NOW()) as minutes_since_last_action,
    v.visit_total_actions as actions_in_session,
    v.location_country as country,
    v.location_city as city,
    v.config_browser_name as browser,
    v.config_os as operating_system,
    v.referer_name as traffic_source,
    -- Current page (last action)
    SUBSTRING_INDEX(la.name, '?', 1) as current_page
FROM matomo_log_visit v
LEFT JOIN matomo_log_link_visit_action lva ON v.idvisit = lva.idvisit 
    AND lva.server_time = v.visit_last_action_time
LEFT JOIN matomo_log_action la ON lva.idaction_url = la.idaction
WHERE v.visit_last_action_time >= DATE_SUB(NOW(), INTERVAL 30 MINUTE)
AND TIMESTAMPDIFF(MINUTE, v.visit_last_action_time, NOW()) <= 30
ORDER BY v.visit_last_action_time DESC;
```

### Real-time Conversion Monitoring

Tracks recent conversions and their details for immediate revenue insights.

**Key Metrics:**
- Recent conversions (last 2 hours)
- Order values and goal completions
- Time to conversion from session start
- Traffic source attribution

**Business Value:** Monitor conversion performance in real-time and identify successful traffic sources.

```sql
SELECT 
    c.server_time as conversion_time,
    TIMESTAMPDIFF(MINUTE, c.server_time, NOW()) as minutes_ago,
    hex(c.idvisitor) as visitor_id,
    c.idorder as order_id,
    c.revenue as order_value,
    v.referer_name as traffic_source,
    v.location_country as country,
    g.name as goal_name,
    g.description as goal_description,
    c.idgoal,
    -- Time from session start to conversion
    TIMESTAMPDIFF(MINUTE, v.visit_first_action_time, c.server_time) as session_duration_to_conversion
FROM matomo_log_conversion c
JOIN matomo_log_visit v ON c.idvisit = v.idvisit
LEFT JOIN matomo_goal g ON c.idgoal = g.idgoal AND c.idsite = g.idsite
WHERE c.server_time >= DATE_SUB(NOW(), INTERVAL 2 HOUR)
ORDER BY c.server_time DESC;
```

---

## 5. Custom Event & Goal Tracking

### Form Completion Analysis

Tracks form interaction and completion rates using Matomo's event tracking.

**Key Metrics:**
- Form start and completion rates
- Average fields completed before submission
- Form abandonment patterns

**Business Value:** Optimize form design and reduce abandonment rates to improve conversion.

```sql
WITH form_events AS (
    SELECT 
        l.idvisit,
        la_category.name as event_category,
        la_action.name as event_action,
        COALESCE(la_name.name, 'Unknown Form') as form_name,
        l.server_time,
        ROW_NUMBER() OVER (PARTITION BY l.idvisit, COALESCE(la_name.name, 'Unknown Form') ORDER BY l.server_time) as event_sequence
    FROM matomo_log_link_visit_action l
    JOIN matomo_log_action la_category ON l.idaction_event_category = la_category.idaction
    JOIN matomo_log_action la_action ON l.idaction_event_action = la_action.idaction
    LEFT JOIN matomo_log_action la_name ON l.idaction_name = la_name.idaction
    WHERE la_category.name = 'Form'
    AND l.server_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
    AND l.idaction_event_category IS NOT NULL
)
SELECT 
    form_name,
    COUNT(DISTINCT CASE WHEN event_action = 'start' THEN idvisit END) as form_starts,
    COUNT(DISTINCT CASE WHEN event_action = 'submit' THEN idvisit END) as form_completions,
    ROUND(COUNT(DISTINCT CASE WHEN event_action = 'submit' THEN idvisit END) * 100.0 / 
          NULLIF(COUNT(DISTINCT CASE WHEN event_action = 'start' THEN idvisit END), 0), 2) as completion_rate,
    AVG(CASE WHEN event_action = 'submit' THEN event_sequence END) as avg_fields_to_completion
FROM form_events
WHERE form_name IS NOT NULL
GROUP BY form_name
HAVING form_starts >= 10
ORDER BY completion_rate DESC;
```

### Video/Media Engagement Analysis

Tracks video interaction and engagement patterns using event tracking.

**Key Metrics:**
- Play, pause, seek, and completion events
- Video completion rates
- User interaction patterns
- Watch time percentages

**Business Value:** Optimize video content strategy and improve engagement rates.

```sql
SELECT 
    COALESCE(la_name.name, 'Unknown Video') as video_title,
    COUNT(DISTINCT l.idvisit) as unique_viewers,
    COUNT(CASE WHEN la_action.name = 'play' THEN 1 END) as play_events,
    COUNT(CASE WHEN la_action.name = 'pause' THEN 1 END) as pause_events,
    COUNT(CASE WHEN la_action.name = 'complete' THEN 1 END) as completion_events,
    COUNT(CASE WHEN la_action.name = 'seek' THEN 1 END) as seek_events,
    -- Use event value for watch percentage if available
    AVG(CASE WHEN l.custom_float IS NOT NULL THEN l.custom_float ELSE NULL END) as avg_watch_percentage,
    ROUND(COUNT(CASE WHEN la_action.name = 'complete' THEN 1 END) * 100.0 / 
          NULLIF(COUNT(CASE WHEN la_action.name = 'play' THEN 1 END), 0), 2) as completion_rate,
    -- Calculate engagement score based on available interactions
    ROUND((COUNT(CASE WHEN la_action.name = 'pause' THEN 1 END) + 
           COUNT(CASE WHEN la_action.name = 'seek' THEN 1 END)) * 100.0 / 
          NULLIF(COUNT(CASE WHEN la_action.name = 'play' THEN 1 END), 0), 2) as interaction_rate
FROM matomo_log_link_visit_action l
JOIN matomo_log_action la_category ON l.idaction_event_category = la_category.idaction
JOIN matomo_log_action la_action ON l.idaction_event_action = la_action.idaction
LEFT JOIN matomo_log_action la_name ON l.idaction_name = la_name.idaction
WHERE la_category.name = 'Video'
AND l.server_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
AND l.idaction_event_category IS NOT NULL
GROUP BY COALESCE(la_name.name, 'Unknown Video')
HAVING unique_viewers >= 5
ORDER BY unique_viewers DESC;
```

---

## 6. Technical Performance

### Page Load Time Analysis

Analyzes page performance based on custom timing events with MySQL-compatible percentile calculations.

**Key Metrics:**
- Average, median, and 95th percentile load times
- Performance distribution and outliers
- Performance grading system
- Load time standard deviation

**Business Value:** Identify performance bottlenecks and optimize user experience.

```sql
WITH page_performance AS (
    SELECT 
        SUBSTRING_INDEX(la_page.name, '?', 1) as page_url,
        CASE 
            WHEN l.custom_float IS NOT NULL THEN CAST(l.custom_float AS UNSIGNED)
            ELSE NULL
        END as load_time_ms,
        DATE(l.server_time) as date
    FROM matomo_log_link_visit_action l
    JOIN matomo_log_action la_category ON l.idaction_event_category = la_category.idaction
    JOIN matomo_log_action la_page ON l.idaction_url = la_page.idaction
    WHERE la_category.name = 'Performance'
    AND l.custom_float IS NOT NULL
    AND CAST(l.custom_float AS UNSIGNED) > 0
    AND CAST(l.custom_float AS UNSIGNED) < 30000 -- Filter outliers > 30 seconds
    AND l.server_time >= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
),
percentile_calc AS (
    SELECT 
        page_url,
        load_time_ms,
        COUNT(*) OVER (PARTITION BY page_url) as total_count,
        ROW_NUMBER() OVER (PARTITION BY page_url ORDER BY load_time_ms) as row_num
    FROM page_performance
    WHERE load_time_ms IS NOT NULL
)
SELECT 
    pp.page_url,
    COUNT(*) as measurement_count,
    ROUND(AVG(pp.load_time_ms), 0) as avg_load_time_ms,
    ROUND(STDDEV(pp.load_time_ms), 0) as load_time_stddev,
    MIN(pp.load_time_ms) as min_load_time,
    MAX(pp.load_time_ms) as max_load_time,
    -- Performance percentiles using MySQL-compatible approach
    ROUND(AVG(CASE WHEN pc50.row_num BETWEEN FLOOR(pc50.total_count * 0.5) AND CEIL(pc50.total_count * 0.5) THEN pc50.load_time_ms END), 0) as median_load_time,
    ROUND(AVG(CASE WHEN pc95.row_num BETWEEN FLOOR(pc95.total_count * 0.95) AND CEIL(pc95.total_count * 0.95) THEN pc95.load_time_ms END), 0) as p95_load_time,
    -- Performance grade
    CASE 
        WHEN AVG(pp.load_time_ms) <= 1000 THEN 'Excellent'
        WHEN AVG(pp.load_time_ms) <= 2500 THEN 'Good'
        WHEN AVG(pp.load_time_ms) <= 4000 THEN 'Needs Improvement'
        ELSE 'Poor'
    END as performance_grade
FROM page_performance pp
LEFT JOIN percentile_calc pc50 ON pp.page_url = pc50.page_url
LEFT JOIN percentile_calc pc95 ON pp.page_url = pc95.page_url
WHERE pp.load_time_ms IS NOT NULL
GROUP BY pp.page_url
HAVING measurement_count >= 10
ORDER BY avg_load_time_ms;
```

### Bot vs Human Traffic Detection

Identifies and filters bot traffic patterns to ensure accurate analytics.

**Key Metrics:**
- Suspected bot vs human visit classification
- Bot detection based on browser patterns and behavior
- Daily bot traffic percentage trends

**Business Value:** Filter out bot traffic for more accurate user behavior analysis and conversion metrics.

```sql
SELECT 
    DATE(visit_first_action_time) as date,
    COUNT(*) as total_visits,
    COUNT(CASE WHEN 
        (config_browser_name LIKE '%bot%' OR 
         config_browser_name LIKE '%crawler%' OR 
         config_browser_name LIKE '%spider%' OR
         config_browser_name = 'Unknown' OR
         visit_total_actions = 1 AND visit_total_time < 5) 
        THEN 1 END) as suspected_bot_visits,
    COUNT(CASE WHEN 
        config_browser_name NOT LIKE '%bot%' AND 
        config_browser_name NOT LIKE '%crawler%' AND 
        config_browser_name NOT LIKE '%spider%' AND
        config_browser_name != 'Unknown' AND
        NOT (visit_total_actions = 1 AND visit_total_time < 5)
        THEN 1 END) as human_visits,
    ROUND(COUNT(CASE WHEN 
        (config_browser_name LIKE '%bot%' OR 
         config_browser_name LIKE '%crawler%' OR 
         config_browser_name LIKE '%spider%' OR
         config_browser_name = 'Unknown' OR
         visit_total_actions = 1 AND visit_total_time < 5) 
        THEN 1 END) * 100.0 / COUNT(*), 2) as bot_percentage
FROM matomo_log_visit
WHERE visit_first_action_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY DATE(visit_first_action_time)
ORDER BY date DESC;
```

---

## 7. Marketing Attribution Models

### Multi-touch Attribution Analysis

Assigns credit across multiple touchpoints in the customer journey using various attribution models.

**Key Metrics:**
- First-touch, last-touch, linear, and time-decay attribution
- Channel and source performance comparison
- Average touch position for conversions

**Business Value:** Understand the true impact of different marketing channels and optimize budget allocation.

```sql
WITH customer_journey AS (
    SELECT 
        hex(v.idvisitor) as visitor_id,
        v.idvisit,
        v.visit_first_action_time,
        v.referer_name as source,
        CASE 
            WHEN v.referer_type = 1 THEN 'direct'
            WHEN v.referer_type = 2 THEN 'search'
            WHEN v.referer_type = 3 THEN 'website'
            WHEN v.referer_type = 6 THEN 'campaign'
            ELSE 'other'
        END as channel,
        c.idorder,
        COALESCE(c.revenue, 0) as revenue,
        ROW_NUMBER() OVER (PARTITION BY v.idvisitor ORDER BY v.visit_first_action_time) as touch_sequence,
        COUNT(*) OVER (PARTITION BY v.idvisitor) as total_touches,
        CASE WHEN c.idorder IS NOT NULL THEN 1 ELSE 0 END as is_conversion_visit
    FROM matomo_log_visit v
    LEFT JOIN matomo_log_conversion c ON v.idvisit = c.idvisit
    WHERE v.visit_first_action_time >= DATE_SUB(CURDATE(), INTERVAL 90 DAY)
),
attribution_weights AS (
    SELECT 
        visitor_id,
        idvisit,
        source,
        channel,
        touch_sequence,
        total_touches,
        revenue,
        is_conversion_visit,
        -- First Touch Attribution
        CASE WHEN touch_sequence = 1 AND is_conversion_visit = 1 THEN revenue ELSE 0 END as first_touch_revenue,
        -- Last Touch Attribution  
        CASE WHEN touch_sequence = total_touches AND is_conversion_visit = 1 THEN revenue ELSE 0 END as last_touch_revenue,
        -- Linear Attribution
        CASE WHEN is_conversion_visit = 1 THEN revenue / total_touches ELSE 0 END as linear_revenue,
        -- Time Decay Attribution (fixed to avoid negative exponents)
        CASE WHEN is_conversion_visit = 1 THEN 
            revenue * POWER(0.5, CAST(total_touches - touch_sequence AS SIGNED))
        ELSE 0 END as time_decay_revenue
    FROM customer_journey cj
    WHERE EXISTS (SELECT 1 FROM customer_journey cj2 WHERE cj2.visitor_id = cj.visitor_id AND cj2.is_conversion_visit = 1)
)
SELECT 
    channel,
    source,
    COUNT(DISTINCT visitor_id) as influenced_customers,
    COUNT(*) as total_touchpoints,
    ROUND(SUM(first_touch_revenue), 2) as first_touch_attribution,
    ROUND(SUM(last_touch_revenue), 2) as last_touch_attribution,
    ROUND(SUM(linear_revenue), 2) as linear_attribution,
    ROUND(SUM(time_decay_revenue), 2) as time_decay_attribution,
    ROUND(AVG(CASE WHEN revenue > 0 THEN touch_sequence END), 1) as avg_conversion_touch_position
FROM attribution_weights
GROUP BY channel, source
HAVING total_touchpoints >= 10
ORDER BY linear_attribution DESC;
```

---

## 8. Security & Fraud Detection

### Suspicious Activity Detection

Identifies potentially fraudulent or suspicious visitor patterns using behavioral analysis.

**Key Metrics:**
- Rapid clicking patterns
- Impossible geographic changes
- Browser and OS variations
- Suspicion scoring (0-100)

**Business Value:** Protect against click fraud and identify suspicious user behavior for security purposes.

```sql
WITH visitor_sessions AS (
    SELECT 
        hex(idvisitor) as visitor_id,
        location_ip as ip_address,
        visit_first_action_time,
        location_country,
        visit_total_actions,
        visit_total_time,
        config_browser_name,
        config_os,
        LAG(location_country) OVER (PARTITION BY idvisitor ORDER BY visit_first_action_time) as prev_country,
        LAG(visit_first_action_time) OVER (PARTITION BY idvisitor ORDER BY visit_first_action_time) as prev_visit_time
    FROM matomo_log_visit
    WHERE visit_first_action_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
),
suspicious_patterns AS (
    SELECT 
        visitor_id,
        ip_address,
        COUNT(DISTINCT visit_first_action_time) as visit_count,
        COUNT(DISTINCT DATE(visit_first_action_time)) as days_active,
        AVG(visit_total_actions) as avg_actions_per_visit,
        AVG(visit_total_time) as avg_session_duration,
        COUNT(DISTINCT config_browser_name) as browser_variations,
        COUNT(DISTINCT config_os) as os_variations,
        COUNT(DISTINCT location_country) as country_variations,
        MAX(visit_total_actions) as max_actions_in_session,
        -- Rapid clicking pattern
        COUNT(CASE WHEN visit_total_actions > 50 AND visit_total_time < 60 THEN 1 END) as rapid_clicking_sessions,
        -- Impossible geographic patterns
        COUNT(CASE WHEN location_country != prev_country 
              AND prev_country IS NOT NULL
              AND TIMESTAMPDIFF(HOUR, prev_visit_time, visit_first_action_time) < 1 
              THEN 1 END) as impossible_geo_changes
    FROM visitor_sessions
    GROUP BY visitor_id, ip_address
)
SELECT 
    visitor_id,
    ip_address,
    visit_count,
    days_active,
    ROUND(avg_actions_per_visit, 2) as avg_actions_per_visit,
    ROUND(avg_session_duration, 2) as avg_session_duration,
    browser_variations,
    country_variations,
    rapid_clicking_sessions,
    impossible_geo_changes,
    -- Suspicion Score (0-100)
    LEAST(100, ROUND(
        (CASE WHEN avg_actions_per_visit > 100 THEN 25 ELSE 0 END) +
        (CASE WHEN avg_session_duration < 5 AND avg_actions_per_visit > 10 THEN 20 ELSE 0 END) +
        (browser_variations * 5) +
        (country_variations * 10) +
        (rapid_clicking_sessions * 15) +
        (impossible_geo_changes * 20)
    )) as suspicion_score,
    CASE 
        WHEN rapid_clicking_sessions > 0 OR impossible_geo_changes > 0 THEN 'High Risk'
        WHEN browser_variations > 3 OR country_variations > 2 THEN 'Medium Risk'
        WHEN avg_actions_per_visit > 50 AND avg_session_duration < 10 THEN 'Low Risk'
        ELSE 'Normal'
    END as risk_level
FROM suspicious_patterns
WHERE visit_count >= 3
AND (rapid_clicking_sessions > 0 OR impossible_geo_changes > 0 OR browser_variations > 2 OR 
     (avg_actions_per_visit > 50 AND avg_session_duration < 10))
ORDER BY suspicion_score DESC;
```

### Referrer Spam Filtering

Identifies and filters referrer spam patterns to maintain data quality.

**Key Metrics:**
- Single-action, zero-time visits
- Unique IPs vs unique visitors ratio
- Spam classification based on behavior patterns

**Business Value:** Maintain data quality by identifying and filtering out referrer spam traffic.

```sql
SELECT 
    referer_name,
    referer_url,
    COUNT(*) as visit_count,
    COUNT(DISTINCT location_ip) as unique_ips,
    COUNT(DISTINCT hex(idvisitor)) as unique_visitors,
    AVG(visit_total_actions) as avg_actions,
    AVG(visit_total_time) as avg_duration,
    COUNT(CASE WHEN visit_total_actions = 1 AND visit_total_time = 0 THEN 1 END) as single_action_zero_time,
    ROUND(COUNT(CASE WHEN visit_total_actions = 1 AND visit_total_time = 0 THEN 1 END) * 100.0 / COUNT(*), 2) as spam_indicator_percentage,
    CASE 
        WHEN COUNT(CASE WHEN visit_total_actions = 1 AND visit_total_time = 0 THEN 1 END) * 100.0 / COUNT(*) > 80 THEN 'Likely Spam'
        WHEN COUNT(CASE WHEN visit_total_actions = 1 AND visit_total_time = 0 THEN 1 END) * 100.0 / COUNT(*) > 50 THEN 'Possible Spam'
        ELSE 'Legitimate'
    END as spam_classification
FROM matomo_log_visit
WHERE referer_name IS NOT NULL
AND visit_first_action_time >= DATE_SUB(CURDATE(), INTERVAL 30 DAY)
GROUP BY referer_name, referer_url
HAVING visit_count >= 10
ORDER BY spam_indicator_percentage DESC, visit_count DESC;
```

---

## Usage Notes & Customization

### Before Using These Queries

1. **Table Prefixes**: Replace `matomo_` prefixes if your installation uses different naming
2. **Date Ranges**: Adjust date ranges based on your data volume and retention policy
3. **Performance Testing**: Test queries on subsets first to check performance
4. **Column Verification**: Verify column names match your Matomo version
5. **Indexing**: Add appropriate indexes for better performance on large datasets
6. **Limits**: Consider using LIMIT clauses for initial testing

### Recommended Indexes

```sql
-- Performance optimization indexes
CREATE INDEX idx_visit_visitor_time ON matomo_log_visit(idvisitor, visit_first_action_time);
CREATE INDEX idx_action_visit_time ON matomo_log_link_visit_action(idvisit, server_time);
CREATE INDEX idx_conversion_visit_time ON matomo_log_conversion(idvisit, server_time);
CREATE INDEX idx_action_type_name ON matomo_log_action(type, name);
```

### Customization Tips

1. **Engagement Scoring**: Modify weights based on your business model
2. **Suspicious Activity**: Adjust thresholds based on your typical traffic patterns
3. **Attribution Models**: Customize based on your marketing channels and sales cycle
4. **Event Categories**: Add business-specific event categories and goals
5. **Performance Grades**: Adjust load time thresholds based on your performance goals

### Data Requirements

- **Event Tracking**: Video and form analysis requires proper event tracking implementation
- **Site Search**: Search analysis requires site search tracking to be enabled
- **E-commerce**: Revenue analysis requires e-commerce tracking setup
- **Goals**: Goal-related queries require goal configuration in Matomo
- **Custom Variables**: Some queries use custom variables that may need implementation

### Security Considerations

- These queries are read-only and safe for production use
- Always test in a development environment first
- Consider query execution time on large datasets
- Use appropriate user permissions for database access
- Monitor database performance when running complex queries

---

*This documentation covers advanced SQL queries for Matomo analytics. Always test thoroughly before using in production environments and customize based on your specific business needs and data structure.*