# Status Hub Provider Standard

Status Hub is a generic host. Providers communicate through manifests, status
JSON files, optional commands, and configuration JSON.

## Plugin Manifest

Both bundled providers and GitHub-installed plugins use the same
`statushub-plugin.json` schema. GitHub-installed plugins must provide the file
at the repository root. Bundled providers are packaged by Status Hub under
`BuiltinPlugins/<plugin-id>/`.

```json
{
  "id": "example-status-provider",
  "title": "Example Status Provider",
  "version": "0.1.0",
  "providers": [
    {
      "id": "main",
      "title": "Example Provider",
      "icon": "square.stack.3d.up",
      "statusFile": "runtime/status.json",
      "configFile": "runtime/config.json",
      "command": "bin/example-provider",
      "arguments": [],
      "workingDirectory": "."
    }
  ]
}
```

### Required Provider Fields

- `id`: stable provider id inside the plugin.
- `title`: user-facing provider name.
- `icon`: required icon. Use either a valid SF Symbol name or a plugin-relative
  image path such as `assets/gitlab-icon.svg`.
- `statusFile`: JSON file written by the provider.

### Optional Provider Fields

- `configFile`: JSON config file managed by Status Hub settings.
- `command`: executable command started by Status Hub.
- `arguments`: command arguments.
- `workingDirectory`: relative working directory. Defaults to the plugin root.
- `configuration`: settings sections rendered by Status Hub.

## Runtime Environment

When Status Hub starts a provider command, it passes:

- `STATUS_HUB_PROVIDER_ID`
- `STATUS_HUB_STATUS_FILE`
- `STATUS_HUB_CONFIG_FILE`
- `STATUS_HUB_DATA_DIR`

Provider commands should keep running, poll their own data sources, and write
`STATUS_HUB_STATUS_FILE` atomically.

## Status File

```json
{
  "status": "attention",
  "summary": "2 个任务需要确认，1 个正在运行",
  "updatedAt": "2026-06-11T12:30:00+08:00",
  "items": [
    {
      "id": "daily-job",
      "title": "每日任务",
      "subtitle": "等待人工确认",
      "status": "attention",
      "url": "https://example.com/artifacts/daily-job",
      "value": "2",
      "detail": {
        "owner": "team"
      },
      "actions": [
        {
          "id": "run",
          "title": "触发",
          "command": "bin/example-provider",
          "arguments": ["run"],
          "workingDirectory": "."
        }
      ],
      "links": [
        {
          "id": "latest-report",
          "title": "最近报告",
          "url": "https://example.com/report"
        }
      ]
    }
  ]
}
```

Supported status values:

- `idle`
- `success`
- `running`
- `attention`
- `failed`
- `unknown`

## Configuration

Provider manifests may declare settings sections:

```json
{
  "configuration": [
    {
      "id": "connection",
      "title": "Connection",
      "fields": [
        {
          "key": "service.baseUrl",
          "title": "Base URL",
          "type": "text",
          "defaultValue": "https://example.com"
        },
        {
          "key": "service.token",
          "title": "Token",
          "type": "password"
        }
      ]
    }
  ]
}
```

Supported field types:

- `text`
- `textarea`
- `password`
- `number`
- `toggle`
- `select`
- `multiselect`
- `externalConfig`

Status Hub writes provider config as JSON to `configFile` and preserves
`runtime/` during plugin updates.

## Distribution

Use bundled providers for general-purpose functionality that should ship with
Status Hub, such as system health. Use GitHub-installed providers for custom or
team-specific integrations, such as GitLab monitoring or Intelli automation.

Bundled providers are copied from the app bundle into:

```text
~/Library/Application Support/StatusHub/plugins/<plugin-id>/
```

They still run out of the user plugin directory so `runtime/`, generated
helpers, and provider config remain writable. Bundled provider updates are
delivered with the Status Hub app. GitHub-installed providers are updated from
repository tags.

## Provider-Owned Advanced UI

If a provider needs domain-specific interaction, such as GitLab project search
and branch selection, keep that interaction inside the provider. Expose it as a
provider action or helper command, while Status Hub remains the generic launcher
and status renderer.

Declare that flow as an `externalConfig` field:

```json
{
  "key": "repositories",
  "title": "Monitored Projects",
  "type": "externalConfig",
  "placeholder": "Select projects and branches",
  "help": "Opens the provider-owned selector and writes configFile",
  "command": "bin/configurator",
  "arguments": [],
  "workingDirectory": "."
}
```

When the user clicks the field, Status Hub starts `command` and passes the same
provider environment variables. The helper should read and write
`STATUS_HUB_CONFIG_FILE`; Status Hub reloads and restarts the provider after the
helper exits.
