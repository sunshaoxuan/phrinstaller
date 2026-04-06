# PROD-01: OHR 自动化安装工具需求文档

**生效日期**: 2026-04-06
**状态**: 执行中

---

## 1. 概述 (Objective)

为庶务事务（OHR）系统提供一个基于 PowerShell 7+ 的自动化安装工具。该工具旨在通过标准化流程，在 On-Premise 环境中完成从“原始资材配置”到“全自动化部署”的闭环，显著降低人工干预风险。

## 2. 工具目录结构 (Tool Directory structure)

为确保工具的可维护性与环境隔离，遵循以下物理布局：

```text
OHR_Installer/
├── bin/                # 第三方工具文件夹 (含 PS7 核心, PG 客户端, 7z 等)
├── work/               # 临时文件目录 (执行中的缓存, 禁命名为 temp_*)
├── logs/               # 脚本日志存放处 (按 EnvName 分离)
├── reports/            # 结果测试报告 (JSON/HTML 格式)
├── installer/          # 配置完成的安装包输出目录 (按 EnvName 分离)
├── config/             # 工具自身的全局配置文件
│   └── history/        # 历史执行快照 (断点续做与默认值回填)
└── Install-OHR.ps1     # 核心启动脚本
```

## 3. 环境与参数定义 (Environment & Parameters)

### 3.1 环境收集
- **环境名称 (EnvName)**:
    - 采集方式：脚本运行参数或交互式输入。
    - 用途：作为目录隔离标识符，用于命名日志子目录、资源保存目录及配置文件后缀（如 `ohr.dev.json`）。

### 3.2 资材路径配置
- **原始资材路径 (ArtifactsPath)**: 用户提供的、未经配置的 OHR 编译包根目录。
- **配置后保存路径 (ConfiguredArtifactsPath)**: 脚本完成参数注入（配置化）后的资材存放位置。
    - **隔离逻辑**: 为防止多环境覆盖，必须按逻辑存储为：`$ConfiguredArtifactsPath/$EnvName/`。
    - **产出内容**: 包含已替换变量的配置文件、.bat 脚本及 OHR 安装包。

### 3.3 参数示例
```powershell
./Install-OHR.ps1 `
    -EnvName "Production-Primary" `
    -ArtifactsPath "D:\Source\OHR_Release" `
    -ConfiguredArtifactsPath "D:\Configured\OHR" `
    -APHostName "AP-SRV-01" `
    -IsDBLocal $false `
    -DBCredential (Get-Credential)
```

## 4. 执行流程与关键逻辑 (Execution Logic)

### 4.1 核心步骤（线性连续）
1. **初始化校验**:
    - 运行权限提升 (Admin Required)。
    - PowerShell 7.0+ 检查。
    - 原始资材目录 (`ArtifactsPath`) 完整性检查（包含 install/, sql/, config.template/）。
2. **环境预热**:
    - 创建对应的 `logs/$EnvName` 目录。
    - 准备 `work/` 缓存空间。
3. **配置注入 (Configurator)**:
    - 将 `config.template/` 中的所有模板文件复制到 `work/`。
    - 根据参数执行变量替换（DB 连接, MinIO Endpoint 等）。
    - 将生成的配置及完整安装包移动至 `ConfiguredArtifactsPath/$EnvName`。
4. **数据库与服务部署**:
    - 支持 AP/DB 同机或分离架构（分离模式通过 WinRM 执行）。
    - 数据库初始化（tenant/ohr 两个 DB）。
    - 修改 `pg_hba.conf` 并校验连通性。
    - 执行 `suite.install.ps1` 进行 AP 服务部署。
5. **服务验证**:
    - 启动服务 (`suite.start.ps1`)。
    - 端口监听 (`7070`) 与 HTTP 响应（HTTP 200/302）校验。

## 5. 日志与报告要求 (Logs & Reports)

### 5.1 脚本日志 (Script Log)
- **存放路径**: `logs/$EnvName/YYYYMMDD_HHmmss.log`。
- **内容级别**:
    - `INF`: 正常进度。
    - `WRN`: 非关键性偏差。
    - `ERR`: 关键步骤失败（触发回滚或停止）。
    - `DBG`: 详细指令流（默认关闭，通过 -Debug 开启）。

### 5.2 结果测试报告 (Test Report)
- **格式**: 生成 `reports/$EnvName/TestResult_YYYYMMDD.md`。
- **覆盖项**:
    - 通信验证 (AP ↔ DB, AP ↔ MinIO)。
    - 服务状态监控 (Web/Service Service Status)。
    - 核心 URL 可访问性清单。
    - 数据库对象完整性检查总结。

## 6. 状态持久化与断点续做 (State Persistence & Resume)

### 6.1 参数回填机制 (Default Values)
- **参数收集**:
    - 在运行过程中，脚本需实时或在关键节点将采集到的参数（如 `ArtifactsPath`, `APHost`, `DBHost`, `DBCredential` 及其它应用配置）持久化至 `config/history/$EnvName.json`。
- **交互逻辑**:
    - 下次运行时，若指定了相同的 `EnvName`，脚本会自动从历史 JSON 中加载旧值作为默认值。
    - **UI 展示**: 提示时显示格式 `请输入 <参数名称> [默认值: <旧值>]:`。
    - **逻辑处理**:
        - 若用户直接按下 `Enter`: 使用持久化文件中的旧值。
        - 若用户输入新值: 使用并更新持久化文件中的该项值。
    - **环境隔离**: 若 `EnvName` 不同，脚本将视为新环境，重新进入空白配置引导流程。

### 6.2 断点续做逻辑 (Resume)
- **步骤状态记录**:
    - 脚本需维护每一步骤（Step 1-7）的执行状态 (`Pending` / `Success` / `Failed`)。
- **重运行逻辑**:
    - 脚本在启动后检查历史状态。
    - 对于状态为 `Success` 且具有**幂等性**的步骤（如创建目录、校验版本），脚本可跳过并直接输出提示消息。
    - 对于非幂等或关键安装步骤，脚本应询问用户是否重新执行 (`-Force` 参数可强制全量执行)。

## 7. 错误处理策略 (Error Handling)

- **原子性原则**: 配置注入阶段失败需立即停止，不进入部署阶段。
- **回滚机制**: 服务安装失败需尝试调用 `suite.stop.ps1` 并输出系统日志以便排查。
- **非目标范围**: 脚本不负责编译源代码及处理环境缺失的 OS 补丁。
