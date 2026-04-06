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
├── logs/               # 脚本日志存放处 (二级: 客户/环境)
├── reports/            # 结果测试报告 (二级: 客户/环境)
├── installer/          # 配置完成的安装包输出目录 (二级: 客户/环境)
├── backup/             # 资材备份目录 (二级: 客户/环境/时间戳)
├── config/             #工具自身的全局配置文件
│   └── history/        # 参数历史快照 (JSON 内部支持按客户分层)
└── Install-OHR.ps1     # 核心启动脚本
```

## 3. 环境与参数定义 (Environment & Parameters)

### 3.1 识别信息收集 (Environment Collection)
- **客户名称 (CustomerName)**:
    - **逻辑**: 主菜单第一级。由于客户较多，需先选择已有客户或输入 [新客户]。
- **环境名称 (EnvName)**:
    - **逻辑**: 主菜单第二级。选择客户后，列出该客户下的环境（如：社内验证、DEMO、开发、本番）或输入 [新环境]。
- **路径隔离映射**:
    - 日志: `logs/{{CustomerName}}/{{EnvName}}/`
    - 安装包: `installer/{{CustomerName}}/{{EnvName}}/`
    - 历史配置: `config/history/snapshot.json` (或 `config/history/{{CustomerName}}.json`，内部通过 JSON 结构区分环境)
    - 备份: `backup/{{CustomerName}}/{{EnvName}}/`

### 3.2 资材路径配置
- **原始资材路径 (ArtifactsPath)**: 用户提供的、未经配置的 OHR 编译包根目录。
- **配置后保存路径 (ConfiguredArtifactsPath)**: 脚本完成参数注入（配置化）后的资材存放位置。
    - **隔离逻辑**: 为防止不同客户或环境间的覆盖，必须按二级逻辑存储：`$ConfiguredArtifactsPath/{{CustomerName}}/{{EnvName}}/`。
    - **产出内容**: 包含专属于该客户环境的配置文件、.bat 脚本及安装包。

### 3.3 参数示例
```powershell
./Install-OHR.ps1 `
    -CustomerName "Hokusen-Group" `
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
    - 根据 Customer/Env 创建对应的 `logs/{{CustomerName}}/{{EnvName}}` 目录。
    - 准备 `work/` 缓存空间。
3. **配置注入 (Configurator)**:
    - 执行“备份与覆盖检查”（见 6.3 节）。
    - 将 `config.template/` 中的所有模板文件复制到 `work/`。
    - 根据参数执行变量替换（DB 连接, MinIO Endpoint 等）。
    - 将生成的配置及完整安装包移动至 `ConfiguredArtifactsPath/{{CustomerName}}/{{EnvName}}`。
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
