# 🔒 SAST Security Check

A Static Application Security Testing (SAST) tool for Go projects using [Gosec](https://github.com/securego/gosec).

**Developed by dhanibaharzah**

---

## Features

- 🔍 **Automated Security Scanning** - Runs Gosec on your Go codebase
- 📊 **Priority Matrix** - Combines severity + confidence for actionable prioritization
- 🌐 **Interactive HTML Report** - Beautiful, self-contained report with popups
- 🎯 **Severity Filtering** - Scan for specific severity levels
- 🚀 **CI/CD Ready** - Exit codes for pipeline integration
- 📦 **Auto-Install** - Installs Gosec if not present

---

## Quick Start

```bash
# Make executable (first time only)
chmod +x sast-check.sh

# Run scan on current directory (all severities)
./sast-check.sh

# Run scan with severity filter
./sast-check.sh --medium

# Run scan on a specific repository
./sast-check.sh --medium /path/to/my-go-project

# Scan another repo from anywhere
./sast-check.sh /path/to/repo
```

---

## Usage

```bash
./sast-check.sh [OPTIONS] [REPO_PATH]

Options:
  --low       Include LOW, MEDIUM, and HIGH severity issues
  --medium    Include MEDIUM and HIGH severity issues only
  --high      Include HIGH severity issues only
  --help      Show help message

Arguments:
  REPO_PATH   Path to the Go repository (default: current directory)
```

### Examples

```bash
./sast-check.sh                          # Current dir, all severities
./sast-check.sh --high                   # Current dir, high only
./sast-check.sh --medium ./backend       # ./backend dir, medium+
./sast-check.sh /home/user/my-api        # Absolute path, all severities
```

---

## Priority Matrix

The tool combines **Severity** and **Confidence** to calculate actionable priority:

```
                         CONFIDENCE
                    LOW       MEDIUM      HIGH
              ┌───────────┬───────────┬───────────┐
         HIGH │  MEDIUM   │   HIGH    │ CRITICAL  │
              │ Investigate│ Fix Soon │  Fix NOW! │
    S    ─────┼───────────┼───────────┼───────────┤
    E  MEDIUM │    LOW    │  MEDIUM   │   HIGH    │
    V         │  Review   │ Plan Fix  │ Fix Soon  │
    E    ─────┼───────────┼───────────┼───────────┤
    R    LOW  │   INFO    │   INFO    │    LOW    │
    I         │   Noise   │   Noise   │  If Time  │
    T         └───────────┴───────────┴───────────┘
    Y
```

### Priority Levels

| Priority | Meaning | Action |
|----------|---------|--------|
| 🔴 **CRITICAL** | High severity + High confidence | Fix immediately - confirmed dangerous vulnerability |
| 🟠 **HIGH** | High+Medium or Medium+High | Fix soon - likely a real security issue |
| 🟡 **MEDIUM** | High+Low or Medium+Medium | Investigate - might be real, needs review |
| 🟢 **LOW** | Medium+Low or Low+High | Review if time permits |
| ⚪ **INFO** | Low+Medium or Low+Low | Likely noise or false positive |

---

## Exit Codes

For CI/CD integration:

| Exit Code | Meaning | Recommendation |
|-----------|---------|----------------|
| `0` | No critical/high priority issues | ✅ Safe to proceed |
| `1` | HIGH priority issues found | ⚠️ Review before merge |
| `2` | CRITICAL issues found | 🛑 Block deployment |

### Example CI/CD Usage

```yaml
# GitHub Actions
- name: Run SAST Security Scan
  run: ./sast-check.sh --medium
  continue-on-error: false  # Fail on exit code 1 or 2
```

```yaml
# GitLab CI
sast:
  script:
    - ./sast-check.sh --medium
  allow_failure: false
```

---

## Output Files

| File | Description |
|------|-------------|
| `gosec-results.json` | Raw JSON output from Gosec |
| `gosec-report.html` | Interactive HTML report (self-contained) |

---

## HTML Report Features

- **📊 Overview Dashboard** - Stats cards showing priority counts
- **📋 Summary Table** - All rules sorted by priority
- **🔍 Clickable Rows** - Click any rule to see all issues in a popup
- **ⓘ Info Icons** - Click to learn about each security rule
- **🎯 Filter by Priority** - Filter issues within the popup
- **📂 Open in Cursor** - Click file paths to open directly in Cursor IDE at the exact line
- **📱 Responsive** - Works on desktop and mobile

---

## Security Rules Checked

| Rule | Description | Severity |
|------|-------------|----------|
| G101 | Hardcoded credentials | HIGH |
| G102 | Bind to all interfaces | MEDIUM |
| G104 | Unhandled errors | LOW |
| G107 | URL in HTTP request from variable (SSRF) | MEDIUM |
| G112 | Slowloris attack (no ReadHeaderTimeout) | MEDIUM |
| G115 | Integer overflow conversion | HIGH |
| G201 | SQL injection via string concatenation | HIGH |
| G202 | SQL injection via string formatting | HIGH |
| G203 | HTML template injection (XSS) | MEDIUM |
| G204 | Command injection | HIGH |
| G301 | Insecure file permissions (mkdir) | MEDIUM |
| G304 | Path traversal | MEDIUM |
| G306 | Insecure file permissions (WriteFile) | MEDIUM |
| G401 | Weak crypto (MD5, SHA1) | MEDIUM |
| G402 | Insecure TLS configuration | HIGH |
| G404 | Weak random number generator | HIGH |

[Full list of Gosec rules](https://github.com/securego/gosec#available-rules)

---

## Requirements

- **Go** - Go 1.16 or later
- **jq** - For JSON parsing (usually pre-installed on macOS/Linux)
- **Node.js or Python3** - For JSON embedding (optional, fallback to awk)

Gosec is automatically installed if not present.

---

## Ignoring False Positives

### In Code (Inline)

```go
// #nosec G104 -- error intentionally ignored for logging
logger.Log(message)

// #nosec G101 -- not a credential, just a field name
const TokenField = "auth_token"
```

### Exclude Rules

```bash
# Run without specific rules
gosec -exclude=G104,G101 ./...
```

---

## Customization

### Modify the Script

Edit `sast-check.sh` to customize:

- **Line 16**: Change output file names
- **Line 140+**: Modify HTML template styling
- **Line 270+**: Add/modify rule information in the popup

---

## Troubleshooting

### "command not found: gosec"

The script auto-installs Gosec, but if it fails:

```bash
# Install manually
go install github.com/securego/gosec/v2/cmd/gosec@latest

# Or via curl
curl -sfL https://raw.githubusercontent.com/securego/gosec/master/install.sh | sh -s -- -b $(go env GOPATH)/bin
```

### "jq: command not found"

```bash
# macOS
brew install jq

# Ubuntu/Debian
sudo apt-get install jq

# Alpine
apk add jq
```

### HTML Report Not Opening

```bash
# Open manually
open gosec-report.html          # macOS
xdg-open gosec-report.html      # Linux
start gosec-report.html         # Windows
```

---

## License

MIT License - Feel free to use and modify.

---

## Contributing

1. Fork the repository
2. Create your feature branch
3. Make changes to `sast-check.sh`
4. Test with `./sast-check.sh`
5. Submit a pull request

---

**Developed by dhanibaharzah** | Powered by [Gosec](https://github.com/securego/gosec)
