#!/bin/bash

# =============================================================================
# SAST Security Check Script for Go Projects
# Uses Gosec for static application security testing
# =============================================================================

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Configuration
GOSEC_PATH="$(go env GOPATH)/bin/gosec"

# Print banner
echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║              🔒 SAST Security Check via Gosec                 ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Help function
show_help() {
    echo -e "${BLUE}Usage:${NC} $0 [OPTIONS] [REPO_PATH]"
    echo ""
    echo -e "${BLUE}Options:${NC}"
    echo "  --low       Include LOW, MEDIUM, and HIGH severity issues"
    echo "  --medium    Include MEDIUM and HIGH severity issues only"
    echo "  --high      Include HIGH severity issues only"
    echo "  --help      Show this help message"
    echo ""
    echo -e "${BLUE}Arguments:${NC}"
    echo "  REPO_PATH   Path to the Go repository (default: current directory)"
    echo ""
    echo -e "${BLUE}Examples:${NC}"
    echo "  $0                        # Current dir, all severities"
    echo "  $0 --high                 # Current dir, high severity only"
    echo "  $0 --medium ./my-project  # Specific path, medium+ severity"
    echo "  $0 /path/to/repo          # Specific path, all severities"
    echo ""
    exit 0
}

# Parse arguments
SEVERITY=""
SEVERITY_LABEL="ALL"
REPO_PATH=""

# Parse all arguments
while [[ $# -gt 0 ]]; do
    case "$1" in
        --low)
            SEVERITY="-severity low"
            SEVERITY_LABEL="LOW+"
            shift
            ;;
        --medium)
            SEVERITY="-severity medium"
            SEVERITY_LABEL="MEDIUM+"
            shift
            ;;
        --high)
            SEVERITY="-severity high"
            SEVERITY_LABEL="HIGH"
            shift
            ;;
        --help|-h)
            show_help
            ;;
        -*)
            echo -e "${RED}Error: Unknown option '$1'${NC}"
            echo "Use --help for usage information"
            exit 1
            ;;
        *)
            # Assume it's the repo path
            REPO_PATH="$1"
            shift
            ;;
    esac
done

# Set default repo path to current directory
if [ -z "$REPO_PATH" ]; then
    REPO_PATH="."
fi

# Resolve to absolute path and validate
if [ ! -d "$REPO_PATH" ]; then
    echo -e "${RED}Error: Directory '$REPO_PATH' does not exist${NC}"
    exit 1
fi

REPO_PATH=$(cd "$REPO_PATH" && pwd)

# Extract repo name from path
REPO_NAME=$(basename "$REPO_PATH")

# Output files in the repo directory
OUTPUT_JSON="$REPO_PATH/gosec-results.json"
OUTPUT_HTML="$REPO_PATH/gosec-report.html"

# Check if gosec is installed
if [ ! -f "$GOSEC_PATH" ]; then
    echo -e "${YELLOW}⚠ Gosec not found. Installing...${NC}"
    curl -sfL https://raw.githubusercontent.com/securego/gosec/master/install.sh | sh -s -- -b "$(go env GOPATH)/bin"
    echo -e "${GREEN}✓ Gosec installed successfully${NC}"
fi

# Get gosec version
GOSEC_VERSION=$("$GOSEC_PATH" --version 2>&1 | head -1 || echo "unknown")
echo -e "${BLUE}Gosec Version:${NC} $GOSEC_VERSION"
echo -e "${BLUE}Repository:${NC} $REPO_NAME ($REPO_PATH)"
echo -e "${BLUE}Severity Filter:${NC} $SEVERITY_LABEL"
echo -e "${BLUE}Output:${NC} gosec-results.json → gosec-report.html"
echo ""

# Run gosec
echo -e "${CYAN}▶ Running security scan on ${REPO_NAME}...${NC}"
echo ""

# Build the command (run from repo directory)
CMD="$GOSEC_PATH -fmt=json -out=$OUTPUT_JSON $SEVERITY ./..."

echo -e "${YELLOW}Command: $CMD${NC}"
echo ""

# Run gosec from the repo directory (allow non-zero exit code as it returns 1 when issues found)
pushd "$REPO_PATH" > /dev/null
$GOSEC_PATH -fmt=json -out="$OUTPUT_JSON" $SEVERITY ./... 2>&1 || true
popd > /dev/null

# Check if output file was created
if [ ! -f "$OUTPUT_JSON" ]; then
    echo -e "${RED}✗ Failed to generate results${NC}"
    exit 1
fi

# Parse results for summary
TOTAL_ISSUES=$(jq '.Stats.found // 0' "$OUTPUT_JSON" 2>/dev/null || echo "0")
TOTAL_FILES=$(jq '.Stats.files // 0' "$OUTPUT_JSON" 2>/dev/null || echo "0")
TOTAL_LINES=$(jq '.Stats.lines // 0' "$OUTPUT_JSON" 2>/dev/null || echo "0")

HIGH_COUNT=$(jq '[.Issues[] | select(.severity == "HIGH")] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")
MEDIUM_COUNT=$(jq '[.Issues[] | select(.severity == "MEDIUM")] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")
LOW_COUNT=$(jq '[.Issues[] | select(.severity == "LOW")] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")

# Calculate priority counts based on Severity × Confidence matrix
# CRITICAL: HIGH severity + HIGH confidence (fix immediately)
# HIGH: HIGH+MEDIUM or MEDIUM+HIGH (fix soon)
# MEDIUM: HIGH+LOW or MEDIUM+MEDIUM (investigate/plan)
# LOW: MEDIUM+LOW or LOW+HIGH (review when time permits)
# INFO: LOW+MEDIUM or LOW+LOW (noise/false positive)

CRITICAL_COUNT=$(jq '[.Issues[] | select(.severity == "HIGH" and .confidence == "HIGH")] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")
HIGH_PRIORITY_COUNT=$(jq '[.Issues[] | select((.severity == "HIGH" and .confidence == "MEDIUM") or (.severity == "MEDIUM" and .confidence == "HIGH"))] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")
MEDIUM_PRIORITY_COUNT=$(jq '[.Issues[] | select((.severity == "HIGH" and .confidence == "LOW") or (.severity == "MEDIUM" and .confidence == "MEDIUM"))] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")
LOW_PRIORITY_COUNT=$(jq '[.Issues[] | select((.severity == "MEDIUM" and .confidence == "LOW") or (.severity == "LOW" and .confidence == "HIGH"))] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")
INFO_COUNT=$(jq '[.Issues[] | select((.severity == "LOW" and .confidence == "MEDIUM") or (.severity == "LOW" and .confidence == "LOW"))] | length' "$OUTPUT_JSON" 2>/dev/null || echo "0")

echo ""
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${CYAN}                        SCAN RESULTS                           ${NC}"
echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  📁 Files Scanned:    ${BLUE}$TOTAL_FILES${NC}"
echo -e "  📝 Lines of Code:    ${BLUE}$TOTAL_LINES${NC}"
echo ""
echo -e "${CYAN}  ┌─────────────────────────────────────────────────────────┐${NC}"
echo -e "${CYAN}  │              PRIORITY (Severity × Confidence)          │${NC}"
echo -e "${CYAN}  ├─────────────────────────────────────────────────────────┤${NC}"
echo -e "  │  🔴 CRITICAL (High+High):     ${RED}$(printf '%3d' $CRITICAL_COUNT)${NC}  ← Fix immediately   │"
echo -e "  │  🟠 HIGH (High+Med/Med+High): ${YELLOW}$(printf '%3d' $HIGH_PRIORITY_COUNT)${NC}  ← Fix soon         │"
echo -e "  │  🟡 MEDIUM (High+Low/Med+Med):${YELLOW}$(printf '%3d' $MEDIUM_PRIORITY_COUNT)${NC}  ← Investigate      │"
echo -e "  │  🟢 LOW (Med+Low/Low+High):   ${GREEN}$(printf '%3d' $LOW_PRIORITY_COUNT)${NC}  ← Review if time   │"
echo -e "  │  ⚪ INFO (Low+Med/Low+Low):   ${BLUE}$(printf '%3d' $INFO_COUNT)${NC}  ← Likely noise      │"
echo -e "${CYAN}  └─────────────────────────────────────────────────────────┘${NC}"
echo ""
echo -e "  ${CYAN}By Severity:${NC}"
echo -e "    High: ${RED}$HIGH_COUNT${NC}  Medium: ${YELLOW}$MEDIUM_COUNT${NC}  Low: ${GREEN}$LOW_COUNT${NC}"
echo ""
echo -e "  📊 Total Issues:     ${CYAN}$TOTAL_ISSUES${NC}"
echo ""

# Show action required
if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo -e "${RED}  ⚠️  ACTION REQUIRED: $CRITICAL_COUNT critical issue(s) need immediate attention!${NC}"
    echo ""
elif [ "$HIGH_PRIORITY_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}  ⚠️  ACTION RECOMMENDED: $HIGH_PRIORITY_COUNT high priority issue(s) should be fixed soon.${NC}"
    echo ""
fi

# Generate HTML report
echo -e "${CYAN}▶ Generating HTML report...${NC}"

cat > "$OUTPUT_HTML" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Gosec Security Report</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
            background: #0d1117; color: #c9d1d9; line-height: 1.6; padding: 20px;
        }
        .container { max-width: 1400px; margin: 0 auto; }
        h1 { color: #58a6ff; margin-bottom: 10px; font-size: 28px; }
        .subtitle { color: #8b949e; margin-bottom: 30px; }
        .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); gap: 15px; margin-bottom: 30px; }
        .stat-card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 20px; text-align: center; }
        .stat-card .number { font-size: 32px; font-weight: bold; }
        .stat-card .label { color: #8b949e; font-size: 14px; }
        .stat-card.high .number { color: #f85149; }
        .stat-card.medium .number { color: #d29922; }
        .stat-card.low .number { color: #3fb950; }
        .stat-card.info .number { color: #58a6ff; }
        .stat-card.critical .number { color: #ff6b6b; }
        .stat-card.priority-high .number { color: #ffa94d; }
        .summary-table { background: #161b22; border: 1px solid #30363d; border-radius: 8px; margin-bottom: 30px; overflow: hidden; }
        .summary-table h2 { padding: 15px 20px; background: #21262d; border-bottom: 1px solid #30363d; font-size: 16px; }
        .summary-table table { width: 100%; border-collapse: collapse; }
        .summary-table th, .summary-table td { padding: 12px 20px; text-align: left; border-bottom: 1px solid #21262d; }
        .summary-table th { background: #161b22; color: #8b949e; font-weight: 500; }
        .summary-table tbody tr { cursor: pointer; transition: all 0.2s; }
        .summary-table tbody tr:hover { background: #1c2128; transform: translateX(4px); }
        .summary-table tbody tr:active { background: #252d38; }
        .click-hint { color: #484f58; font-size: 11px; margin-left: 8px; }
        .info-icon { cursor: pointer; color: #58a6ff; margin-left: 8px; font-size: 14px; opacity: 0.7; }
        .info-icon:hover { opacity: 1; }
        .filter-bar { display: flex; gap: 10px; margin-bottom: 20px; flex-wrap: wrap; }
        .filter-btn { padding: 8px 16px; border: 1px solid #30363d; background: #21262d; color: #c9d1d9; border-radius: 6px; cursor: pointer; font-size: 14px; transition: all 0.2s; }
        .filter-btn:hover { background: #30363d; }
        .filter-btn.active { background: #238636; border-color: #238636; }
        .issue-card { background: #161b22; border: 1px solid #30363d; border-radius: 8px; margin-bottom: 15px; overflow: hidden; }
        .issue-header { padding: 15px 20px; display: flex; align-items: center; gap: 15px; border-bottom: 1px solid #30363d; flex-wrap: wrap; }
        .severity-badge { padding: 4px 12px; border-radius: 20px; font-size: 12px; font-weight: 600; text-transform: uppercase; }
        .severity-HIGH { background: #f8514922; color: #f85149; border: 1px solid #f85149; }
        .severity-MEDIUM { background: #d2992222; color: #d29922; border: 1px solid #d29922; }
        .severity-LOW { background: #3fb95022; color: #3fb950; border: 1px solid #3fb950; }
        .priority-badge { padding: 4px 10px; border-radius: 4px; font-size: 11px; font-weight: 600; margin-left: auto; }
        .priority-CRITICAL { background: #ff6b6b33; color: #ff6b6b; border: 1px solid #ff6b6b; }
        .priority-HIGH { background: #ffa94d33; color: #ffa94d; border: 1px solid #ffa94d; }
        .priority-MEDIUM { background: #ffd43b33; color: #ffd43b; border: 1px solid #ffd43b; }
        .priority-LOW { background: #69db7c33; color: #69db7c; border: 1px solid #69db7c; }
        .priority-INFO { background: #4dabf733; color: #4dabf7; border: 1px solid #4dabf7; }
        .confidence-badge { padding: 4px 10px; border-radius: 4px; font-size: 11px; background: #21262d; color: #8b949e; }
        .rule-id { font-family: monospace; background: #21262d; padding: 4px 8px; border-radius: 4px; color: #58a6ff; cursor: pointer; transition: all 0.2s; }
        .rule-id:hover { background: #388bfd; color: #fff; }
        .cwe-link { color: #8b949e; text-decoration: none; font-size: 13px; }
        .cwe-link:hover { color: #58a6ff; text-decoration: underline; }
        .issue-details { padding: 15px 20px; font-size: 15px; color: #e6edf3; }
        .issue-location { padding: 10px 20px; background: #0d1117; border-top: 1px solid #30363d; font-family: monospace; font-size: 13px; color: #8b949e; }
        .issue-location .file { color: #58a6ff; }
        .issue-location .line { color: #d29922; }
        .code-preview { background: #0d1117; border-top: 1px solid #30363d; overflow-x: auto; }
        .code-preview pre { margin: 0; padding: 15px 20px; font-family: 'SF Mono', Monaco, monospace; font-size: 13px; line-height: 1.5; white-space: pre-wrap; word-break: break-all; }
        .autofix { padding: 12px 20px; background: #1c3a2a; border-top: 1px solid #238636; font-size: 13px; color: #3fb950; }
        .autofix::before { content: "💡 "; }
        .no-issues { text-align: center; padding: 60px 20px; background: #161b22; border: 1px solid #30363d; border-radius: 8px; }
        .no-issues h2 { color: #3fb950; margin-bottom: 10px; }
        .footer { margin-top: 40px; padding-top: 20px; border-top: 1px solid #30363d; text-align: center; color: #8b949e; font-size: 13px; }
        .popup-overlay { display: none; position: fixed; top: 0; left: 0; width: 100%; height: 100%; background: rgba(0,0,0,0.7); z-index: 1000; justify-content: center; align-items: center; }
        .popup-overlay.active { display: flex; }
        .popup { background: #161b22; border: 1px solid #30363d; border-radius: 12px; max-width: 600px; width: 90%; max-height: 80vh; overflow-y: auto; box-shadow: 0 8px 32px rgba(0,0,0,0.4); animation: popupIn 0.2s ease-out; }
        @keyframes popupIn { from { opacity: 0; transform: scale(0.95) translateY(-10px); } to { opacity: 1; transform: scale(1) translateY(0); } }
        .popup-header { padding: 20px; border-bottom: 1px solid #30363d; display: flex; justify-content: space-between; align-items: center; }
        .popup-header h3 { display: flex; align-items: center; gap: 12px; font-size: 18px; color: #e6edf3; }
        .popup-close { background: none; border: none; color: #8b949e; font-size: 24px; cursor: pointer; padding: 5px; line-height: 1; }
        .popup-close:hover { color: #f85149; }
        .popup-body { padding: 20px; }
        .popup-section { margin-bottom: 20px; }
        .popup-section:last-child { margin-bottom: 0; }
        .popup-section h4 { color: #8b949e; font-size: 12px; text-transform: uppercase; letter-spacing: 0.5px; margin-bottom: 8px; }
        .popup-section p { color: #c9d1d9; line-height: 1.6; }
        .popup-section pre { background: #0d1117; padding: 15px; border-radius: 8px; overflow-x: auto; font-family: 'SF Mono', Monaco, monospace; font-size: 13px; line-height: 1.5; }
        .popup-tags { display: flex; gap: 8px; flex-wrap: wrap; }
        .popup-tag { padding: 4px 10px; border-radius: 4px; font-size: 12px; background: #21262d; }
        .popup-tag.severity-high { background: #f8514922; color: #f85149; }
        .popup-tag.severity-medium { background: #d2992222; color: #d29922; }
        .popup-tag.severity-low { background: #3fb95022; color: #3fb950; }
        .popup-link { display: inline-flex; align-items: center; gap: 6px; color: #58a6ff; text-decoration: none; padding: 8px 16px; background: #21262d; border-radius: 6px; font-size: 14px; margin-top: 10px; }
        .popup-link:hover { background: #30363d; }
        .loading { text-align: center; padding: 60px; color: #8b949e; }
        
        /* Popup Issues List Styles */
        .popup-issues-list { padding: 0; }
        .popup-issue-item { border-bottom: 1px solid #30363d; padding: 15px 20px; transition: background 0.2s; }
        .popup-issue-item:hover { background: #1c2128; }
        .popup-issue-item:last-child { border-bottom: none; }
        .popup-issue-header { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; flex-wrap: wrap; }
        .issue-number { color: #484f58; font-size: 12px; font-weight: 600; min-width: 30px; }
        .popup-issue-location { display: flex; align-items: center; gap: 15px; margin-bottom: 10px; font-family: monospace; font-size: 13px; }
        .popup-issue-location .file { color: #58a6ff; }
        .popup-issue-location .line { color: #d29922; }
        .popup-issue-code { background: #0d1117; border-radius: 6px; overflow: hidden; margin-bottom: 8px; }
        .popup-issue-code pre { margin: 0; padding: 12px 15px; font-family: 'SF Mono', Monaco, monospace; font-size: 12px; line-height: 1.4; overflow-x: auto; white-space: pre-wrap; word-break: break-all; }
        .popup-issue-fix { background: #1c3a2a; padding: 10px 15px; border-radius: 6px; font-size: 12px; color: #3fb950; }
    </style>
</head>
<body>
    <div class="container">
        <h1>🔒 SAST Security Check via Gosec</h1>
        <p class="subtitle" id="subtitle">Loading...</p>
        
        <div class="stats" id="stats"></div>
        
        <div class="summary-table" id="summaryTable" style="display:none;">
            <h2>📊 Issues by Rule <span style="font-weight:normal;color:#8b949e;font-size:13px;margin-left:10px;">Click a row to view details</span></h2>
            <table>
                <thead><tr><th style="width:120px;">Rule ID</th><th>Description</th><th style="width:100px;">Severity</th><th style="width:100px;">Priority</th><th style="width:70px;">Count</th></tr></thead>
                <tbody id="summaryBody"></tbody>
            </table>
        </div>
        
        <div id="issuesContainer" style="display:none;"></div>
        
        <div class="footer" id="footer"></div>
    </div>
    
    <!-- Rule Info Popup (for ? icon) -->
    <div class="popup-overlay" id="rulePopup">
        <div class="popup">
            <div class="popup-header">
                <h3><span class="rule-id" id="popupRuleId"></span><span id="popupRuleName"></span></h3>
                <button class="popup-close" onclick="closePopup()">&times;</button>
            </div>
            <div class="popup-body" id="popupBody"></div>
        </div>
    </div>
    
    <!-- Issues List Popup (for clicking on rule row) -->
    <div class="popup-overlay" id="issuesPopup">
        <div class="popup" style="max-width: 900px; max-height: 85vh;">
            <div class="popup-header">
                <h3>
                    <span class="rule-id" id="issuesPopupRuleId"></span>
                    <span id="issuesPopupTitle"></span>
                    <span id="issuesPopupCount" style="color:#8b949e;font-weight:normal;font-size:14px;margin-left:10px;"></span>
                </h3>
                <button class="popup-close" onclick="closeIssuesPopup()">&times;</button>
            </div>
            <div class="popup-body" id="issuesPopupBody" style="max-height: 70vh; overflow-y: auto; padding: 0;"></div>
        </div>
    </div>
    
    <script>
        const ruleInfo = {
            'G101': { name: 'Hardcoded Credentials', severity: 'HIGH', description: 'Detects potential hardcoded credentials, passwords, API keys, or tokens in source code.', whatItChecks: ['Variable names containing: password, passwd, secret, token, apikey', 'String literals that look like credentials'], fix: '// Use environment variables\napiKey := os.Getenv("API_KEY")', cwe: { id: '798', name: 'Use of Hard-coded Credentials' } },
            'G102': { name: 'Bind to All Interfaces', severity: 'MEDIUM', description: 'Detects when a server binds to all network interfaces (0.0.0.0).', whatItChecks: ['net.Listen() with 0.0.0.0', 'http.ListenAndServe() with empty address'], fix: 'http.ListenAndServe("127.0.0.1:8080", handler)', cwe: { id: '200', name: 'Exposure of Sensitive Information' } },
            'G104': { name: 'Unhandled Errors', severity: 'LOW', description: 'Detects when errors returned by functions are not checked.', whatItChecks: ['Function calls returning error', 'Errors assigned to _'], fix: 'if err := doSomething(); err != nil {\n    return err\n}', cwe: { id: '703', name: 'Improper Check of Exceptional Conditions' } },
            'G112': { name: 'Slowloris Attack', severity: 'MEDIUM', description: 'Detects HTTP servers without ReadHeaderTimeout configured.', whatItChecks: ['http.Server without ReadHeaderTimeout'], fix: 'server := &http.Server{\n    ReadHeaderTimeout: 10 * time.Second,\n}', cwe: { id: '400', name: 'Uncontrolled Resource Consumption' } },
            'G115': { name: 'Integer Overflow', severity: 'HIGH', description: 'Detects integer type conversions that could overflow.', whatItChecks: ['int64 → int32 conversions', 'int → int32 conversions'], fix: 'if val > math.MaxInt32 {\n    return errors.New("overflow")\n}', cwe: { id: '190', name: 'Integer Overflow' } },
            'G201': { name: 'SQL Injection', severity: 'HIGH', description: 'Detects SQL queries built using string concatenation.', whatItChecks: ['String concatenation in SQL', 'fmt.Sprintf in queries'], fix: 'db.Query("SELECT * FROM users WHERE id = $1", id)', cwe: { id: '89', name: 'SQL Injection' } },
            'G304': { name: 'Path Traversal', severity: 'MEDIUM', description: 'Detects file operations where path comes from a variable.', whatItChecks: ['os.Open() with variable paths', 'filepath.Join() with untrusted input'], fix: 'cleanPath := filepath.Clean(input)\nif !strings.HasPrefix(cleanPath, allowedDir) {\n    return err\n}', cwe: { id: '22', name: 'Path Traversal' } },
            'G306': { name: 'Insecure File Permissions', severity: 'MEDIUM', description: 'Detects file creation with overly permissive permissions.', whatItChecks: ['os.WriteFile() with permissions > 0600'], fix: 'os.WriteFile("file", data, 0600)', cwe: { id: '276', name: 'Incorrect Default Permissions' } },
            'G402': { name: 'TLS InsecureSkipVerify', severity: 'HIGH', description: 'Detects TLS with InsecureSkipVerify set to true.', whatItChecks: ['tls.Config with InsecureSkipVerify: true'], fix: 'tlsConfig := &tls.Config{\n    MinVersion: tls.VersionTLS12,\n}', cwe: { id: '295', name: 'Improper Certificate Validation' } },
            'G404': { name: 'Weak Random', severity: 'HIGH', description: 'Detects use of math/rand instead of crypto/rand.', whatItChecks: ['math/rand package usage'], fix: 'import "crypto/rand"\nbytes := make([]byte, 16)\nrand.Read(bytes)', cwe: { id: '338', name: 'Use of Weak PRNG' } }
        };

        // Embedded JSON data (injected by sast-check.sh)
        const reportData = __GOSEC_JSON_DATA_PLACEHOLDER__;

        function loadReport() {
            try {
                renderReport(reportData);
            } catch (e) {
                document.getElementById('issuesContainer').innerHTML = '<div class="loading">Error loading report: ' + e.message + '</div>';
            }
        }

        // Repository name (injected by sast-check.sh)
        const repoName = '__REPO_NAME_PLACEHOLDER__';
        
        // Priority order for sorting
        const priorityOrder = { 'CRITICAL': 0, 'HIGH': 1, 'MEDIUM': 2, 'LOW': 3, 'INFO': 4 };
        
        // Priority calculation based on Severity × Confidence matrix
        function calculatePriority(severity, confidence) {
            if (severity === 'HIGH' && confidence === 'HIGH') return 'CRITICAL';
            if ((severity === 'HIGH' && confidence === 'MEDIUM') || (severity === 'MEDIUM' && confidence === 'HIGH')) return 'HIGH';
            if ((severity === 'HIGH' && confidence === 'LOW') || (severity === 'MEDIUM' && confidence === 'MEDIUM')) return 'MEDIUM';
            if ((severity === 'MEDIUM' && confidence === 'LOW') || (severity === 'LOW' && confidence === 'HIGH')) return 'LOW';
            return 'INFO';
        }
        
        function getPriorityLabel(priority) {
            const labels = {
                'CRITICAL': '🔴 Fix Immediately',
                'HIGH': '🟠 Fix Soon',
                'MEDIUM': '🟡 Investigate',
                'LOW': '🟢 Review If Time',
                'INFO': '⚪ Likely Noise'
            };
            return labels[priority] || priority;
        }

        function renderReport(data) {
            const issues = data.Issues || [];
            const stats = data.Stats || {};
            const version = data.GosecVersion || 'unknown';
            
            // Add priority to each issue
            issues.forEach(issue => {
                issue.priority = calculatePriority(issue.severity, issue.confidence);
            });
            
            document.getElementById('subtitle').textContent = `${repoName} • Gosec v${version} • ${new Date().toLocaleDateString()}`;
            
            // Count by severity
            const highCount = issues.filter(i => i.severity === 'HIGH').length;
            const mediumCount = issues.filter(i => i.severity === 'MEDIUM').length;
            const lowCount = issues.filter(i => i.severity === 'LOW').length;
            
            // Count by priority
            const criticalCount = issues.filter(i => i.priority === 'CRITICAL').length;
            const highPriorityCount = issues.filter(i => i.priority === 'HIGH').length;
            const mediumPriorityCount = issues.filter(i => i.priority === 'MEDIUM').length;
            const lowPriorityCount = issues.filter(i => i.priority === 'LOW').length;
            const infoCount = issues.filter(i => i.priority === 'INFO').length;
            
            document.getElementById('stats').innerHTML = `
                <div class="stat-card info"><div class="number">${stats.files || 0}</div><div class="label">Files Scanned</div></div>
                <div class="stat-card info"><div class="number">${(stats.lines || 0).toLocaleString()}</div><div class="label">Lines of Code</div></div>
                <div class="stat-card critical"><div class="number">${criticalCount}</div><div class="label">🔴 Critical</div></div>
                <div class="stat-card priority-high"><div class="number">${highPriorityCount}</div><div class="label">🟠 High Priority</div></div>
                <div class="stat-card medium"><div class="number">${mediumPriorityCount}</div><div class="label">🟡 Medium</div></div>
                <div class="stat-card low"><div class="number">${lowPriorityCount + infoCount}</div><div class="label">🟢 Low/Info</div></div>
            `;
            
            // Summary by rule
            const ruleGroups = {};
            issues.forEach(issue => {
                if (!ruleGroups[issue.rule_id]) {
                    ruleGroups[issue.rule_id] = { count: 0, severity: issue.severity, confidence: issue.confidence, details: issue.details };
                }
                ruleGroups[issue.rule_id].count++;
            });
            
            if (Object.keys(ruleGroups).length > 0) {
                document.getElementById('summaryTable').style.display = 'block';
                // Sort by highest priority first
                const sortedRules = Object.entries(ruleGroups).sort((a, b) => {
                    const priorityA = calculatePriority(a[1].severity, a[1].confidence);
                    const priorityB = calculatePriority(b[1].severity, b[1].confidence);
                    return priorityOrder[priorityA] - priorityOrder[priorityB];
                });
                document.getElementById('summaryBody').innerHTML = sortedRules
                    .map(([rule, info]) => {
                        const priority = calculatePriority(info.severity, info.confidence);
                        return `
                        <tr onclick="showIssuesForRule('${rule}')">
                            <td>
                                <span class="rule-id">${rule}</span>
                                <span class="info-icon" onclick="event.stopPropagation(); showRuleInfo('${rule}')" title="Learn about this rule">ⓘ</span>
                            </td>
                            <td>${info.details}<span class="click-hint">Click to view issues →</span></td>
                            <td><span class="severity-badge severity-${info.severity}">${info.severity}</span></td>
                            <td><span class="priority-badge priority-${priority}">${priority}</span></td>
                            <td>${info.count}</td>
                        </tr>
                    `}).join('');
            }
            
            // Store issues globally for popup access
            window.allIssues = issues;
            
            // Show "no issues" message if empty
            if (issues.length === 0) {
                document.getElementById('summaryTable').innerHTML = '<div class="no-issues"><h2>✅ No Security Issues Found</h2><p>Great job! Your code passed all security checks.</p></div>';
            }
            
            document.getElementById('footer').innerHTML = `Generated on ${new Date().toLocaleString()} • Gosec v${version} • ${stats.files || 0} files • ${(stats.lines || 0).toLocaleString()} lines<br><span style="color:#484f58">Click on any rule row to view detailed issues</span><br><span style="color:#58a6ff;margin-top:8px;display:inline-block;">Developed by dhanibaharzah</span>`;
        }

        function escapeHtml(text) {
            const div = document.createElement('div');
            div.textContent = text;
            return div.innerHTML;
        }

        function showRuleInfo(ruleId) {
            const rule = ruleInfo[ruleId];
            if (!rule) { alert('No info for ' + ruleId); return; }
            document.getElementById('popupRuleId').textContent = ruleId;
            document.getElementById('popupRuleName').textContent = rule.name;
            document.getElementById('popupBody').innerHTML = `
                <div class="popup-section"><div class="popup-tags">
                    <span class="popup-tag severity-${rule.severity.toLowerCase()}">${rule.severity}</span>
                    <span class="popup-tag">CWE-${rule.cwe.id}</span>
                </div></div>
                <div class="popup-section"><h4>Description</h4><p>${rule.description}</p></div>
                <div class="popup-section"><h4>What It Checks</h4><ul style="margin-left:20px">${rule.whatItChecks.map(c => '<li>'+c+'</li>').join('')}</ul></div>
                <div class="popup-section"><h4>How To Fix</h4><pre>${escapeHtml(rule.fix)}</pre></div>
                <div class="popup-section"><a class="popup-link" href="https://cwe.mitre.org/data/definitions/${rule.cwe.id}.html" target="_blank">📖 CWE-${rule.cwe.id}: ${rule.cwe.name}</a></div>
            `;
            document.getElementById('rulePopup').classList.add('active');
        }

        function closePopup() { document.getElementById('rulePopup').classList.remove('active'); }
        function closeIssuesPopup() { document.getElementById('issuesPopup').classList.remove('active'); }
        
        function showIssuesForRule(ruleId) {
            const issues = window.allIssues.filter(i => i.rule_id === ruleId);
            const ruleData = ruleInfo[ruleId] || { name: ruleId };
            
            document.getElementById('issuesPopupRuleId').textContent = ruleId;
            document.getElementById('issuesPopupTitle').textContent = ruleData.name || 'Security Issue';
            document.getElementById('issuesPopupCount').textContent = `(${issues.length} issue${issues.length !== 1 ? 's' : ''})`;
            
            // Sort by priority
            issues.sort((a, b) => priorityOrder[a.priority] - priorityOrder[b.priority]);
            
            let html = `
                <div style="padding: 15px 20px; background: #21262d; border-bottom: 1px solid #30363d; display: flex; gap: 10px; flex-wrap: wrap;">
                    <button class="filter-btn active" onclick="filterPopupIssues('all', this)">All (${issues.length})</button>
            `;
            
            // Add priority filter buttons
            const priorityCounts = {};
            issues.forEach(i => { priorityCounts[i.priority] = (priorityCounts[i.priority] || 0) + 1; });
            ['CRITICAL', 'HIGH', 'MEDIUM', 'LOW', 'INFO'].forEach(p => {
                if (priorityCounts[p]) {
                    const colors = { CRITICAL: '#ff6b6b', HIGH: '#ffa94d', MEDIUM: '#ffd43b', LOW: '#69db7c', INFO: '#4dabf7' };
                    html += `<button class="filter-btn" onclick="filterPopupIssues('${p}', this)" style="border-color:${colors[p]};color:${colors[p]}">${p} (${priorityCounts[p]})</button>`;
                }
            });
            html += '</div>';
            
            html += '<div class="popup-issues-list">';
            issues.forEach((issue, idx) => {
                const file = issue.file.replace(new RegExp('.*' + repoName + '/'), '');
                html += `
                    <div class="popup-issue-item" data-priority="${issue.priority}">
                        <div class="popup-issue-header">
                            <span class="issue-number">#${idx + 1}</span>
                            <span class="severity-badge severity-${issue.severity}">${issue.severity}</span>
                            <span class="confidence-badge">Confidence: ${issue.confidence}</span>
                            <span class="priority-badge priority-${issue.priority}">${getPriorityLabel(issue.priority)}</span>
                        </div>
                        <div class="popup-issue-location">
                            <span class="file">${file}</span>
                            <span class="line">Line ${issue.line}</span>
                            <a class="cwe-link" href="${issue.cwe.url}" target="_blank" onclick="event.stopPropagation()">CWE-${issue.cwe.id}</a>
                        </div>
                        <div class="popup-issue-code"><pre>${escapeHtml(issue.code)}</pre></div>
                        ${issue.autofix ? `<div class="popup-issue-fix">💡 ${issue.autofix}</div>` : ''}
                    </div>
                `;
            });
            html += '</div>';
            
            document.getElementById('issuesPopupBody').innerHTML = html;
            document.getElementById('issuesPopup').classList.add('active');
        }
        
        function filterPopupIssues(priority, btn) {
            document.querySelectorAll('#issuesPopupBody .filter-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');
            document.querySelectorAll('.popup-issue-item').forEach(item => {
                item.style.display = (priority === 'all' || item.dataset.priority === priority) ? 'block' : 'none';
            });
        }
        
        document.getElementById('rulePopup').onclick = e => { if (e.target.id === 'rulePopup') closePopup(); };
        document.getElementById('issuesPopup').onclick = e => { if (e.target.id === 'issuesPopup') closeIssuesPopup(); };
        document.onkeydown = e => { if (e.key === 'Escape') { closePopup(); closeIssuesPopup(); } };

        loadReport();
    </script>
</body>
</html>
HTMLEOF

# Inject the JSON data and repo name into the HTML file
# Use a temp file to handle the replacement safely
TEMP_HTML=$(mktemp)
JSON_CONTENT=$(cat "$OUTPUT_JSON")

# Use node if available for safer JSON embedding, otherwise use python/awk
if command -v node &> /dev/null; then
    node -e "
        const fs = require('fs');
        let html = fs.readFileSync('$OUTPUT_HTML', 'utf8');
        const json = fs.readFileSync('$OUTPUT_JSON', 'utf8');
        html = html.replace('__GOSEC_JSON_DATA_PLACEHOLDER__', json);
        html = html.replace('__REPO_NAME_PLACEHOLDER__', '$REPO_NAME');
        fs.writeFileSync('$OUTPUT_HTML', html);
    "
elif command -v python3 &> /dev/null; then
    python3 -c "
with open('$OUTPUT_HTML', 'r') as f:
    html = f.read()
with open('$OUTPUT_JSON', 'r') as f:
    data = f.read()
html = html.replace('__GOSEC_JSON_DATA_PLACEHOLDER__', data)
html = html.replace('__REPO_NAME_PLACEHOLDER__', '$REPO_NAME')
with open('$OUTPUT_HTML', 'w') as f:
    f.write(html)
"
else
    # Last resort: Use awk (handles special characters better than sed)
    awk -v jsonfile="$OUTPUT_JSON" -v reponame="$REPO_NAME" '
        BEGIN { 
            while ((getline line < jsonfile) > 0) {
                json = json (json ? "\n" : "") line
            }
            close(jsonfile)
        }
        {
            gsub(/__GOSEC_JSON_DATA_PLACEHOLDER__/, json)
            gsub(/__REPO_NAME_PLACEHOLDER__/, reponame)
            print
        }
    ' "$OUTPUT_HTML" > "$TEMP_HTML" && mv "$TEMP_HTML" "$OUTPUT_HTML"
fi

echo -e "${GREEN}✓ HTML report generated${NC}"

# Open in browser
echo -e "${CYAN}▶ Opening report in browser...${NC}"

# Detect OS and open browser
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    open "$OUTPUT_HTML" 2>/dev/null || open -a "Safari" "$OUTPUT_HTML" 2>/dev/null || echo -e "${YELLOW}Please open $OUTPUT_HTML manually${NC}"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    # Linux
    xdg-open "$OUTPUT_HTML" 2>/dev/null || sensible-browser "$OUTPUT_HTML" 2>/dev/null || echo -e "${YELLOW}Please open $OUTPUT_HTML manually${NC}"
elif [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "cygwin" ]]; then
    # Windows
    start "$OUTPUT_HTML" 2>/dev/null || echo -e "${YELLOW}Please open $OUTPUT_HTML manually${NC}"
else
    echo -e "${YELLOW}Please open $OUTPUT_HTML manually${NC}"
fi

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}                    ✓ SCAN COMPLETE                            ${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""
echo -e "  📂 Repository:  ${BLUE}$REPO_NAME${NC}"
echo -e "  📄 JSON Report: ${BLUE}$OUTPUT_JSON${NC}"
echo -e "  🌐 HTML Report: ${BLUE}$OUTPUT_HTML${NC}"
echo ""

# Exit with appropriate code based on priority
# Exit 2: CRITICAL issues found (High severity + High confidence)
# Exit 1: HIGH priority issues found (High+Medium or Medium+High)
# Exit 0: No critical/high priority issues
if [ "$CRITICAL_COUNT" -gt 0 ]; then
    echo -e "${RED}Exiting with code 2 (CRITICAL issues found)${NC}"
    exit 2
elif [ "$HIGH_PRIORITY_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}Exiting with code 1 (HIGH priority issues found)${NC}"
    exit 1
fi
exit 0
