---
name: efficiency-review
description: Analyze a page or route for load performance — trace every API call on mount, flag unbounded or client-side-filtered queries, detect O(n^2) JSONB-join anti-patterns in the backend, and propose measured optimizations with test requirements. Use when a page feels slow or before shipping a data-heavy screen.
---

# Efficiency Review Skill

Analyze page load performance, identify unnecessary data fetching, and propose optimizations.

## Usage

```
/efficiency-review [page-path]
```

Example: `/efficiency-review /admin/users?section=tenants`

## Process

### 1. Identify the Page/Component

- Determine the route and component being analyzed
- Find the main component file and related hooks/context
- List all child components that may make API calls

### 2. Trace All API Calls on Load

Map out every API call made during page load:

| # | API Call | Trigger | Timing | Data Used? |
|---|----------|---------|--------|------------|
| 1 | Endpoint | mount/effect/callback | sequential/parallel | yes/no |

Consider:
- Mount effects (`useEffect(() => {...}, [])`)
- Section/route-based effects
- Dependent effects that chain requests
- Context providers that fetch data

### 3. For Each Call, Determine

- **Endpoint**: The API URL being called
- **Timing**: How long this typically takes (measure if possible)
- **Sequential?**: Is this blocking other calls?
- **Data displayed?**: Is the fetched data actually rendered on the page?
- **Cacheable?**: Could this be cached to avoid repeat fetches?

### 4. Query Specificity Review (CRITICAL)

**All queries must be specific and intentional. Never fetch entire tables.**

For each API call, verify:

| Check | Pass/Fail | Notes |
|-------|-----------|-------|
| Has WHERE clause or filter params | | |
| Returns bounded result set | | |
| Pagination implemented (if list) | | |
| Only fetches needed fields | | |

#### Red Flags to Catch

```typescript
// ❌ BAD: Fetches everything to find one item
const response = await api.get('/base_entities/', {
    params: { show_system_types: true, show_user_types: true }
});
const item = response.data.find(e => e.data?.name === 'Target');

// ✅ GOOD: Direct lookup by name
const response = await api.get('/base_entities/entity-type-id/Target');
```

```typescript
// ❌ BAD: No filters, returns all records
const users = await api.get('/users');

// ✅ GOOD: Filtered and paginated
const users = await api.get('/users', {
    params: { tenant_id: currentTenant, limit: 50, offset: 0 }
});
```

```typescript
// ❌ BAD: Fetch all, then filter client-side
const allProjects = await getProjects();
const activeProjects = allProjects.filter(p => p.status === 'active');

// ✅ GOOD: Server-side filtering
const activeProjects = await getProjects({ status: 'active' });
```

#### Query Audit Checklist

For each endpoint call found, answer:

1. **What is being fetched?** (table/entity type)
2. **How many records could this return?** (1, bounded list, unbounded)
3. **Are there filter parameters?** (type_fk, tenant_fk, status, etc.)
4. **Is there pagination?** (limit/offset or cursor)
5. **Could this grow unbounded over time?**

Flag any query that:
- Returns all entities of a type without filters
- Uses client-side filtering on large datasets
- Has no pagination on list endpoints
- Fetches full objects when only IDs are needed

### 5. Backend Database Query Anti-Patterns

**When reviewing backend code, check for these critical performance issues:**

#### JSONB JOIN Performance Issue (CRITICAL - O(n²) COMPLEXITY)

**This is the #1 performance killer in EAV/single-table architectures.**

The pattern `JOIN ... ON entity_id::text = data->>'foreign_key'` causes PostgreSQL to:
1. Cast every `entity_id` to text (prevents index usage)
2. Extract JSONB field for every row (no index unless specifically created)
3. Perform nested loop join = O(n²) comparisons

**Detection**: Search for this regex pattern:
```bash
grep -rn "JOIN.*entity_id::text.*data->>'|JOIN.*data->>'.*entity_id::text" src/
```

**Examples of the anti-pattern:**
```sql
-- ❌ BAD: All of these cause full table scans
JOIN entities t ON t.entity_id::text = e.data->>'type_fk'
JOIN entities p ON p.entity_id::text = li.data->>'product_fk'
LEFT JOIN entities sub_set ON sub_set.entity_id::text = plan.data->>'subscription_set_fk'
```

**Why it's slow:**
- 10,000 entities = ~100 million comparisons
- 100,000 entities = ~10 billion comparisons
- Query time grows quadratically with data

#### Multi-Nested JSONB JOINs (CATASTROPHIC - O(n^4) or worse)

**This is the absolute worst pattern. Flag immediately.**

When queries chain multiple JSONB JOINs together, the complexity multiplies:

```sql
-- ❌ CATASTROPHIC: Triple nested JOIN = O(n^4) complexity
SELECT owner_tenant.data->>'name'
FROM entities sub
JOIN entities plan ON plan.entity_id::text = sub.data->>'plan_fk'           -- O(n²)
JOIN entities sub_set ON sub_set.entity_id::text = plan.data->>'subscription_set_fk'  -- O(n²)
JOIN entities owner_tenant ON owner_tenant.entity_id::text = sub_set.data->>'tenant_fk'  -- O(n²)
WHERE sub.entity_id::text = ANY(:sub_ids)

-- ❌ VERY BAD: Quadruple nested JOIN = O(n^5) complexity
SELECT ...
FROM entities m
LEFT JOIN entities p ON p.entity_id::text = m.data->>'plan_fk'
LEFT JOIN entities prod ON prod.entity_id::text = m.data->>'product_fk'
LEFT JOIN entities sub_set ON sub_set.entity_id::text = p.data->>'subscription_set_fk'
LEFT JOIN entities t ON t.entity_id::text = m.data->>'tenant_fk'
```

**Impact of nested JOINs:**
| Nesting Depth | Complexity | 10k entities | 100k entities |
|---------------|------------|--------------|---------------|
| 1 JOIN | O(n²) | 100M ops | 10B ops |
| 2 JOINs | O(n³) | 1T ops | 1000T ops |
| 3 JOINs | O(n⁴) | 10000T ops | timeout |

**Detection**: Look for queries with 2+ JOINs on JSONB fields:
```bash
grep -rn "JOIN.*entity_id::text.*data->>" src/ | while read line; do
  file=$(echo "$line" | cut -d: -f1)
  linenum=$(echo "$line" | cut -d: -f2)
  # Check for multiple JOINs in nearby lines
  sed -n "$((linenum-5)),$((linenum+10))p" "$file" | grep -c "JOIN.*entity_id::text" | \
    xargs -I{} test {} -gt 1 && echo "MULTI-NESTED: $line"
done
```

**✅ GOOD: Multi-step batch lookups with helper functions:**
```python
# Use helper functions from admin_invoices.py:
# - lookup_operator_tenants_via_subscriptions(db, subscription_ids)
# - lookup_operator_tenants_via_products(db, product_ids)
# - lookup_plan_names_via_subscriptions(db, subscription_ids)
# - batch_lookup_entities(db, entity_ids, fields)
# - batch_lookup_fk_chain(db, start_ids, fk_field)

# Example: Replace sub -> plan -> sub_set -> tenant chain
operator_info = lookup_operator_tenants_via_subscriptions(db, subscription_fks)
# This does 4 indexed queries instead of 1 O(n⁴) nested JOIN
```

**✅ GOOD: Two-step query pattern:**
```python
# Step 1: Get the IDs you need (fast, can use indexes)
fk_ids_query = text("""
    SELECT data->>'product_fk' as product_id
    FROM entities
    WHERE data->>'type_fk' = :line_item_type
    AND data->>'product_fk' IS NOT NULL
""")
product_ids = [row.product_id for row in db.execute(fk_ids_query, params)]

# Step 2: Fetch related entities using ANY() (uses primary key index)
if product_ids:
    products_query = text("""
        SELECT entity_id, data->>'name' as name
        FROM entities
        WHERE entity_id::text = ANY(:product_ids)
    """)
    products = db.execute(products_query, {'product_ids': product_ids})
```

**✅ ALTERNATIVE: Add BTREE indexes on frequently-joined JSONB fields:**
```sql
CREATE INDEX idx_entities_data_type_fk ON entities ((data->>'type_fk'));
CREATE INDEX idx_entities_data_tenant_fk ON entities ((data->>'tenant_fk'));
CREATE INDEX idx_entities_data_product_fk ON entities ((data->>'product_fk'));
```

#### When to use each approach:

| Scenario | Recommended Approach |
|----------|---------------------|
| One-time or rare queries | Two-step query pattern |
| Frequently used FK relationships | Add BTREE index + keep JOIN |
| Large result sets (>1000 rows) | Always use two-step pattern |
| Small lookup tables (<100 rows) | JOIN is acceptable |

#### Automated JSONB JOIN Scan

Run this to find all instances in your codebase:
```bash
grep -rn "JOIN.*entity_id::text.*data->>'|JOIN.*data->>'.*entity_id::text" src/ \
  | grep -v "test" | grep -v "__pycache__" \
  | sort | uniq
```

As of this writing, there are **80+ instances** that need review.

#### Full Table Scan Detection
```python
# ❌ CRITICAL: Never do this
entities = db.query(BaseEntity).all()
filtered = [e for e in entities if e.data.get('status') == 'active']

# ✅ GOOD: Filter at database level
entities = db.query(BaseEntity).filter(
    text("data->>'status' = 'active'")
).all()
```

#### N+1 Query Pattern
```python
# ❌ BAD: Query inside loop
for user_id in user_ids:
    user = db.query(User).filter(User.id == user_id).first()
    results.append(user)

# ✅ GOOD: Single query with IN clause
users = db.query(User).filter(User.id.in_(user_ids)).all()
```

#### Missing LIMIT/Pagination
```python
# ❌ BAD: Unbounded query
all_records = db.query(BaseEntity).filter(...).all()

# ✅ GOOD: Paginated query
page_records = db.query(BaseEntity).filter(...).limit(100).offset(0).all()
```

### 6. Identify Issues

Common problems to look for:

- **Unbounded queries**: Fetching entire tables without filters (CRITICAL)
- **Client-side filtering**: Fetching all data then filtering in JS
- **Unnecessary fetches**: Data fetched but not displayed
- **Sequential calls**: Independent calls that could be parallel
- **Missing caching**: Same data fetched multiple times
- **Setup logic in view**: One-time setup running on every page load
- **Section bleed**: Data for other sections fetched unnecessarily
- **N+1 queries**: Loop that makes individual API calls per item

### 6. Propose Solutions

For each issue, provide:

```markdown
### Solution: [Brief description]
**Impact**: -XXX to -YYYms

**Problem**: What's happening now

**Change**: What to modify

**File**: path/to/file.tsx line ~XXX
```

### 7. Include Test Requirements

For each proposed change, specify:

- What tests need to be added/modified
- How to verify the optimization works
- Manual verification steps

## Output Format

```markdown
# Page Performance Analysis: [Page Name]

## Summary
- Current load time: ~Xs
- API calls on load: N
- Unnecessary calls: M
- Estimated improvement: -X to -Ys

## API Call Sequence

[Table of all calls]

## Issues Found

### Issue 1: [Description]
[Details]

### Issue 2: [Description]
[Details]

## Proposed Solutions

### Solution 1: [Title]
[Details with code changes]

### Solution 2: [Title]
[Details with code changes]

## Expected Results

| Metric | Before | After |
|--------|--------|-------|
| API calls | X | Y |
| Load time | ~Xs | ~Ys |

## Testing Requirements

### Frontend Tests
[Test specifications]

### Manual Verification
[Steps to verify]
```

## Example Analysis

See the tenants page performance analysis that led to this skill:
- Identified 8 sequential API calls taking ~6 seconds
- Found 5 unnecessary calls (sessions, properties, usage data)
- Reduced to 2-3 calls with ~1-1.5 second load time

Key optimizations:
1. Removed `fetchSessions()` from mount (sessions tab only)
2. Cached tenant type ID to avoid repeat lookups
3. Removed `ensureTenantProperties()` setup logic from view
4. Removed unused API usage summary fetch
