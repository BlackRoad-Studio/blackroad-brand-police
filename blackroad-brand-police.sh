#!/bin/bash
# Brand Police - Design System Compliance Checker
# BlackRoad OS, Inc. © 2026

POLICE_DIR="$HOME/.blackroad/brand-police"
POLICE_DB="$POLICE_DIR/police.db"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Official BlackRoad Colors
OFFICIAL_AMBER="#F5A623"
OFFICIAL_HOT_PINK="#FF1D6C"
OFFICIAL_ELECTRIC_BLUE="#2979FF"
OFFICIAL_VIOLET="#9C27B0"

# Forbidden Colors (old system)
FORBIDDEN_COLORS=("#FF9D00" "#FF6B00" "#FF0066" "#FF006B" "#D600AA" "#7700FF" "#0066FF")

init() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     🎨 Brand Police - Design Compliance       ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

    mkdir -p "$POLICE_DIR/reports"

    # Create database
    sqlite3 "$POLICE_DB" <<'SQL'
-- Projects
CREATE TABLE IF NOT EXISTS projects (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT UNIQUE NOT NULL,
    path TEXT NOT NULL,
    type TEXT NOT NULL,              -- html, css, cloudflare
    compliant INTEGER DEFAULT 0,
    score INTEGER DEFAULT 0,         -- 0-100
    last_checked INTEGER,
    violations TEXT                  -- JSON array
);

-- Violations
CREATE TABLE IF NOT EXISTS violations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    type TEXT NOT NULL,              -- color, spacing, font, gradient
    severity TEXT NOT NULL,          -- critical, warning, info
    description TEXT,
    line_number INTEGER,
    detected_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

-- Fixes
CREATE TABLE IF NOT EXISTS brand_fixes (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    project_id INTEGER NOT NULL,
    violation_type TEXT NOT NULL,
    before_value TEXT,
    after_value TEXT,
    applied_at INTEGER NOT NULL,
    FOREIGN KEY (project_id) REFERENCES projects(id)
);

CREATE INDEX IF NOT EXISTS idx_projects_compliant ON projects(compliant);
CREATE INDEX IF NOT EXISTS idx_violations_project ON violations(project_id);

SQL

    echo -e "${GREEN}✓${NC} Brand Police initialized"
}

# Check HTML/CSS file
check_file() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        echo -e "${RED}Error: File not found: $file_path${NC}"
        return 1
    fi

    local filename=$(basename "$file_path")
    local timestamp=$(date +%s)

    echo -e "${CYAN}🔍 Checking: $filename${NC}"

    local violations=0
    local critical=0

    # Check for forbidden colors
    for color in "${FORBIDDEN_COLORS[@]}"; do
        if grep -qi "$color" "$file_path"; then
            echo -e "  ${RED}✗ CRITICAL:${NC} Forbidden color found: $color"
            violations=$((violations + 1))
            critical=$((critical + 1))
        fi
    done

    # Check for official colors
    local has_amber=$(grep -ci "$OFFICIAL_AMBER" "$file_path" || echo 0)
    local has_pink=$(grep -ci "$OFFICIAL_HOT_PINK" "$file_path" || echo 0)
    local has_blue=$(grep -ci "$OFFICIAL_ELECTRIC_BLUE" "$file_path" || echo 0)
    local has_violet=$(grep -ci "$OFFICIAL_VIOLET" "$file_path" || echo 0)

    if [ $has_amber -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Uses official Amber ($has_amber times)"
    fi
    if [ $has_pink -gt 0 ]; then
        echo -e "  ${GREEN}✓${NC} Uses official Hot Pink ($has_pink times)"
    fi

    # Check Golden Ratio
    if grep -qi "1.618" "$file_path"; then
        echo -e "  ${GREEN}✓${NC} Uses Golden Ratio (φ = 1.618)"
    else
        echo -e "  ${YELLOW}!${NC} Missing Golden Ratio spacing"
        violations=$((violations + 1))
    fi

    # Check for SF Pro Display font
    if grep -qi "SF Pro Display" "$file_path"; then
        echo -e "  ${GREEN}✓${NC} Uses SF Pro Display font"
    elif grep -qi "font-family" "$file_path"; then
        echo -e "  ${YELLOW}!${NC} Not using official font (SF Pro Display)"
        violations=$((violations + 1))
    fi

    # Check for proper gradient
    if grep -qi "linear-gradient.*135deg" "$file_path"; then
        echo -e "  ${GREEN}✓${NC} Uses correct gradient angle (135deg)"
    fi

    # Calculate compliance score
    local score=$((100 - (violations * 10)))
    if [ $score -lt 0 ]; then
        score=0
    fi

    local compliant=0
    if [ $critical -eq 0 ] && [ $score -ge 80 ]; then
        compliant=1
    fi

    # Store in database
    sqlite3 "$POLICE_DB" <<SQL
INSERT OR REPLACE INTO projects (name, path, type, compliant, score, last_checked, violations)
VALUES ('$filename', '$file_path', 'html', $compliant, $score, $timestamp, '$violations');
SQL

    echo -e "\n  ${PURPLE}Compliance Score:${NC} $score/100"

    if [ $compliant -eq 1 ]; then
        echo -e "  ${GREEN}✅ COMPLIANT${NC}\n"
    else
        echo -e "  ${RED}❌ NON-COMPLIANT${NC}\n"
    fi
}

# Auto-fix file
fix_file() {
    local file_path="$1"

    if [ ! -f "$file_path" ]; then
        echo -e "${RED}Error: File not found: $file_path${NC}"
        return 1
    fi

    local filename=$(basename "$file_path")
    echo -e "${CYAN}🔧 Fixing: $filename${NC}"

    # Create backup
    cp "$file_path" "$file_path.backup"

    local fixes=0

    # Replace forbidden colors with official ones
    for color in "${FORBIDDEN_COLORS[@]}"; do
        if grep -qi "$color" "$file_path"; then
            # Replace with Amber by default
            sed -i.tmp "s/$color/$OFFICIAL_AMBER/gi" "$file_path"
            echo -e "  ${GREEN}✓${NC} Replaced $color with official Amber"
            fixes=$((fixes + 1))
        fi
    done

    # Clean up temp file
    rm -f "$file_path.tmp"

    echo -e "\n${GREEN}✅ Applied $fixes fixes${NC}"
    echo -e "${YELLOW}Backup saved:${NC} $file_path.backup\n"

    # Update database
    local timestamp=$(date +%s)
    sqlite3 "$POLICE_DB" <<SQL
INSERT INTO brand_fixes (project_id, violation_type, before_value, after_value, applied_at)
SELECT id, 'color_replacement', 'forbidden_colors', 'official_colors', $timestamp
FROM projects WHERE name = '$filename';
SQL
}

# Scan directory
scan_dir() {
    local dir_path="${1:-.}"

    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     Scanning Directory                        ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

    local count=0
    local compliant=0

    # Find all HTML and CSS files
    find "$dir_path" -type f \( -name "*.html" -o -name "*.css" \) -not -path "*/node_modules/*" -not -path "*/.git/*" | while read -r file; do
        check_file "$file"
        count=$((count + 1))
    done

    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Scan complete!"
}

# Report
report() {
    echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
    echo -e "${PURPLE}║     🎨 Brand Compliance Report                ║${NC}"
    echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"

    local total=$(sqlite3 "$POLICE_DB" "SELECT COUNT(*) FROM projects" 2>/dev/null || echo 0)
    local compliant=$(sqlite3 "$POLICE_DB" "SELECT COUNT(*) FROM projects WHERE compliant = 1" 2>/dev/null || echo 0)
    local non_compliant=$(sqlite3 "$POLICE_DB" "SELECT COUNT(*) FROM projects WHERE compliant = 0" 2>/dev/null || echo 0)
    local avg_score=$(sqlite3 "$POLICE_DB" "SELECT AVG(score) FROM projects" 2>/dev/null || echo 0)
    local total_fixes=$(sqlite3 "$POLICE_DB" "SELECT COUNT(*) FROM brand_fixes" 2>/dev/null || echo 0)

    echo -e "${CYAN}📊 Statistics${NC}"
    echo -e "  ${GREEN}Total Projects:${NC} $total"
    echo -e "  ${GREEN}Compliant:${NC} $compliant"
    echo -e "  ${RED}Non-Compliant:${NC} $non_compliant"
    echo -e "  ${PURPLE}Average Score:${NC} $avg_score/100"
    echo -e "  ${PURPLE}Fixes Applied:${NC} $total_fixes"

    echo -e "\n${CYAN}🎨 Official Colors${NC}"
    echo -e "  ${GREEN}✓${NC} Amber: $OFFICIAL_AMBER"
    echo -e "  ${GREEN}✓${NC} Hot Pink: $OFFICIAL_HOT_PINK"
    echo -e "  ${GREEN}✓${NC} Electric Blue: $OFFICIAL_ELECTRIC_BLUE"
    echo -e "  ${GREEN}✓${NC} Violet: $OFFICIAL_VIOLET"

    echo -e "\n${CYAN}❌ Forbidden Colors${NC}"
    for color in "${FORBIDDEN_COLORS[@]}"; do
        echo -e "  ${RED}✗${NC} $color"
    done
}

# Main execution
case "${1:-help}" in
    init)
        init
        ;;
    check)
        check_file "$2"
        ;;
    fix)
        fix_file "$2"
        ;;
    scan)
        scan_dir "$2"
        ;;
    report)
        report
        ;;
    help|*)
        echo -e "${PURPLE}╔════════════════════════════════════════════════╗${NC}"
        echo -e "${PURPLE}║     🎨 Brand Police - Design Compliance       ║${NC}"
        echo -e "${PURPLE}╚════════════════════════════════════════════════╝${NC}\n"
        echo "Enforce BlackRoad design system compliance"
        echo ""
        echo "Usage: $0 COMMAND [OPTIONS]"
        echo ""
        echo "Setup:"
        echo "  init                    - Initialize Brand Police"
        echo ""
        echo "Operations:"
        echo "  check FILE              - Check single file"
        echo "  fix FILE                - Auto-fix violations"
        echo "  scan [DIR]              - Scan directory"
        echo "  report                  - Show compliance report"
        echo ""
        echo "Examples:"
        echo "  $0 check ~/project/index.html"
        echo "  $0 fix ~/project/index.html"
        echo "  $0 scan ~/projects"
        ;;
esac
