# PROD-01: OHR 自动化安装工具需求文档

**生效日期**: 2026-04-06
**状态**: 执行中

---

## 1. 概述 (Objective)

为庶务事务（OHR）系统提供一个基于 PowerShell 7+ 的自动化安装工具。该工具旨在通过标准化流程，将任务解耦为 **环境配置** (Configuration) 与 **部署执行** (Installation) 两大模块：
- **配置阶段**: 根据输入参数，从原始资材生成并保存专属的客户环境安装包。
- **执行阶段**: 将生成的安装包应用至服务器，完成数据库初始化、服务启动及状态验证。

## 2. 工具目录结构 (Tool Directory structure)

为确保工具的可维护性与环境隔离，遵循以下物理布局：

```text
OHR_Installer/
├── bin/                # 第三方工具文件夹 (含 PS7 核心, PG 客户端, 7z 等)
├── work/               # 临时文件目录 (执行中的缓存, 禁命名为 temp_*)
├── logs/               # 脚本日志存放处 (二级: 客户/环境)
├── reports/            # 结果测试报告 (二级: 客户/环境)
├── installer/          # 配置完成的安装包输出目录 (二级: 客户/环境)
├── backup/             # 资材备份目录 (二级: 客户/环境/时间戳)
├── config/             # 工具自身的全局配置文件
│   └── history/        # 参数历史快照 (JSON 内部支持按客户分层)
├── resources/          # 多语言资源文件 (strings.ja.psd1, strings.en.psd1, strings.zh.psd1)
├── .toolkit_lang       # 语言持久化记录文件
└── Install-OHR.ps1     # 核心启动脚本
```

## 3. 环境与参数定义 (Environment & Parameters)

### 3.1 识别信息收集 (Environment Collection)
- **客户与环境标识**: `CustomerName` / `EnvName` (主菜单引导)。
- **主机与网络信息**: 
    - `APHostIP`: 用于注入 Tenant URL (如 `192.168.10.208`)。
    - `APHostName`: 用于资源调度分配识别 (如 `HOKUSEN-HR-AP`)。
    - `APPort`: 默认 `7070`。
- **数据库连接 (PostgreSQL)**:
    - `DBHostIP`, `DBPort`, `DBUser`, `DBPassword`。
    - `PostgresBinPath`: 用于执行 `psql` / `createdb` 指令。
- **中间件与存储 (MinIO)**:
    - `MinioEndpoint`, `MinioAccessKey`, `MinioSecretKey`, `BucketName` (默认: ohr)。
- **硬件资源配额**:
    - `CPU Cores` (默认: 4), `RAM Total MB` (默认: 8192)。

### 3.2 资产路径配置 (Path Configuration)
- **原始资材路径 (ArtifactsPath)**: 用户提供的、未经配置的 OHR 编译包根目录。
- **配置后保存路径 (ConfiguredArtifactsPath)**: `$ConfiguredArtifactsPath/{{CustomerName}}/{{EnvName}}/`。
    - **隔离逻辑**: 该目录下存放 Phase A 生成的、专属于当前环境的配置文件及 **动态修正 SQL**。

### 3.3 参数示例
```powershell
./Install-OHR.ps1 `
    -CustomerName "Hokusen-Group" `
    -EnvName "Production-Primary" `
    -APHostIP "192.168.10.208" `
    -APHostName "HOKUSEN-HR-AP" `
    -ArtifactsPath "D:\Source\OHR_Release" `
    -DBCredential (Get-Credential)
```

## 4. 执行流程与关键逻辑 (Execution Logic)

### 4.1 Phase A: 配置安装环境 (Environmental Configuration)
本阶段的核心是 **“消除硬编码”**，将手顺书中的静态 IP/主机名转化为可由脚本动态注入的参数。

1. **环境采集与历史加载**: 采用两阶段菜单，通过 `config/history/` 加载上次执行的默认值。
2. **安全冲突检查与备份 (见 6.3 节)**: 检查 `installer/` 目录，若有旧版，则平移备份至 `backup/`。
3. **参数注入逻辑 (Configurator)**:
    - **文件变量替换**: 更新 `config.template/` 下的所有 `.json`, `.yml`, `.properties` 模板。
    - **动态 SQL 生成**: 根据 `APHostIP` 和 `APPort` 动态生成用于更新 `tenant` 数据库的 SQL (即 `UPDATE tenant SET url = ...` 及 `INSERT INTO async_task_resource_distribution ...`)。
4. **离线包封装**: 将配置好的所有文件、脚本及编译后的安装包完整复制至 `installer/{{CustomerName}}/{{EnvName}}/`。

### 4.2 Phase B: 执行部署安装 (Installation Execution)
基于 Phase A 产出的资材，执行符合《环境安装手顺书》顺序的全流程部署。

1. **数据库准备与初始化**:
    - 配置 PostgreSQL `pg_hba.conf` 并重启服务。
    - 在本地或远程（WinRM）创建 `tenant` 与 `ohr` 数据库。
2. **Tenant 数据导入 (关键手顺映射)**:
    - 依次从 `sql/1.tenant/` 路径导入：`i18n_svc_message.sql`, `i18n_web_message.sql`, `url_info.sql`, `ohr_help.sql`。
    - 执行 Phase A 生成的 **IP 与资源配额修正 SQL**。
3. **服务注册与启动**:
    - 执行 `allow.execute.ps1.script.bat`（管理员权限提升）。
    - 执行 `suite.install.ps1`（输入 "y" 自动确认）。
    - 执行 `suite.start.ps1`（由于配置已注入，无需人工干预）。
4. **业务数据 (OHR) 与中间件配置**:
    - 依次从 `sql/2.ohr/` 路径导入：`ds-create`, `code`, `scheduled_task`, `account`, `ohr.sql`。
    - **MinIO 配置**: 自动创建 Bucket 条目（参考 F1 手顺）。
    - **计划任务**: 执行 `win-create-task-job.bat` 以实现 Windows 自启动。
5. **综合验收**:
    - 模拟 HTTP 总领口请求 (`7070`)，生成最终的 `reports/` 数据文件。

## 5. 日志与报告要求 (Logs & Reports)

### 5.1 脚本日志 (Script Log)
- **存放路径**: `logs/{{CustomerName}}/{{EnvName}}/YYYYMMDD_HHmmss.log`。
- **内容级别**:
    - `INF`: 正常进度。
    - `WRN`: 非关键性偏差。
    - `ERR`: 关键步骤失败（触发回滚或停止）。
    - `DBG`: 详细指令流（默认关闭，通过 -Debug 开启）。

### 5.2 结果测试报告 (Test Report)
- **格式**: 生成 `reports/{{CustomerName}}/{{EnvName}}/TestResult_YYYYMMDD.md`。
- **覆盖项**:
    - 通信验证 (AP ↔ DB, AP ↔ MinIO)。
    - 服务状态监控 (Web/Service Service Status)。
    - 核心 URL 可访问性清单。
    - 数据库对象完整性检查总结。

## 6. 状态持久化与断点续做 (State Persistence & Resume)

### 6.1 参数回填机制 (Default Values)
- **参数收集**:
    - 在运行过程中，脚本需持久化参数至 `config/history/` 目录下的 JSON 文件中。建议按客户维度存储（如 `{{CustomerName}}.json`），内部通过环境名键值对实现属性分层。
- **交互逻辑**:
    - 下次运行时，脚本根据选定的客户从其对应的 JSON 或 全局 snapshot 中加载环境配置。
    - **环境切换**: 若 `CustomerName` 或 `EnvName` 不同，脚本将视为新目标，重新进入相应层级的配置引导。

### 6.2 断点续做逻辑 (Resume)
...
### 6.3 备份与安全逻辑 (Backup & Safety)
- **存在性检查**:
    - 在生成安装包前，检查 `installer/{{CustomerName}}/{{EnvName}}/` 是否已存在合法的安装资材。
- **交互提示**:
    - 若已存在旧资材，提示：“检测到该环境已存在安装包。为防止覆盖，系统将先执行备份，是否继续？[Y/N]”。
- **备份执行**:
    - 确认后，将旧目录移动至 `backup/{{CustomerName}}/{{EnvName}}/YYYYMMDD_HHmmss/`。
    - 清空原环境目录，写入新生成的安装资材。

## 7. 错误处理策略 (Error Handling)

- **原子性原则**: 配置注入阶段失败需立即停止，不进入部署阶段。
- **回滚机制**: 服务安装失败需尝试调用 `suite.stop.ps1` 并输出系统日志以便排查。
- **非目标范围**: 脚本不负责编译源代码及处理环境缺失的 OS 补丁。

## 8. i18n 多语言支持 (i18n Support)

### 8.1 语种支持
- **日语 (JA)**: 默认语种。
- **中文 (ZH)**: 简体中文。
- **英语 (EN)**: 标准英语。

### 8.2 逻辑设计
- **首播检查**: 若当前目录不存在 `.toolkit_lang` 文件，则默认使用日语 (`JA`)。
- **持久化记录**: 每次选定或手动切换语种后，将语言代码写入 `.toolkit_lang`。
- **回填逻辑**: 下次运行脚本时，优先读取 `.toolkit_lang` 记录的值作为全局语种设置。
- **外部定义**: 所有 UI 文案、提示语、错误摘要均抽离至 `resources/strings.<lang>.psd1`，脚本内仅引用资源 Key。

### 8.3 交互逻辑
- **语言设置菜单**: 主菜单包含“切换语种 (Change Language)”入口，交互式循环切换或列表选择。
