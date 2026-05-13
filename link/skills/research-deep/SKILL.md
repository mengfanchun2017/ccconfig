---
name: research-deep
user-invocable: true
description: Read research outline, launch independent agent for each item for deep research. Uses tavily MCP research() for AI-synthesized deep research, tavily extract() for full-text, minimax web_search for Chinese sources. Disable task output.
allowed-tools: Bash, Read, Write, Glob, WebSearch, Task, mcp__tavily__tavily_search, mcp__tavily__tavily_research, mcp__tavily__tavily_extract, mcp__minimax__web_search
---

# Research Deep - Deep Research

## Trigger
`/research-deep`

## Workflow

### Step 1: Auto-locate Outline
Find `*/outline.yaml` file in current working directory, read items list, execution config (including items_per_agent).

### Step 2: Resume Check
- Check completed JSON files in output_dir
- Skip completed items

### Step 3: Batch Execution
- Batch by batch_size (need user approval before next batch)
- Each agent handles items_per_agent items
- Launch research-agent (background parallel, disable task output)

**Parameter Retrieval**:
- `{topic}`: topic field from outline.yaml
- `{item_name}`: item's name field
- `{item_related_info}`: item's complete yaml content (name + category + description etc.)
- `{output_dir}`: execution.output_dir from outline.yaml (default: ./results)
- `{fields_path}`: absolute path to {topic}/fields.yaml
- `{output_path}`: absolute path to {output_dir}/{item_name_slug}.json (slugify item_name: replace spaces with _, remove special chars)

**Hard Constraint**: The following prompt must be strictly reproduced, only replacing variables in {xxx}, do not modify structure or wording.

**Prompt Template**:
```python
prompt = f"""## Task
Research {item_related_info}, output structured JSON to {output_path}

## Field Definitions
Read {fields_path} to get all field definitions

## Research Method (Three-Source Coverage — Execute in Parallel)

You MUST use all three sources in parallel to ensure comprehensive coverage:

### Source 1: Tavily Deep Research (Primary — for synthesis)
Use `mcp__tavily__tavily_research` with input:
"A comprehensive analysis of {item_name} in the context of {topic}. Include all aspects covered by the field definitions."
- Model: "pro" for complex/multi-faceted items, "auto" for straightforward items
- This returns an AI-synthesized report with citations

### Source 2: English Web Search (Supplementary — for gaps)
Use `mcp__tavily__tavily_search` with query:
"{item_name} {topic} overview features performance"
- search_depth: "advanced"
- Extract key pages with `mcp__tavily__tavily_extract` for full text

### Source 3: Chinese Web Search (Supplementary — for Chinese market/context)
Use `mcp__minimax__web_search` with query translated to Chinese:
"{item_name} {topic} 中文 分析 评测"
- Aggregate Chinese-specific information and perspectives

### Fallback
If any source returns no useful results, supplement with built-in `WebSearch` using the same queries.

## Result Aggregation
After all three sources return:
1. Cross-reference and deduplicate findings
2. Mark conflicting information from different sources
3. Prefer information with explicit source citations
4. Combine English + Chinese perspectives into unified field values

## Output Requirements
1. Output JSON according to fields defined in fields.yaml
2. Mark uncertain field values with [uncertain]
3. Add uncertain array at the end of JSON, listing all uncertain field names
4. All field values must be in English
5. Add `_sources` array at JSON root: list of source URLs consulted

## Output Path
{output_path}

## Validation
After completing JSON output, run validation script to ensure complete field coverage:
python ~/.claude/skills/research/validate_json.py -f {fields_path} -j {output_path}
Task is complete only after validation passes.
"""
```

**One-shot Example** (assuming researching GitHub Copilot):
```
## Task
Research name: GitHub Copilot
category: International Product
description: Developed by Microsoft/GitHub, first mainstream AI coding assistant, ~40% market share, output structured JSON to {project_dir}/results/GitHub_Copilot.json

## Field Definitions
Read {project_dir}/fields.yaml to get all field definitions

## Research Method (Three-Source Coverage — Execute in Parallel)

You MUST use all three sources in parallel to ensure comprehensive coverage:

### Source 1: Tavily Deep Research (Primary)
mcp__tavily__tavily_research with input:
"A comprehensive analysis of GitHub Copilot in the context of AI Coding. Include basic info, technical features, market positioning, pricing, and competitive landscape."

### Source 2: English Web Search (Supplementary)
mcp__tavily__tavily_search with query: "GitHub Copilot AI coding assistant features pricing market share 2025"
Extract key pages for full text.

### Source 3: Chinese Web Search (Supplementary)
mcp__minimax__web_search with query: "GitHub Copilot AI编程助手 评测 价格 功能 2025"

## Output Requirements
1. Output JSON according to fields defined in fields.yaml
2. Mark uncertain field values with [uncertain]
3. Add uncertain array at the end of JSON, listing all uncertain field names
4. All field values must be in English
5. Add `_sources` array at JSON root

## Output Path
{project_dir}/results/GitHub_Copilot.json

## Validation
After completing JSON output, run validation script to ensure complete field coverage:
python ~/.claude/skills/research/validate_json.py -f {project_dir}/fields.yaml -j {project_dir}/results/GitHub_Copilot.json
Task is complete only after validation passes.
```

### Step 4: Wait and Monitor
- Wait for current batch to complete
- Launch next batch
- Display progress

### Step 5: Summary Report
After all complete, output:
- Completion count
- Failed/uncertain marked items
- Output directory

## Agent Config
- Background execution: Yes
- Task Output: Disabled (agent has explicit output file when complete)
- Resume support: Yes
