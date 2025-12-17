#!/bin/bash
#
# 12-tdarr.sh - Configure Tdarr transcoding server
# Part of the configure phase
#

set -euo pipefail

# Source library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/../../lib/init.sh"

# Module info
MODULE_NAME="Configure Tdarr"
MODULE_STEP=12
MODULE_TOTAL=12

# ============================================
# HELPER FUNCTIONS
# ============================================

# Generate 24x7 schedule JSON
generate_tdarr_schedule() {
    local schedule="["
    local first=true
    for day in Sun Mon Tue Wed Thur Fri Sat; do
        for hour in 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23; do
            local next_hour
            next_hour=$(printf "%02d" $(( (10#$hour + 1) % 24 )))
            if [[ "$first" == true ]]; then
                first=false
            else
                schedule+=","
            fi
            schedule+="{\"_id\":\"${day}:${hour}-${next_hour}\",\"checked\":true}"
        done
    done
    schedule+="]"
    echo "$schedule"
}

# ============================================
# MAIN
# ============================================

main() {
    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "running"

    cd "$(get_project_root)"
    load_env

    print_section "Configuring Tdarr (Transcoding)"

    # Wait for Tdarr to be ready
    if ! wait_for_service "Tdarr" "http://localhost:8265" 15 2; then
        report_log "warning" "Tdarr not ready - skipping configuration"
        print_info "Configure manually at http://localhost:8265"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    # Give Tdarr a moment to fully initialize its database
    sleep 3

    # Get API keys for notifications
    local sonarr_key="${SONARR_API_KEY:-$(get_api_key sonarr)}"
    local radarr_key="${RADARR_API_KEY:-$(get_api_key radarr)}"

    # Auto-detect GPU
    local gpu_type
    gpu_type=$(detect_gpu_type)
    local gpu_name
    gpu_name=$(get_gpu_name "$gpu_type")
    print_info "Detected GPU: ${gpu_name}"

    # Check existing flows
    local existing_flows
    existing_flows=$(curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
        -H "Content-Type: application/json" \
        -d '{"data": {"collection":"FlowsJSONDB","mode":"getAll"}}' 2>/dev/null || echo "{}")

    local flow_name="h265-${gpu_type}-transcode"
    local flow_id=""

    # Check for existing flow (handle both compact and pretty JSON)
    if echo "$existing_flows" | grep -qE "\"name\":[[:space:]]*\"${flow_name}\""; then
        print_info "Tdarr ${gpu_name} flow already exists"
        flow_id=$(echo "$existing_flows" | python3 -c "
import sys, json
flow_name = '${flow_name}'
try:
    data = json.load(sys.stdin)
    for flow in data:
        if flow.get('name') == flow_name:
            print(flow.get('_id', ''))
            break
except: pass
" 2>/dev/null || echo "")
    else
        print_info "Creating Tdarr H.265 ${gpu_name} transcoding flow..."
        flow_id=$(openssl rand -hex 5)

        local flow_body
        flow_body=$(cat <<EOF
{
    "data": {
        "collection": "FlowsJSONDB",
        "mode": "insert",
        "docID": "${flow_id}",
        "obj": {
            "_id": "${flow_id}",
            "name": "${flow_name}",
            "description": "Auto-created: H.265 ${gpu_name} transcoding for media files",
            "flowPlugins": [
                {"name":"Input File","sourceRepo":"Community","pluginName":"inputFile","version":"1.0.0","id":"inp1","position":{"x":696,"y":180},"flowType":"flow","fpEnabled":true},
                {"name":"Check File Medium","sourceRepo":"Community","pluginName":"checkFileMedium","version":"1.0.0","id":"chk1","position":{"x":696,"y":240},"fpEnabled":true},
                {"name":"Check Video Codec (hevc)","sourceRepo":"Community","pluginName":"checkVideoCodec","version":"1.0.0","id":"cvc1","position":{"x":696,"y":300},"fpEnabled":true,"inputsDB":{"codec":"hevc"}},
                {"name":"Begin Command","sourceRepo":"Community","pluginName":"ffmpegCommandStart","version":"1.0.0","id":"cmd1","position":{"x":696,"y":360},"fpEnabled":true},
                {"name":"Set Video Encoder","sourceRepo":"Community","pluginName":"ffmpegCommandSetVideoEncoder","version":"1.0.0","id":"enc1","position":{"x":696,"y":420},"fpEnabled":true,"inputsDB":{"hardwareType":"${gpu_type}","ffmpegQuality":"22"}},
                {"name":"Set Container","sourceRepo":"Community","pluginName":"ffmpegCommandSetContainer","version":"1.0.0","id":"con1","position":{"x":696,"y":480},"fpEnabled":true},
                {"name":"Execute","sourceRepo":"Community","pluginName":"ffmpegCommandExecute","version":"1.0.0","id":"exe1","position":{"x":696,"y":540},"fpEnabled":true},
                {"name":"Replace Original File","sourceRepo":"Community","pluginName":"replaceOriginalFile","version":"1.0.0","id":"rep1","position":{"x":696,"y":600},"fpEnabled":true},
                {"name":"Notify Radarr","sourceRepo":"Community","pluginName":"notifyRadarrOrSonarr","version":"2.0.0","id":"ntr1","position":{"x":696,"y":660},"fpEnabled":true,"inputsDB":{"arr":"radarr","arr_host":"http://radarr:7878","arr_api_key":"${radarr_key}"}},
                {"name":"Notify Sonarr","sourceRepo":"Community","pluginName":"notifyRadarrOrSonarr","version":"2.0.0","id":"nts1","position":{"x":696,"y":720},"fpEnabled":true,"inputsDB":{"arr":"sonarr","arr_host":"http://sonarr:8989","arr_api_key":"${sonarr_key}"}}
            ],
            "flowEdges": [
                {"source":"inp1","sourceHandle":"1","target":"chk1","id":"e1","type":"smoothstep","animated":true},
                {"source":"chk1","sourceHandle":"1","target":"cvc1","id":"e2","type":"smoothstep","animated":true},
                {"source":"cvc1","sourceHandle":"2","target":"cmd1","id":"e3","type":"smoothstep","animated":true},
                {"source":"cmd1","sourceHandle":"1","target":"enc1","id":"e4","type":"smoothstep","animated":true},
                {"source":"enc1","sourceHandle":"1","target":"con1","id":"e5","type":"smoothstep","animated":true},
                {"source":"con1","sourceHandle":"1","target":"exe1","id":"e6","type":"smoothstep","animated":true},
                {"source":"exe1","sourceHandle":"1","target":"rep1","id":"e7","type":"smoothstep","animated":true},
                {"source":"rep1","sourceHandle":"1","target":"ntr1","id":"e8","type":"smoothstep","animated":true},
                {"source":"ntr1","sourceHandle":"2","target":"nts1","id":"e9","type":"smoothstep","animated":true}
            ]
        }
    }
}
EOF
)
        curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
            -H "Content-Type: application/json" \
            -d "$flow_body" > /dev/null 2>&1

        # Verify the flow was actually created by querying again
        sleep 1
        local verify_flows
        verify_flows=$(curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
            -H "Content-Type: application/json" \
            -d '{"data": {"collection":"FlowsJSONDB","mode":"getAll"}}' 2>/dev/null || echo "{}")

        if echo "$verify_flows" | grep -qE "\"name\":[[:space:]]*\"${flow_name}\""; then
            # Get the actual flow ID that was created
            flow_id=$(echo "$verify_flows" | python3 -c "
import sys, json
flow_name = '${flow_name}'
try:
    data = json.load(sys.stdin)
    for flow in data:
        if flow.get('name') == flow_name:
            print(flow.get('_id', ''))
            break
except: pass
" 2>/dev/null || echo "")
            report_log "success" "H.265 ${gpu_name} transcoding flow created"
        else
            report_log "warning" "Could not create flow via API"
            flow_id=""
        fi
    fi

    # Create libraries
    local existing_libraries
    existing_libraries=$(curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
        -H "Content-Type: application/json" \
        -d '{"data": {"collection":"LibrarySettingsJSONDB","mode":"getAll"}}' 2>/dev/null || echo "{}")

    local tdarr_schedule
    tdarr_schedule=$(generate_tdarr_schedule)

    # Create Movies library
    if ! echo "$existing_libraries" | grep -q '"name":"Movies"'; then
        print_info "Creating Tdarr Movies library..."
        local library_id
        library_id=$(openssl rand -hex 5)

        local library_body
        library_body=$(cat <<EOF
{
    "data": {
        "collection": "LibrarySettingsJSONDB",
        "mode": "insert",
        "docID": "${library_id}",
        "obj": {
            "_id": "${library_id}",
            "name": "Movies",
            "priority": 0,
            "folder": "/media/movies",
            "cache": "/temp",
            "container": ".mkv",
            "containerFilter": "mkv,mp4,mov,m4v,mpg,mpeg,avi,flv,webm,wmv,vob,evo,iso,m2ts,ts",
            "folderWatching": true,
            "processLibrary": true,
            "processTranscodes": true,
            "processHealthChecks": true,
            "scanOnStart": true,
            "schedule": ${tdarr_schedule},
            "flowId": "${flow_id}"
        }
    }
}
EOF
)
        curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
            -H "Content-Type: application/json" \
            -d "$library_body" > /dev/null 2>&1 && \
            report_log "success" "Movies library created" || report_log "warning" "Could not create Movies library"
    else
        print_info "Tdarr Movies library already exists"
    fi

    # Create TV Shows library
    if ! echo "$existing_libraries" | grep -q '"name":"TV Shows"'; then
        print_info "Creating Tdarr TV Shows library..."
        local tv_library_id
        tv_library_id=$(openssl rand -hex 5)

        local tv_library_body
        tv_library_body=$(cat <<EOF
{
    "data": {
        "collection": "LibrarySettingsJSONDB",
        "mode": "insert",
        "docID": "${tv_library_id}",
        "obj": {
            "_id": "${tv_library_id}",
            "name": "TV Shows",
            "priority": 1,
            "folder": "/media/tv",
            "cache": "/temp",
            "container": ".mkv",
            "containerFilter": "mkv,mp4,mov,m4v,mpg,mpeg,avi,flv,webm,wmv,vob,evo,iso,m2ts,ts",
            "folderWatching": true,
            "processLibrary": true,
            "processTranscodes": true,
            "processHealthChecks": true,
            "scanOnStart": true,
            "schedule": ${tdarr_schedule},
            "flowId": "${flow_id}"
        }
    }
}
EOF
)
        curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
            -H "Content-Type: application/json" \
            -d "$tv_library_body" > /dev/null 2>&1 && \
            report_log "success" "TV Shows library created" || report_log "warning" "Could not create TV Shows library"
    else
        print_info "Tdarr TV Shows library already exists"
    fi

    # Configure node workers
    print_info "Configuring Tdarr node worker limits..."
    sleep 3

    curl -s -X POST "http://localhost:8265/api/v2/cruddb" \
        -H "Content-Type: application/json" \
        -d '{
            "data": {
                "collection": "NodeJSONDB",
                "mode": "update",
                "docID": "HomeLabNode",
                "obj": {
                    "workerLimits": {
                        "healthcheckcpu": 0,
                        "healthcheckgpu": 1,
                        "transcodecpu": 0,
                        "transcodegpu": 2
                    },
                    "nodePaused": false
                }
            }
        }' > /dev/null 2>&1 && \
        report_log "success" "Node workers configured (2 GPU transcode, 1 GPU healthcheck)" || \
        report_log "warning" "Could not configure node workers"

    report_log "success" "Tdarr fully configured with H.265 ${gpu_name} flow and GPU workers"
    report_log "info" "To enable auth: visit http://localhost:8265 and create an admin account"

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
