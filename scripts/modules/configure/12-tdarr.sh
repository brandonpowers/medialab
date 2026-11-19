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
    if ! wait_for_service "Tdarr" "${TDARR_URL}" 15 2; then
        report_log "warning" "Tdarr not ready - skipping configuration"
        print_info "Configure manually at ${TDARR_URL}"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

    # Give Tdarr a moment to fully initialize its database
    sleep 3

    # Get Tdarr API key for authenticated requests
    local tdarr_api_key="${TDARR_API_KEY:-}"
    if [[ -n "$tdarr_api_key" ]]; then
        report_log "success" "Using Tdarr API key for authentication"
    fi

    # Build curl arguments array for Tdarr API calls
    local -a tdarr_curl_auth=()
    if [[ -n "$tdarr_api_key" ]]; then
        tdarr_curl_auth=(-H "x-api-key: ${tdarr_api_key}")
    fi

    # Helper function to make Tdarr API calls with optional auth.
    # Prints the response body and returns non-zero on a transport error or a
    # non-2xx status, so a 401 (wrong/missing key) is no longer reported as
    # success. Tdarr answers a successful cruddb insert/update with an empty 200.
    tdarr_api() {
        local method="$1"
        local endpoint="$2"
        local data="${3:-}"
        local -a args=(-s -X "$method" "${TDARR_URL}${endpoint}"
            -H "Content-Type: application/json" "${tdarr_curl_auth[@]}"
            -w $'\n%{http_code}')
        [[ -n "$data" ]] && args+=(-d "$data")

        local out code
        out=$(curl "${args[@]}" 2>/dev/null) || { echo "{}"; return 1; }
        code="${out##*$'\n'}"
        out="${out%$'\n'*}"
        echo "$out"
        [[ "$code" == 2?? ]]
    }

    # Tdarr 3 runs with auth on: stop here, rather than report a string of
    # false successes, if the server rejects the key.
    if ! tdarr_api POST "/api/v2/cruddb" '{"data": {"collection":"FlowsJSONDB","mode":"getAll"}}' > /dev/null; then
        report_log "error" "Tdarr rejected the API request - check TDARR_API_KEY in .env matches the running tdarr container (recreate it after changing the key)"
        report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
        return 0
    fi

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
    existing_flows=$(tdarr_api POST "/api/v2/cruddb" '{"data": {"collection":"FlowsJSONDB","mode":"getAll"}}') || true

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
        tdarr_api POST "/api/v2/cruddb" "$flow_body" > /dev/null 2>&1 || true  # verified below

        # Verify the flow was actually created by querying again
        sleep 1
        local verify_flows
        verify_flows=$(tdarr_api POST "/api/v2/cruddb" '{"data": {"collection":"FlowsJSONDB","mode":"getAll"}}') || true

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
    existing_libraries=$(tdarr_api POST "/api/v2/cruddb" '{"data": {"collection":"LibrarySettingsJSONDB","mode":"getAll"}}') || true

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
        tdarr_api POST "/api/v2/cruddb" "$library_body" > /dev/null 2>&1 && \
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
        tdarr_api POST "/api/v2/cruddb" "$tv_library_body" > /dev/null 2>&1 && \
            report_log "success" "TV Shows library created" || report_log "warning" "Could not create TV Shows library"
    else
        print_info "Tdarr TV Shows library already exists"
    fi

    # Create Unidentified library (for ARM rips that couldn't be auto-identified)
    if ! echo "$existing_libraries" | grep -q '"name":"Unidentified"'; then
        print_info "Creating Tdarr Unidentified library..."
        local unid_library_id
        unid_library_id=$(openssl rand -hex 5)

        local unid_library_body
        unid_library_body=$(cat <<EOF
{
    "data": {
        "collection": "LibrarySettingsJSONDB",
        "mode": "insert",
        "docID": "${unid_library_id}",
        "obj": {
            "_id": "${unid_library_id}",
            "name": "Unidentified",
            "priority": 2,
            "folder": "/media/unidentified",
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
        tdarr_api POST "/api/v2/cruddb" "$unid_library_body" > /dev/null 2>&1 && \
            report_log "success" "Unidentified library created" || report_log "warning" "Could not create Unidentified library"
    else
        print_info "Tdarr Unidentified library already exists"
    fi

    # Configure node workers.
    # A cruddb write to NodeJSONDB only changes the saved settings (keyed by
    # node name), which the node reads when it next registers - the running
    # node keeps its old limits until tdarr restarts. update-node changes the
    # live node and saves the change, the same as the web UI. It takes the
    # node's runtime ID, which changes on every registration, so look it up by
    # name. The internal node registers ~10s after the server comes up.
    print_info "Configuring Tdarr node worker limits..."
    local node_name="MediaLabNode"   # matches nodeName in docker-compose.yml
    local node_id=""
    for _ in $(seq 1 30); do
        node_id=$(tdarr_api GET "/api/v2/get-nodes" 2>/dev/null \
            | jq -r --arg n "$node_name" \
                'to_entries[] | select(.value.nodeName == $n) | .key' 2>/dev/null \
            | head -n1) || true
        [[ -n "$node_id" ]] && break
        sleep 2
    done

    # Follow the detected hardware: GPU worker slots on a host without a GPU
    # would never encode anything.
    local worker_limits worker_summary
    if [[ "$gpu_type" == "cpu" ]]; then
        worker_limits='{"healthcheckcpu": 1, "healthcheckgpu": 0, "transcodecpu": 1, "transcodegpu": 0}'
        worker_summary="1 CPU transcode, 1 CPU healthcheck"
    else
        worker_limits='{"healthcheckcpu": 0, "healthcheckgpu": 1, "transcodecpu": 0, "transcodegpu": 2}'
        worker_summary="2 GPU transcode, 1 GPU healthcheck"
    fi

    local node_update
    node_update=$(jq -nc --arg id "$node_id" --argjson limits "$worker_limits" \
        '{data: {nodeID: $id, nodeUpdates: {workerLimits: $limits, nodePaused: false}}}')
    if [[ -z "$node_id" ]]; then
        report_log "warning" "Tdarr node '${node_name}' has not registered - set worker limits in the web UI"
    elif tdarr_api POST "/api/v2/update-node" "$node_update" > /dev/null; then
        report_log "success" "Node workers configured (${worker_summary})"
    else
        report_log "warning" "Could not configure node workers"
    fi

    report_log "success" "Tdarr configured with the H.265 ${gpu_name} flow"
    # Tdarr 3 runs with auth on. On a server with no users, seededApiKey also
    # creates an `admin` user whose password is that key.
    if [[ -n "$tdarr_api_key" ]]; then
        report_log "info" "Tdarr auth is on - log in at ${TDARR_URL} as 'admin' with TDARR_API_KEY from .env as the password"
    else
        report_log "warning" "TDARR_API_KEY is not set but Tdarr 3 requires auth - set it in .env and recreate tdarr"
    fi

    report_progress "$MODULE_STEP" "$MODULE_TOTAL" "$MODULE_NAME" "complete"
    finish_progress "complete" "$MODULE_NAME"
}

main "$@"
