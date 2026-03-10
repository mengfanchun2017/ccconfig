# Clash 数据科学配置

仅让 GitHub、PyPI、HuggingFace 等数据科学网站走代理，其他所有流量直连。

---

## 🚀 快速使用

### 方法一：在 Clash Verge 中手动导入规则

1. 打开 Clash Verge
2. 点击「规则」标签
3. 点击「编辑」或「添加」
4. 打开 `data-science-rules.yaml`，复制 `rules:` 下面的所有内容
5. 粘贴到 Clash Verge 的规则编辑器中
6. 保存并重启 Clash Verge

### 方法二：合并到现有配置

如果你已有 Clash 配置文件，只需把 `data-science-rules.yaml` 中的 `rules` 部分复制到你的配置文件中即可。

---

## 📋 包含的网站

### GitHub / 代码托管
- github.com
- githubusercontent.com
- github.io
- gitlab.com
- gist.github.com
- api.github.com
- raw.githubusercontent.com

### Python / PyPI
- pypi.org
- files.pythonhosted.org

### Conda / Anaconda
- anaconda.com
- repo.anaconda.com
- conda.anaconda.org
- anaconda.org
- conda-forge.org

### 机器学习 / AI
- huggingface.co
- tensorflow.org
- pytorch.org
- keras.io
- scikit-learn.org
- scipy.org
- numpy.org
- pandas.pydata.org
- streamlit.io
- plotly.com
- matplotlib.org

### 云服务 / 数据集
- colab.research.google.com
- kaggle.com
- storage.googleapis.com
- s3.amazonaws.com

### 学术 / 论文
- arxiv.org
- export.arxiv.org
- nature.com
- science.org

### OpenAI
- openai.com
- api.openai.com

---

## ⚙️ 规则说明

| 规则类型 | 说明 |
|---------|------|
| `DOMAIN-SUFFIX` | 域名后缀匹配，匹配该域名及所有子域名 |
| `GEOIP,CN,DIRECT` | 中国 IP 直连 |
| `MATCH,,DIRECT` | 其他所有流量直连（必须放在最后） |

**重要：规则按从上到下的顺序匹配，命中第一条后就不再继续匹配！**

---

## 🔍 验证配置

1. 打开 Clash Verge → 「日志」页面
2. 访问 `github.com`
3. 查看日志，应该显示类似：
   ```
   hit rule DOMAIN-SUFFIX,github.com,PROXY
   ```
4. 访问 `baidu.com`
5. 查看日志，应该显示：
   ```
   hit rule MATCH,,DIRECT
   ```

---

## 📝 注意事项

1. **PROXY 替换**：配置中的 `PROXY` 需要替换为你实际的代理组名称或节点名称
2. **规则顺序**：`MATCH,,DIRECT` 必须放在最后！
3. **Git 代理**：确保 Git 配置使用 Clash 代理端口（7897）：
   ```bash
   git config --global http.proxy http://127.0.0.1:7897
   git config --global https.proxy http://127.0.0.1:7897
   ```
