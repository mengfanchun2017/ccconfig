# data-pipeline — 数据 / ML Pipeline 项目

> 场景:数据工程 / ETL / ML 训练 / 特征工程 / 报表
> 复杂度:★★★★

## 适用

- 日志聚合 / 事件流处理
- 数据仓库(ETL → dbt → BI)
- ML 训练 pipeline
- 特征工程 / 模型评估
- 定时报表 / 数据同步

## 默认技术栈

| 组件 | 选型 | 理由 |
|------|------|------|
| 语言 | Python 3.12 | 数据生态最厚 |
| 工作流编排 | Dagster / Airflow / Prefect | 复杂度递减 |
| 数据处理 | Polars / Pandas 2.x | Polars 性能更好 |
| 转换层 | dbt (SQL) | 数据建模标准 |
| 存储 | Parquet / DuckDB / ClickHouse | 列式存储 |
| 调度 | cron / Dagster daemon | 简单 → 复杂 |
| 观测 | OpenTelemetry + Grafana | 标准 |
| 部署 | Docker + K8s / ECS / Cloud Run | 容器化 |

## 备选

| 场景 | 选型 |
|------|------|
| 实时流 | Apache Flink / Kafka Streams / Materialize |
| 大数据 | Spark / PySpark |
| 轻量级(单机) | DuckDB + cron |
| ML 训练 | Kubeflow / Metaflow / Ray |

## 脚手架结构

```
<代号>/
├── src/
│   ├── pipelines/         # Dagster/Airflow 定义
│   │   ├── ingest.py
│   │   ├── transform.py
│   │   └── train.py
│   ├── lib/               # 工具
│   ├── data/              # 数据 schema
│   └── main.py
├── tests/
│   ├── test_pipelines/
│   └── fixtures/
├── notebooks/             # 探索性分析
├── dags/                  # Airflow 兼容
├── data/                  # 数据(本地)
│   ├── raw/
│   ├── processed/
│   └── features/
├── pyproject.toml
├── Dockerfile
├── README.md
└── LICENSE
```

## 关键决策

- **批次 vs 流式**:小时级批次用 Airflow/Dagster;秒级流式用 Flink/Kafka
- **本地 vs 云**:本地 DuckDB 起步;数据量 GB+ 上云(S3 + Athena / BigQuery)
- **数据契约**:dbt + data contract 文件,上下游明确 schema
- **回填(backfill)**:Dagster partitions 原生支持;Airflow 需自定义
- **幂等性**:所有任务必须可重跑不破坏数据(关键!)

## 风险点

1. **数据漂移** — 上游 schema 变更会让 pipeline 失败。缓解:加 schema 校验 + 大数据测试(ge 库)。
2. **资源耗尽** — 处理大文件 OOM。缓解:用 Polars 惰性求值 + 分块处理 + 监控内存。
3. **调度失败级联** — 一个任务失败影响下游。缓解:Dagster/Airflow 重试 + 告警 + 手动 backfill。
4. **数据血缘不清晰** — 几月后没人知道某字段从哪来。缓解:dbt docs + OpenMetadata / DataHub。
5. **重算成本** — 全量重算消耗大。缓解:增量(partition) + 缓存中间层。

## 学习路径(4-6 周)

| 周 | 任务 |
|----|------|
| 1 | 选编排框架 + 简单 ETL demo(单文件输入输出) |
| 2 | 加 Polars / dbt 做转换 + 单元测试 |
| 3 | 调度(cron / Dagster daemon)+ 监控(日志 / 告警) |
| 4 | Docker 化 + 部署到云(Cloud Run / ECS) |
| 5 | 数据契约 + 血缘 + 文档(dbt docs) |
| 6 | 集成测试 + 灾备(数据快照) + 性能调优 |
