#!/bin/bash

# Graceful ODTE Test Runner with Signal Handling
# Usage: ./graceful_odte.sh [PROFILE] [DURATION]

set -e

# Default values
PROFILE="${1:-auto}"
DURATION="${2:-1800}"
CLEANUP_DONE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Function to perform graceful cleanup
graceful_cleanup() {
    if [ "$CLEANUP_DONE" = true ]; then
        return
    fi
    
    CLEANUP_DONE=true
    log "🛑 Received interrupt signal - performing graceful shutdown..."
    
    # Stop ODTE process if running
    if [ ! -z "$ODTE_PID" ] && kill -0 "$ODTE_PID" 2>/dev/null; then
        log "📊 Stopping ODTE data collection (PID: $ODTE_PID)..."
        kill -TERM "$ODTE_PID" 2>/dev/null || true
        
        # Wait up to 30 seconds for graceful termination
        local countdown=30
        while [ $countdown -gt 0 ] && kill -0 "$ODTE_PID" 2>/dev/null; do
            echo -n "⏳ Waiting for graceful termination... ${countdown}s"
            sleep 1
            countdown=$((countdown - 1))
            echo -ne "\r"
        done
        echo ""
        
        # Force kill if still running
        if kill -0 "$ODTE_PID" 2>/dev/null; then
            warn "Force terminating ODTE process..."
            kill -KILL "$ODTE_PID" 2>/dev/null || true
        fi
    fi
    
    # Stop filter process if running
    if [ ! -z "$FILTER_PID" ] && kill -0 "$FILTER_PID" 2>/dev/null; then
        log "🔧 Stopping filter application..."
        kill -TERM "$FILTER_PID" 2>/dev/null || true
        wait "$FILTER_PID" 2>/dev/null || true
    fi
    
    # Find the test directory
    log "📁 Locating test results..."

    # Resolve the real results directory (follow symlink if present)
    if [ -L results ]; then
        RESULTS_DIR=$(readlink -f results)
    else
        RESULTS_DIR="results"
    fi

    # Try to locate the test dir with a small retry loop to avoid races
    test_dir=""
    for i in $(seq 1 10); do
        test_dir=$(find "$RESULTS_DIR" -name "test_*_${ACTUAL_PROFILE}" -type d 2>/dev/null | sort | tail -1)
        if [ -n "$test_dir" ]; then
            break
        fi
        sleep 1
    done

    if [ -z "$test_dir" ]; then
        error "No test directory found for profile ${ACTUAL_PROFILE} (searched: $RESULTS_DIR)"
        exit 1
    fi
    
    log "📊 Processing partial results in: $test_dir"
    
    # Create reports directory if it doesn't exist
    local reports_dir="$test_dir/generated_reports"
    mkdir -p "$reports_dir"
    
    # Generate timestamp for partial results
    local partial_timestamp=$(date '+%Y%m%d_%H%M%S')
    echo "partial_test_interrupted_at_${partial_timestamp}" > "$test_dir/PARTIAL_TEST_MARKER"
    
    # Try to run analysis on partial data
    log "📈 Running analysis on partial data..."
    
    # Latency analysis
    if python3 scripts/reports/report_generators/latency_analysis.py "$reports_dir" 2>/dev/null; then
        success "✅ Latency analysis completed"
    else
        warn "⚠️ Latency analysis failed (insufficient data?)"
    fi
    
    # Standard analysis
    if make analyze REPORTS_DIR="$reports_dir" 2>/dev/null; then
        success "✅ Standard analysis completed"
    else
        warn "⚠️ Standard analysis failed"
    fi
    
    # Plot generation
    if make plots REPORTS_DIR="$reports_dir" 2>/dev/null; then
        success "✅ Plots generated"
    else
        warn "⚠️ Plot generation failed"
    fi
    
    # Intelligent analysis
    if python3 scripts/reports/report_generators/intelligent_test_analysis.py "$test_dir" 2>/dev/null; then
        success "✅ Intelligent analysis completed"
    else
        warn "⚠️ Intelligent analysis failed"
    fi
    
    # Generate partial summary
    log "📋 Generating partial test summary..."
    if [ -f "scripts/show_test_summary.sh" ]; then
        bash scripts/show_test_summary.sh "$reports_dir" || warn "Summary generation failed"
    fi
    
    success "🎯 Graceful shutdown completed!"
    success "📊 Partial results saved in: $test_dir"
    warn "⚠️ Test was interrupted - results are partial and may be incomplete"
    
    exit 0
}

# Set up signal handlers
trap graceful_cleanup SIGINT SIGTERM

# Auto-detect profile if needed
if [ "$PROFILE" = "auto" ]; then
    log "🔍 Auto-detecting active topology profile..."
    DETECTED_PROFILE=$(bash scripts/detect_profile.sh 2>/dev/null || echo "unknown")
    
    if [ "$DETECTED_PROFILE" != "unknown" ]; then
        if [ "$DETECTED_PROFILE" = "urllc_legacy" ]; then
            DETECTED_PROFILE="urllc"
            log "✅ Detected legacy URLLC profile (3Gbit bug), treating as: $DETECTED_PROFILE"
        else
            log "✅ Detected active profile: $DETECTED_PROFILE"
        fi
        PROFILE="$DETECTED_PROFILE"
    else
        warn "⚠️ Could not detect profile, defaulting to urllc"
        PROFILE="urllc"
    fi
fi

ACTUAL_PROFILE="$PROFILE"

# Show current configuration
log "🚀 Starting graceful ODTE workflow..."
echo ""
PROFILE="$PROFILE" DURATION="$DURATION" bash scripts/show_current_config.sh || warn "Config display failed"
echo ""

log "[1/4] Running ODTE experiment (PROFILE=$PROFILE, DURATION=$DURATION)..."
log "💡 Press Ctrl+C at any time for graceful shutdown with partial results"

# Start ODTE experiment in background
{
    make odte PROFILE="$PROFILE" DURATION="$DURATION" &
    ODTE_PID=$!
    
    log "🎯 ODTE started (PID: $ODTE_PID)"
    
    # Intentionally skip intelligent filter application: run with ALL devices.
    # This avoids brittle house-name based detection and ensures the updater
    # processes every device. Analysis later will filter to bidirectional
    # devices only.
    log "� Skipping intelligent filter: updater will run for ALL devices"
    FILTER_PID=""
    
    # Wait for ODTE to complete
    wait "$ODTE_PID"
    ODTE_EXIT_CODE=$?
    
    # Wait for filter to complete (only if we started one)
    if [ -n "$FILTER_PID" ]; then
        wait "$FILTER_PID" 2>/dev/null || true
    fi
    
    if [ $ODTE_EXIT_CODE -ne 0 ]; then
        error "ODTE experiment failed with exit code $ODTE_EXIT_CODE"
        exit 1
    fi
    
} || {
    error "ODTE experiment failed"
    graceful_cleanup
    exit 1
}

# If we get here, the test completed successfully
log "✅ ODTE experiment completed successfully!"

# Continue with post-processing
# Resolve results path and retry a few times to avoid timing issues
if [ -L results ]; then
    RESULTS_DIR=$(readlink -f results)
else
    RESULTS_DIR="results"
fi

latest_test_dir=""
for i in $(seq 1 10); do
    latest_test_dir=$(find "$RESULTS_DIR" -name "test_*_$PROFILE" -type d 2>/dev/null | sort | tail -1)
    if [ -n "$latest_test_dir" ]; then
        break
    fi
    sleep 1
done

if [ -z "$latest_test_dir" ]; then
    error "No test directory found for profile $PROFILE (searched: $RESULTS_DIR)"
    exit 1
fi

reports_dir="$latest_test_dir/generated_reports"
reports_dir="$latest_test_dir/generated_reports"

# Ensure reports directory exists (avoid failure if not created by earlier steps)
if [ ! -d "$reports_dir" ]; then
    warn "Reports directory not found: $reports_dir - creating it"
    mkdir -p "$reports_dir" || {
        error "Failed to create reports directory: $reports_dir"
        exit 1
    }
fi

log "[2/4] Performing detailed latency analysis..."
# Generate bidirectional-only data and replace ODTE CSV so all downstream
# analyses use only bidirectional devices (telemetry + RPC).
log "🔎 Generating bidirectional-only dataset (telemetry ∩ RPC)"
if python3 scripts/analyze_bidirectional.py "$reports_dir"; then
    # If a filtered CSV was created, replace the original urllc_odte CSV with it
    FILTERED_CSV=$(ls "$reports_dir"/filtered_odte_*.csv 2>/dev/null | head -n1 || true)
    ORIG_CSV=$(ls "$reports_dir"/urllc_odte_*.csv 2>/dev/null | head -n1 || true)
    if [ -n "$FILTERED_CSV" ] && [ -n "$ORIG_CSV" ]; then
        log "🔁 Replacing original ODTE CSV with filtered bidirectional CSV"
        cp "$ORIG_CSV" "${ORIG_CSV}.bak" || true
        mv -f "$FILTERED_CSV" "$ORIG_CSV" || cp -f "$FILTERED_CSV" "$ORIG_CSV"
    else
        log "⚠️ No filtered CSV found; continuing with original ODTE CSV"
    fi
else
    warn "⚠️ Bidirectional analysis failed; continuing with original ODTE CSV"
fi

python3 scripts/reports/report_generators/latency_analysis.py "$reports_dir" || {
    error "Latency analysis failed"
    exit 1
}

log "[3/4] Performing standard analysis on: $reports_dir"
make analyze REPORTS_DIR="$reports_dir" || {
    error "Analysis failed"
    exit 1
}

log "[4/4] Generating plots..."
make plots REPORTS_DIR="$reports_dir" || {
    error "Plot generation failed"
    exit 1
}

log "[5/5] Running intelligent analysis..."
python3 scripts/reports/report_generators/intelligent_test_analysis.py "$latest_test_dir" || {
    warn "⚠️ Intelligent analysis failed, continuing..."
}

success "✅ Complete ODTE workflow finished successfully!"
bash scripts/show_test_summary.sh "$reports_dir" || warn "Summary display failed"