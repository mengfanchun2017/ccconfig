---
name: research-report
user-invocable: true
description: Summarize deep research results into markdown report, cover all fields, skip uncertain values.
allowed-tools: Read, Write, Glob, Bash, AskUserQuestion
---

# Research Report - Summary Report

## Trigger
`/research-report`

## Workflow

### Step 1: Locate Results Directory
Find `*/outline.yaml` in current working directory, read topic and output_dir config.

### Step 2: Scan Optional Summary Fields
Read all JSON results, extract fields suitable for TOC display (numeric, short metrics), e.g.:
- github_stars
- google_scholar_cites
- swe_bench_score
- user_scale
- valuation
- release_date

Use AskUserQuestion to ask user:
- Which fields to display in TOC besides item name?
- Provide dynamic options list (based on actual fields in JSON)

### Step 3: Generate Python Conversion Script
Generate `generate_report.py` in `{topic}/` directory, script requirements:
- Read all JSON from output_dir
- Read fields.yaml to get field structure
- Cover all field values from each JSON
- Skip fields with values containing [uncertain]
- Skip fields listed in uncertain array
- Generate markdown report format: Table of contents (with anchor links + user-selected summary fields) + Detailed content (by field category)
- Save to `{topic}/report.md`

**TOC Format Requirements**:
- Must include every item
- Each item displays: number, name (anchor link), user-selected summary fields
- Example: `1. [GitHub Copilot](#github-copilot) - Stars: 10k | Score: 85%`

#### Script Technical Requirements (Must Follow)

**1. JSON Structure Compatibility**
Support two JSON structures:
- Flat structure: Fields directly at top level `{"name": "xxx", "release_date": "xxx"}`
- Nested structure: Fields in category sub-dict `{"basic_info": {"name": "xxx"}, "technical_features": {...}}`

Field lookup order: Top level -> category mapping key -> Traverse all nested dicts

**2. Category Multi-language Mapping**
fields.yaml category names and JSON keys can be any combination (CN-CN, CN-EN, EN-CN, EN-EN). Must establish bidirectional mapping:
```python
CATEGORY_MAPPING = {
    "Basic Info": ["basic_info", "Basic Info"],
    "Technical Features": ["technical_features", "technical_characteristics", "Technical Features"],
    "Performance Metrics": ["performance_metrics", "performance", "Performance Metrics"],
    "Milestone Significance": ["milestone_significance", "milestones", "Milestone Significance"],
    "Business Info": ["business_info", "commercial_info", "Business Info"],
    "Competition & Ecosystem": ["competition_ecosystem", "competition", "Competition & Ecosystem"],
    "History": ["history", "History"],
    "Market Positioning": ["market_positioning", "market", "Market Positioning"],
}
```

**3. Complex Value Formatting**
- list of dicts (e.g., key_events, funding_history): Format each dict as one line, separate kv with ` | `
- Normal list: Short lists joined with comma, long lists displayed with line breaks
- Nested dict: Recursive formatting, display with semicolon or line breaks
- Long text strings (over 100 chars): Add line breaks `<br>` or use blockquote format for readability

**4. Extra Fields Collection**
Collect fields that exist in JSON but not defined in fields.yaml, put in "Other Info" category. Note to filter:
- Internal fields: `_source_file`, `_sources`, `uncertain`
- Nested structure top-level keys: `basic_info`, `technical_features` etc.
- `uncertain` array: Display each field name on separate line, don't compress into one line

**5. Uncertain Value Skipping**
Skip conditions:
- Field value contains `[uncertain]` string
- Field name is in `uncertain` array
- Field value is None or empty string

### Step 4: Execute Script
Run `python {topic}/generate_report.py`

## Output
- `{topic}/generate_report.py` - Conversion script
- `{topic}/report.md` - Summary report

---

## Report Quality Standards

The generated `report.md` MUST follow these standards:

### Structure Template

```markdown
# {Topic} Research Report
> Generated: {YYYY-MM-DD} | Sources: {N} | Items: {M}

## Table of Contents
(anchor links + summary fields per item)

## 1. Executive Summary
- 3-5 sentence overview of key findings
- Cross-cutting patterns across all items

## 2. Item Details
(one section per item, organized by field category)

## 3. Comparative Analysis
- Comparison table across items on key metrics
- Notable outliers and patterns

## 4. Sources
- Full list of sources consulted, grouped by item
- Each source: title, URL, access date

## 5. Uncertainty Register
- List all fields marked [uncertain] across all items
- Group by item, note reason if known
```

### Citation Format

Every data point that comes from a specific source MUST be cited:
- Inline: `[Source: Title](URL)` after the fact
- Multiple sources: `[Sources: Title1, Title2](URL1, URL2)`
- No bare URLs — always include descriptive title text
- Model knowledge (not from web search) does not need citation

### Data Confidence Levels

Mark data reliability using these tags:
- `[verified]` — Confirmed by 2+ independent sources
- `[single-source]` — From one source only, cross-reference needed
- `[uncertain]` — Source conflict or low-confidence estimate
- `[model-knowledge]` — From training data, not verified by web search

### Content Quality Rules

1. **Lead with insight, support with data** — Don't just list facts; explain what they mean
2. **No placeholder text** — Every section must have substantive content
3. **Numbers over adjectives** — "grew 34% YoY" not "grew significantly"
4. **Compare across items** — Don't treat each item in isolation
5. **Acknowledge gaps** — If a field is empty for most items, note it in the uncertainty register
6. **Chinese-friendly** — If topic involves China/Chinese market, include Chinese-sourced data explicitly
