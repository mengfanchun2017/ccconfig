---
name: research
user-invocable: true
allowed-tools: Read, Write, Glob, WebSearch, Task, AskUserQuestion, mcp__tavily__tavily_search, mcp__tavily__tavily_research, mcp__tavily__tavily_extract, mcp__minimax__web_search
description: Conduct preliminary research on a topic and generate research outline. For academic research, benchmark research, technology selection, etc.
---

# Research Skill - Preliminary Research

## Trigger
`/research <topic>`

## Workflow

### Step 1: Generate Initial Framework from Model Knowledge
Based on topic, use model's existing knowledge to generate:
- Main research objects/items list in this domain
- Suggested research field framework

Output {step1_output}, use AskUserQuestion to confirm:
- Need to add/remove items?
- Does field framework meet requirements?

### Step 2: Three-Source Web Search Supplement (MANDATORY)

**CRITICAL**: Do NOT use a single web search. Launch all three searches in parallel, then aggregate results.

Use AskUserQuestion to ask for time range (e.g., last 6 months, since 2024, unlimited).

**Parameter Retrieval**:
- `{topic}`: User input research topic
- `{topic_cn}`: Chinese translation of topic
- `{YYYY-MM-DD}`: Current date
- `{step1_output}`: Complete output from Step 1
- `{time_range}`: User specified time range

**Hard Constraint**: The following three searches must run in PARALLEL, not sequentially.

#### Search 1: Tavily English Search
```
mcp__tavily__tavily_search
  query: "{topic} latest developments {time_range}"
  search_depth: "advanced"
  max_results: 10
```
Follow up with `mcp__tavily__tavily_extract` on the top 3-5 most relevant results for full text.

#### Search 2: Minimax Chinese Search
```
mcp__minimax__web_search
  query: "{topic_cn} 最新动态 2025"
```

#### Search 3: Tavily Deep Research (for synthesis)
```
mcp__tavily__tavily_research
  input: "Comprehensive overview of {topic}. Based on this existing framework: {step1_output}. Identify missing items and suggest additional research fields. Focus on {time_range}."
  model: "auto"
```

#### Fallback: Built-in WebSearch
If any of the above returns insufficient results, supplement with built-in `WebSearch` using equivalent queries.

#### Aggregation
After all three sources return, merge results:
1. Extract unique items from all sources
2. Deduplicate: same item found in multiple sources → keep the one with most detail
3. Mark source origin for each item: [tavily] / [minimax] / [tavily-research]
4. Flag items found in only one source for user review
5. Aggregate all source URLs into a unified source list

### Step 3: Ask User for Existing Fields
Use AskUserQuestion to ask if user has existing field definition file, if so read and merge.

### Step 4: Generate Outline (Separate Files)
Merge {step1_output}, {step2_output} and user's existing fields, generate two files:

**outline.yaml** (items + config):
- topic: Research topic
- items: Research objects list
- execution:
  - batch_size: Number of parallel agents (confirm with AskUserQuestion)
  - items_per_agent: Items per agent (confirm with AskUserQuestion)
  - output_dir: Results output directory (default: ./results)

**fields.yaml** (field definitions):
- Field categories and definitions
- Each field's name, description, detail_level
- detail_level hierarchy: brief -> moderate -> detailed
- uncertain: Uncertain fields list (reserved field, auto-filled in deep phase)

### Step 5: Output and Confirm
- Create directory: `./{topic_slug}/`
- Save: `outline.yaml` and `fields.yaml`
- Show to user for confirmation

## Output Path
```
{current_working_directory}/{topic_slug}/
  ├── outline.yaml    # items list + execution config
  └── fields.yaml     # field definitions
```

## Follow-up Commands
- `/research-add-items` - Supplement items
- `/research-add-fields` - Supplement fields
- `/research-deep` - Start deep research
