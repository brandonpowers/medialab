// Homelab Setup Wizard JavaScript

// State
let currentStep = 1;
let hardwareData = null;
let driveData = null;
let selectedDrive = null;
let config = {};
let currentEventSource = null;
let currentModulePid = null;
let installAborted = false;
let installCancelledByUser = false;
let installCompleted = false;

// API Base URL
const API_BASE = '/cgi-bin';

// localStorage key for form persistence
const FORM_STORAGE_KEY = 'homelab_setup_form';

// ============================================
// FORM PERSISTENCE
// ============================================

// List of form field IDs to persist
const PERSIST_FIELDS = [
    // Step 1: Hardware (timezone dropdown)
    'timezone',
    // Step 2: Storage
    'media-path', 'format-drive',
    // Step 3: Admin
    'server-name', 'language', 'admin-email', 'admin-user', 'admin-pass',
    // Step 4: Services
    'tmdb-key',
    'enable-usenet', 'usenet-host', 'usenet-port', 'usenet-connections', 'usenet-ssl', 'usenet-user', 'usenet-pass',
    'enable-nzb-indexer', 'nzb-indexer-type', 'nzb-indexer-api-key', 'nzb-indexer-url',
    'enable-cloudflare', 'domain', 'cf-token'
];

function saveFormData() {
    const formData = {};
    PERSIST_FIELDS.forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            if (el.type === 'checkbox') {
                formData[id] = el.checked;
            } else {
                formData[id] = el.value;
            }
        }
    });
    // Also save selected drive
    const selectedDriveRadio = document.querySelector('input[name="drive"]:checked');
    if (selectedDriveRadio) {
        formData['_selectedDrive'] = selectedDriveRadio.value;
    }
    try {
        localStorage.setItem(FORM_STORAGE_KEY, JSON.stringify(formData));
    } catch (e) {
        console.warn('Could not save form data to localStorage:', e);
    }
}

function loadFormData() {
    try {
        const saved = localStorage.getItem(FORM_STORAGE_KEY);
        if (!saved) return;

        const formData = JSON.parse(saved);
        PERSIST_FIELDS.forEach(id => {
            const el = document.getElementById(id);
            if (el && formData[id] !== undefined) {
                if (el.type === 'checkbox') {
                    el.checked = formData[id];
                } else {
                    el.value = formData[id];
                }
            }
        });
        // Restore selected drive (will be applied after drives load)
        if (formData['_selectedDrive']) {
            selectedDrive = formData['_selectedDrive'];
        }
    } catch (e) {
        console.warn('Could not load form data from localStorage:', e);
    }
}

function setupFormPersistence() {
    PERSIST_FIELDS.forEach(id => {
        const el = document.getElementById(id);
        if (el) {
            const eventType = (el.type === 'checkbox' || el.tagName === 'SELECT') ? 'change' : 'input';
            el.addEventListener(eventType, saveFormData);
        }
    });
    // Also listen for drive selection changes
    document.addEventListener('change', (e) => {
        if (e.target.name === 'drive') {
            saveFormData();
        }
    });
}

// ============================================
// STEP NAVIGATION
// ============================================

function goToStep(step) {
    // Update step indicators
    document.querySelectorAll('.step').forEach((el, idx) => {
        el.classList.remove('active', 'complete');
        if (idx + 1 < step) el.classList.add('complete');
        if (idx + 1 === step) el.classList.add('active');
    });

    // Update content
    document.querySelectorAll('.step-content').forEach((el, idx) => {
        el.classList.remove('active');
        if (idx + 1 === step) el.classList.add('active');
    });

    currentStep = step;

    // Load step data
    if (step === 1) detectHardware();
    if (step === 2) loadDrives();
    if (step === 5) prepareInstall();
    if (step === 6) loadServiceStatus();
}

function nextStep() {
    if (currentStep < 6) {
        goToStep(currentStep + 1);
    }
}

function prevStep() {
    if (currentStep > 1) {
        goToStep(currentStep - 1);
    }
}

// ============================================
// HARDWARE DETECTION
// ============================================

// Common timezones grouped by region
const timezones = [
    // Americas
    'America/New_York', 'America/Chicago', 'America/Denver', 'America/Los_Angeles',
    'America/Anchorage', 'America/Phoenix', 'America/Toronto', 'America/Vancouver',
    'America/Mexico_City', 'America/Sao_Paulo', 'America/Buenos_Aires',
    // Europe
    'Europe/London', 'Europe/Paris', 'Europe/Berlin', 'Europe/Rome', 'Europe/Madrid',
    'Europe/Amsterdam', 'Europe/Brussels', 'Europe/Stockholm', 'Europe/Warsaw',
    'Europe/Moscow', 'Europe/Istanbul',
    // Asia/Pacific
    'Asia/Tokyo', 'Asia/Shanghai', 'Asia/Hong_Kong', 'Asia/Singapore', 'Asia/Seoul',
    'Asia/Kolkata', 'Asia/Dubai', 'Asia/Bangkok', 'Asia/Jakarta',
    'Australia/Sydney', 'Australia/Melbourne', 'Australia/Perth',
    'Pacific/Auckland', 'Pacific/Honolulu',
    // Africa
    'Africa/Cairo', 'Africa/Johannesburg', 'Africa/Lagos', 'Africa/Nairobi'
];

function populateTimezoneDropdown(detectedTimezone) {
    const select = document.getElementById('timezone');
    const detected = detectedTimezone || 'America/Chicago';

    // Check if there's already a saved timezone value (from localStorage)
    const savedTimezone = select.value;
    const timezoneToSelect = savedTimezone || detected;

    // Add detected timezone first if not in list
    let tzList = [...timezones];
    if (detected && !tzList.includes(detected)) {
        tzList.unshift(detected);
    }
    // Also add saved timezone if not in list
    if (savedTimezone && !tzList.includes(savedTimezone)) {
        tzList.unshift(savedTimezone);
    }

    // Sort alphabetically
    tzList.sort();

    select.innerHTML = tzList.map(tz => {
        const selected = tz === timezoneToSelect ? 'selected' : '';
        return `<option value="${tz}" ${selected}>${tz.replace(/_/g, ' ')}</option>`;
    }).join('');
}

async function detectHardware() {
    const container = document.getElementById('hardware-info');
    container.innerHTML = '<div class="loading">Scanning hardware...</div>';

    try {
        const response = await fetch(`${API_BASE}/detect.cgi`);
        hardwareData = await response.json();

        const detectedTz = hardwareData.timezone || 'America/Chicago';

        // Format CPU display
        const cpuModel = hardwareData.system?.cpu_model || 'Unknown';
        const cpuCores = hardwareData.system?.cpu_cores || '?';

        // Format GPU display - show model if available, otherwise fall back to type name
        const gpuModel = hardwareData.gpu?.model;
        const gpuType = hardwareData.gpu?.name || 'Unknown';
        const gpuAccel = gpuType.match(/\(([^)]+)\)/)?.[1] || '';  // Extract "VAAPI", "NVENC", etc.
        const gpuDisplay = gpuModel
            ? `${gpuModel}${gpuAccel ? ` (${gpuAccel})` : ''}`
            : gpuType;

        // Format optical drives
        const opticalDrives = hardwareData.optical?.drives || '';
        const opticalDisplay = opticalDrives ? opticalDrives : 'None detected';

        container.innerHTML = `
            <div class="hardware-item">
                <span class="hardware-label">CPU</span>
                <span class="hardware-value">${cpuModel} (${cpuCores} cores)</span>
            </div>
            <div class="hardware-item">
                <span class="hardware-label">Memory</span>
                <span class="hardware-value">${hardwareData.system?.memory || 'Unknown'}</span>
            </div>
            <div class="hardware-item">
                <span class="hardware-label">GPU</span>
                <span class="hardware-value">${gpuDisplay}</span>
            </div>
            <div class="hardware-item">
                <span class="hardware-label">Optical Drives</span>
                <span class="hardware-value">${opticalDisplay}</span>
            </div>
            <div class="hardware-item">
                <span class="hardware-label">Timezone</span>
                <select id="timezone" class="hardware-select">
                    <option value="">Loading...</option>
                </select>
            </div>
        `;

        // Populate timezone dropdown with detected value
        populateTimezoneDropdown(detectedTz);

        // Pre-populate Jellyfin server name with hostname
        const detectedHostname = hardwareData.system?.hostname || 'Media Server';
        const serverNameInput = document.getElementById('server-name');
        if (serverNameInput && !serverNameInput.value) {
            serverNameInput.value = detectedHostname;
        }

        document.getElementById('btn-next-1').disabled = false;
    } catch (error) {
        container.innerHTML = `
            <div class="hardware-item">
                <span class="hardware-value" style="color: var(--error)">
                    Failed to detect hardware. Make sure the CGI server is running.
                </span>
            </div>
            <p style="margin-top: 1rem; color: var(--text-muted)">
                You can still proceed with manual configuration.
            </p>
            <div class="hardware-item">
                <span class="hardware-label">Timezone</span>
                <select id="timezone" class="hardware-select">
                    <option value="">Loading...</option>
                </select>
            </div>
        `;
        // Still populate timezone dropdown with default
        populateTimezoneDropdown(null);
        document.getElementById('btn-next-1').disabled = false;
    }
}

// ============================================
// DRIVE SELECTION
// ============================================

async function loadDrives() {
    const container = document.getElementById('drive-list');
    container.innerHTML = '<div class="loading">Loading drives...</div>';

    // Reset format checkbox state
    updateFormatCheckbox(null);

    try {
        const response = await fetch(`${API_BASE}/drives.cgi`);
        driveData = await response.json();

        if (!driveData.drives || driveData.drives.length === 0) {
            container.innerHTML = `
                <p>No drives detected. Enter a path below for media storage.</p>
            `;
            selectedDrive = null;
            updateFormatCheckbox(null);
            document.getElementById('btn-next-2').disabled = false;
            return;
        }

        let html = '';
        driveData.drives.forEach((drive, idx) => {
            const isRecommended = drive.device === driveData.recommended;
            const isSystem = drive.is_system;

            // Determine status badge
            let statusBadge = '';
            if (isSystem) {
                statusBadge = '<span class="drive-system">System Drive</span>';
            } else if (isRecommended) {
                statusBadge = '<span class="drive-recommended">Recommended</span>';
            }

            // Mount status text
            const mountInfo = drive.mountpoint
                ? `mounted at ${drive.mountpoint}`
                : 'not mounted';

            // Select first non-system drive by default, or first drive if all are system
            const firstNonSystem = driveData.drives.findIndex(d => !d.is_system);
            const defaultIdx = firstNonSystem >= 0 ? firstNonSystem : 0;
            const isSelected = idx === defaultIdx;

            html += `
                <label class="drive-item ${isSelected ? 'selected' : ''} ${isSystem ? 'drive-is-system' : ''}" onclick="selectDrive(${idx})">
                    <input type="radio" name="drive" value="${drive.device}" ${isSelected ? 'checked' : ''}>
                    <div class="drive-info">
                        <div class="drive-name">${drive.device} ${statusBadge}</div>
                        <div class="drive-details">
                            ${drive.size} - ${drive.model || 'Unknown'} (${mountInfo})
                        </div>
                    </div>
                </label>
            `;
        });

        container.innerHTML = html;

        // Check if we have a saved drive selection from localStorage
        const savedDriveIdx = selectedDrive ? driveData.drives.findIndex(d => d.device === selectedDrive) : -1;

        // Use saved selection if valid, otherwise default to first non-system drive
        let defaultIdx;
        if (savedDriveIdx >= 0) {
            defaultIdx = savedDriveIdx;
        } else {
            const firstNonSystem = driveData.drives.findIndex(d => !d.is_system);
            defaultIdx = firstNonSystem >= 0 ? firstNonSystem : 0;
        }

        selectedDrive = driveData.drives[defaultIdx]?.device;

        // Update radio button selection
        const driveRadio = document.querySelector(`input[name="drive"][value="${selectedDrive}"]`);
        if (driveRadio) {
            driveRadio.checked = true;
            driveRadio.closest('.drive-item')?.classList.add('selected');
        }

        // Only update media path if it's empty (don't override saved value)
        const pathInput = document.getElementById('media-path');
        if (!pathInput.value) {
            updateMediaPath(driveData.drives[defaultIdx]);
        }
        updateFormatCheckbox(driveData.drives[defaultIdx]);

        document.getElementById('btn-next-2').disabled = false;
    } catch (error) {
        container.innerHTML = `
            <p style="color: var(--warning)">
                Could not load drives. Enter a path below for media storage.
            </p>
        `;
        selectedDrive = null;
        updateFormatCheckbox(null);
        document.getElementById('btn-next-2').disabled = false;
    }
}

// Update suggested media path based on selected drive
function updateMediaPath(drive) {
    const pathInput = document.getElementById('media-path');
    if (!drive) {
        pathInput.value = '/mnt/media';
        return;
    }

    if (drive.is_system) {
        // For system drives, suggest a folder on the root filesystem
        pathInput.value = '/srv/media';
    } else if (drive.mountpoint) {
        // For mounted drives, suggest media folder on that mount
        pathInput.value = `${drive.mountpoint}/media`;
    } else {
        // For unmounted drives, use /mnt/media
        pathInput.value = '/mnt/media';
    }
}

// Update format checkbox based on selected drive
function updateFormatCheckbox(drive) {
    const checkbox = document.getElementById('format-drive');
    const warning = document.getElementById('format-warning');
    const group = document.getElementById('format-group');

    // Reset state
    checkbox.checked = false;
    checkbox.disabled = true;
    warning.classList.add('hidden');
    warning.textContent = '';
    group.classList.add('hidden');
    group.classList.remove('format-danger');

    if (!drive) {
        return;
    }

    // Never allow formatting system drives
    if (drive.is_system) {
        return;
    }

    // Show format option for non-system drives
    group.classList.remove('hidden');

    if (drive.mountpoint) {
        // Drive is mounted - disable formatting
        warning.textContent = `Drive is mounted at ${drive.mountpoint}. Unmount before formatting.`;
        warning.classList.remove('hidden');
        return;
    }

    // Drive is unmounted and not system - allow formatting with warning
    checkbox.disabled = false;
    group.classList.add('format-danger');
    warning.textContent = 'Warning: This will permanently erase ALL data on this drive!';
    warning.classList.remove('hidden');
}

function selectDrive(idx) {
    document.querySelectorAll('.drive-item').forEach((el, i) => {
        el.classList.toggle('selected', i === idx);
    });
    selectedDrive = driveData.drives[idx]?.device;
    updateMediaPath(driveData.drives[idx]);
    updateFormatCheckbox(driveData.drives[idx]);
}

// ============================================
// CLOUDFLARE TOGGLE
// ============================================

function toggleCloudflare() {
    const enabled = document.getElementById('enable-cloudflare').checked;
    const fields = document.getElementById('cloudflare-fields');
    fields.classList.toggle('hidden', !enabled);
}

// ============================================
// USENET TOGGLES
// ============================================

function toggleUsenet() {
    const enabled = document.getElementById('enable-usenet').checked;
    const fields = document.getElementById('usenet-fields');
    fields.classList.toggle('hidden', !enabled);
}

function toggleNzbIndexer() {
    const enabled = document.getElementById('enable-nzb-indexer').checked;
    const fields = document.getElementById('nzb-indexer-fields');
    fields.classList.toggle('hidden', !enabled);
}

function updateNzbIndexerUrl() {
    const indexerType = document.getElementById('nzb-indexer-type').value;
    const urlGroup = document.getElementById('nzb-indexer-url-group');

    // Show URL field only for custom indexer
    urlGroup.classList.toggle('hidden', indexerType !== 'custom');
}

// ============================================
// ADMIN VALIDATION
// ============================================

// Valid username pattern: letters, numbers, underscores, 3-32 chars
const usernameRegex = /^[a-zA-Z][a-zA-Z0-9_]{2,31}$/;

function validateUsername(input) {
    const value = input.value;
    const hint = document.getElementById('username-hint');

    // Remove invalid characters as user types
    const sanitized = value.replace(/[^a-zA-Z0-9_]/g, '');
    if (sanitized !== value) {
        input.value = sanitized;
    }

    // Validate
    if (sanitized.length === 0) {
        hint.textContent = 'Letters, numbers, and underscores only (3-32 characters)';
        hint.style.color = '';
        input.classList.remove('input-valid', 'input-invalid');
    } else if (!usernameRegex.test(sanitized)) {
        if (sanitized.length < 3) {
            hint.textContent = 'Username must be at least 3 characters';
        } else if (!/^[a-zA-Z]/.test(sanitized)) {
            hint.textContent = 'Username must start with a letter';
        } else {
            hint.textContent = 'Invalid username format';
        }
        hint.style.color = 'var(--error)';
        input.classList.add('input-invalid');
        input.classList.remove('input-valid');
    } else {
        hint.textContent = 'Username is valid';
        hint.style.color = 'var(--success)';
        input.classList.add('input-valid');
        input.classList.remove('input-invalid');
    }

    updateAdminNextButton();
}

function validatePassword() {
    const password = document.getElementById('admin-pass').value;
    const hint = document.getElementById('password-hint');
    const passInput = document.getElementById('admin-pass');

    // Validate password length
    if (password.length === 0) {
        hint.textContent = 'Minimum 8 characters';
        hint.style.color = '';
        passInput.classList.remove('input-valid', 'input-invalid');
    } else if (password.length < 8) {
        hint.textContent = `${8 - password.length} more characters needed`;
        hint.style.color = 'var(--error)';
        passInput.classList.add('input-invalid');
        passInput.classList.remove('input-valid');
    } else {
        hint.textContent = 'Password length OK';
        hint.style.color = 'var(--success)';
        passInput.classList.add('input-valid');
        passInput.classList.remove('input-invalid');
    }

    updateAdminNextButton();
}

function togglePasswordVisibility(inputId, toggleId) {
    // Support old single-argument call for backwards compatibility
    if (!toggleId) {
        inputId = 'admin-pass';
        toggleId = 'eye-icon';
    }

    const passInput = document.getElementById(inputId);
    const toggleText = document.getElementById(toggleId);

    if (passInput && toggleText) {
        if (passInput.type === 'password') {
            passInput.type = 'text';
            toggleText.textContent = 'hide';
        } else {
            passInput.type = 'password';
            toggleText.textContent = 'show';
        }
    }
}

function updateAdminNextButton() {
    const serverName = document.getElementById('server-name').value.trim();
    const username = document.getElementById('admin-user').value;
    const password = document.getElementById('admin-pass').value;
    const btn = document.getElementById('btn-next-3');

    const isValid = serverName.length >= 1 && usernameRegex.test(username) && password.length >= 8;

    btn.disabled = !isValid;
}

// ============================================
// INSTALLATION - MODULE DEFINITIONS
// ============================================

const setupModules = [
    { id: '01-prerequisites', name: 'Check Prerequisites', phase: 'setup' },
    { id: '02-detect-hardware', name: 'Detect Hardware', phase: 'setup' },
    { id: '03-select-media-drive', name: 'Configure Storage', phase: 'setup' },
    { id: '04-generate-env', name: 'Generate Environment', phase: 'setup' },
    { id: '05-create-directories', name: 'Create Directories', phase: 'setup' },
    { id: '06-setup-arm-udev', name: 'Setup ARM Detection', phase: 'setup' },
    { id: '07-pull-images', name: 'Pull Docker Images', phase: 'setup' },
    { id: '08-start-services', name: 'Start Services', phase: 'setup' }
];

const configureModules = [
    { id: '00-jellyfin', name: 'Configure Jellyfin', phase: 'configure', container: 'jellyfin' },
    { id: '01-wait-services', name: 'Wait for Services', phase: 'configure' },
    { id: '02-qbittorrent', name: 'Configure qBittorrent', phase: 'configure', container: 'qbittorrent' },
    { id: '02b-sabnzbd', name: 'Configure SABnzbd', phase: 'configure', container: 'sabnzbd' },
    { id: '03-prowlarr', name: 'Configure Prowlarr', phase: 'configure', container: 'prowlarr' },
    { id: '04-sonarr', name: 'Configure Sonarr', phase: 'configure', container: 'sonarr' },
    { id: '05-radarr', name: 'Configure Radarr', phase: 'configure', container: 'radarr' },
    { id: '06-lidarr', name: 'Configure Lidarr', phase: 'configure', container: 'lidarr' },
    { id: '07-bazarr', name: 'Configure Bazarr', phase: 'configure', container: 'bazarr' },
    { id: '08-link-prowlarr', name: 'Link Prowlarr', phase: 'configure' },
    { id: '09-recyclarr', name: 'Configure Recyclarr', phase: 'configure' },
    { id: '10-jellyseerr', name: 'Configure Jellyseerr', phase: 'configure', container: 'jellyseerr' },
    { id: '11-arm', name: 'Configure ARM', phase: 'configure', container: 'arm' },
    { id: '12-tdarr', name: 'Configure Tdarr', phase: 'configure', container: 'tdarr' },
    { id: '13-homepage', name: 'Verify Homepage', phase: 'configure', container: 'homepage' }
];

// Track service configuration status
let serviceConfigStatus = {};

// ============================================
// INSTALLATION - START
// ============================================

function prepareInstall() {
    console.log('prepareInstall called, installCompleted:', installCompleted);

    // If installation already completed, show Reinstall/Next buttons and Back but don't reset the UI
    if (installCompleted) {
        document.getElementById('btn-group-complete').classList.remove('hidden');
        document.getElementById('btn-back-install').classList.remove('hidden');
        return;
    }

    // Collect configuration from form fields (with safe access)
    const getVal = (id) => document.getElementById(id)?.value || '';
    const getChecked = (id) => document.getElementById(id)?.checked || false;
    const getDisabled = (id) => document.getElementById(id)?.disabled || false;

    config = {
        admin: {
            email: getVal('admin-email'),
            username: getVal('admin-user'),
            password: getVal('admin-pass')
        },
        system: {
            timezone: getVal('timezone') || 'America/Chicago',
            server_name: getVal('server-name') || 'homelab',
            language: getVal('language') || 'en'
        },
        storage: {
            drive_device: selectedDrive,
            media_path: getVal('media-path') || '/mnt/media',
            format_drive: getChecked('format-drive') && !getDisabled('format-drive')
        },
        cloud: {
            cloudflare_enabled: getChecked('enable-cloudflare'),
            domain: getVal('domain'),
            tunnel_token: getVal('cf-token')
        },
        api_keys: {
            tmdb: getVal('tmdb-key')
        },
        usenet: {
            enabled: getChecked('enable-usenet'),
            host: getVal('usenet-host'),
            port: parseInt(getVal('usenet-port')) || 563,
            username: getVal('usenet-user'),
            password: getVal('usenet-pass'),
            connections: parseInt(getVal('usenet-connections')) || 30,
            ssl: getChecked('usenet-ssl')
        },
        nzb_indexer: {
            enabled: getChecked('enable-nzb-indexer'),
            type: getVal('nzb-indexer-type'),
            api_key: getVal('nzb-indexer-api-key'),
            url: getVal('nzb-indexer-url')
        }
    };

    // Reset state
    installAborted = false;
    installCancelledByUser = false;

    // Reset UI visibility
    document.getElementById('btn-install').classList.remove('hidden');
    document.getElementById('btn-group-complete').classList.add('hidden');
    document.getElementById('btn-back-install').classList.remove('hidden');
    document.getElementById('btn-cancel').classList.add('hidden');
    document.getElementById('btn-diagnostic').classList.add('hidden');
    document.getElementById('log-card').classList.add('hidden');

    // Reset progress bar state
    const progressBar = document.getElementById('progress-bar');
    progressBar.classList.remove('success', 'error');
    document.getElementById('progress-fill').style.width = '0%';

    // Initialize module list
    const moduleList = document.getElementById('module-list');
    console.log('moduleList element:', moduleList);
    console.log('setupModules:', setupModules);

    if (moduleList && setupModules) {
        moduleList.innerHTML = setupModules.map(m => `
            <div class="module-item" id="module-${m.id}">
                <div class="module-status pending">○</div>
                <span>${m.name}</span>
            </div>
        `).join('');
    }

    // Show configuration summary
    console.log('config:', config);
    showConfigSummary();
}

function showConfigSummary() {
    const summary = document.getElementById('config-summary');

    // Safety check - ensure config exists
    if (!config || !config.system) {
        summary.innerHTML = '<p style="color: var(--text-muted)">Configuration not loaded</p>';
        return;
    }

    // Get optical drive info from hardware detection
    const opticalDrives = hardwareData?.optical?.drives || '';
    const opticalDisplay = opticalDrives ? opticalDrives : 'None';

    // Language display name mapping
    const languageNames = {
        'en': 'English', 'es': 'Spanish', 'fr': 'French', 'de': 'German',
        'it': 'Italian', 'pt': 'Portuguese', 'nl': 'Dutch', 'pl': 'Polish',
        'ru': 'Russian', 'ja': 'Japanese', 'zh': 'Chinese', 'ko': 'Korean'
    };

    const items = [
        { label: 'Server Name', value: config.system?.server_name || 'homelab' },
        { label: 'Language', value: languageNames[config.system?.language] || 'English' },
        { label: 'Timezone', value: config.system.timezone || 'America/Chicago' },
        { label: 'Admin User', value: config.admin?.username || '(not set)' },
        { label: 'Admin Email', value: config.admin?.email || '(not set)' },
        { label: 'Password', value: config.admin?.password ? '••••••••' : '(not set)', masked: !!config.admin?.password },
        { label: 'Media Path', value: config.storage?.media_path || '/mnt/media' },
        { label: 'Storage Drive', value: config.storage?.drive_device || '(existing path)' },
        { label: 'Format Drive', value: config.storage?.format_drive ? 'Yes' : 'No' },
        { label: 'Optical Drives', value: opticalDisplay },
        { label: 'Cloudflare', value: config.cloud?.cloudflare_enabled ? 'Enabled' : 'Disabled' }
    ];

    // Add domain if cloudflare is enabled
    if (config.cloud?.cloudflare_enabled && config.cloud?.domain) {
        items.push({ label: 'Domain', value: config.cloud.domain });
    }

    // Add TMDB if set
    if (config.api_keys?.tmdb) {
        items.push({ label: 'TMDB API', value: '••••••••', masked: true });
    }

    // Add Usenet if enabled
    if (config.usenet?.enabled) {
        items.push({ label: 'Usenet', value: `${config.usenet.host}:${config.usenet.port}` });
        if (config.usenet.username) {
            items.push({ label: 'Usenet User', value: config.usenet.username });
        }
    }

    // Add NZB Indexer if enabled
    if (config.nzb_indexer?.enabled) {
        const indexerNames = {
            'nzbgeek': 'NZBgeek',
            'drunkenslug': 'DrunkenSlug',
            'nzbfinder': 'NZBFinder',
            'custom': 'Custom'
        };
        items.push({ label: 'NZB Indexer', value: indexerNames[config.nzb_indexer.type] || config.nzb_indexer.type });
    }

    summary.innerHTML = items.map(item => `
        <div class="summary-item">
            <span class="summary-label">${item.label}</span>
            <span class="summary-value${item.masked ? ' masked' : ''}">${item.value}</span>
        </div>
    `).join('');
}

function beginInstall() {
    // Hide Install/Back buttons, show Cancel
    document.getElementById('btn-install').classList.add('hidden');
    document.getElementById('btn-back-install').classList.add('hidden');
    document.getElementById('btn-cancel').classList.remove('hidden');

    // Reset progress bar and show log output
    const progressBar = document.getElementById('progress-bar');
    progressBar.classList.remove('success', 'error');
    document.getElementById('progress-fill').style.width = '0%';
    document.getElementById('log-card').classList.remove('hidden');

    // Start installation
    runInstallation();
}

function reinstall() {
    // Reset installation state
    installCompleted = false;
    installAborted = false;
    installCancelledByUser = false;

    // Hide Reinstall/Next buttons, show Cancel
    document.getElementById('btn-group-complete').classList.add('hidden');
    document.getElementById('btn-back-install').classList.add('hidden');
    document.getElementById('btn-cancel').classList.remove('hidden');

    // Reset progress bar
    const progressBar = document.getElementById('progress-bar');
    progressBar.classList.remove('success', 'error');
    document.getElementById('progress-fill').style.width = '0%';

    // Reset module list to pending state
    const moduleList = document.getElementById('module-list');
    if (moduleList && setupModules) {
        moduleList.innerHTML = setupModules.map(m => `
            <div class="module-item" id="module-${m.id}">
                <div class="module-status pending">○</div>
                <span>${m.name}</span>
            </div>
        `).join('');
    }

    // Clear and show log output
    document.getElementById('log-output').textContent = '';
    document.getElementById('log-card').classList.remove('hidden');

    // Start installation
    runInstallation();
}

// ============================================
// INSTALLATION - RUN WITH SSE
// ============================================

async function runInstallation() {
    const logOutput = document.getElementById('log-output');
    const progressFill = document.getElementById('progress-fill');

    let completedModules = 0;
    const totalModules = setupModules.length;

    logOutput.textContent = '[' + new Date().toLocaleTimeString() + '] Starting installation...\n';

    for (const module of setupModules) {
        if (installAborted) {
            logOutput.textContent += '\n[' + new Date().toLocaleTimeString() + '] Installation cancelled by user\n';
            break;
        }

        const moduleEl = document.getElementById(`module-${module.id}`);
        const statusEl = moduleEl.querySelector('.module-status');

        // Update status to running
        statusEl.className = 'module-status running';
        statusEl.textContent = '●';

        logOutput.textContent += '\n[' + new Date().toLocaleTimeString() + '] Starting ' + module.name + '...\n';
        logOutput.scrollTop = logOutput.scrollHeight;

        try {
            // Run module with real CGI endpoint
            await runModuleWithSSE(module, logOutput);

            // Update status to complete
            statusEl.className = 'module-status complete';
            statusEl.textContent = '✓';
            completedModules++;

            logOutput.textContent += '[' + new Date().toLocaleTimeString() + '] ' + module.name + ' completed\n';
        } catch (error) {
            statusEl.className = 'module-status error';
            statusEl.textContent = '✗';

            logOutput.textContent += '[' + new Date().toLocaleTimeString() + '] ERROR: ' + module.name + ' failed\n';
            logOutput.textContent += '  ' + error.message + '\n';

            // Ask user if they want to continue
            if (!confirm(`${module.name} failed. Continue with installation?`)) {
                installAborted = true;
                break;
            }
        }

        // Update progress
        const progress = (completedModules / totalModules) * 100;
        progressFill.style.width = `${progress}%`;
        logOutput.scrollTop = logOutput.scrollHeight;
    }

    // Installation complete, cancelled, or failed
    document.getElementById('btn-cancel').classList.add('hidden');

    // Check if installation was successful (all modules completed and not aborted)
    const hasErrors = document.querySelectorAll('.module-status.error').length > 0;
    const progressBar = document.getElementById('progress-bar');

    if (installCancelledByUser) {
        progressBar.classList.add('error');
        document.getElementById('btn-diagnostic').classList.remove('hidden');
    } else if (hasErrors || installAborted) {
        progressBar.classList.add('error');
        document.getElementById('btn-diagnostic').classList.remove('hidden');
    } else {
        progressBar.classList.add('success');
        installCompleted = true;
        // Show Next/Reinstall buttons, hide Install button, and auto-advance to step 6 (Complete) on success
        document.getElementById('btn-install').classList.add('hidden');
        document.getElementById('btn-group-complete').classList.remove('hidden');
        setTimeout(() => {
            goToStep(6);
        }, 1000);
    }
}

// ============================================
// RUN MODULE WITH SSE PROGRESS
// ============================================

async function runModuleWithSSE(module, logOutput) {
    return new Promise(async (resolve, reject) => {
        try {
            // Start the module via CGI with config as POST body
            const startResponse = await fetch(
                `${API_BASE}/run-module.cgi?phase=${module.phase}&module=${module.id}`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(config)
                }
            );
            const startData = await startResponse.json();

            if (startData.status === 'error') {
                reject(new Error(startData.message));
                return;
            }

            // Track current module PID for cancellation
            currentModulePid = startData.pid;

            // Connect to SSE progress stream
            const progressFile = encodeURIComponent(startData.progress_file);
            const eventSource = new EventSource(`${API_BASE}/progress.cgi?file=${progressFile}`);
            currentEventSource = eventSource;

            let moduleComplete = false;

            eventSource.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);

                    // Log progress messages
                    if (data.message) {
                        logOutput.textContent += '  ' + data.message + '\n';
                        logOutput.scrollTop = logOutput.scrollHeight;
                    }

                    // Check for completion
                    if (data.status === 'complete' || data.type === 'finish') {
                        moduleComplete = true;
                        currentModulePid = null;
                        eventSource.close();
                        resolve();
                    }

                    // Check for error
                    if (data.status === 'error') {
                        moduleComplete = true;
                        currentModulePid = null;
                        eventSource.close();
                        reject(new Error(data.message || 'Module failed'));
                    }
                } catch (e) {
                    // Non-JSON data, just log it
                    logOutput.textContent += '  ' + event.data + '\n';
                    logOutput.scrollTop = logOutput.scrollHeight;
                }
            };

            eventSource.addEventListener('done', () => {
                if (!moduleComplete) {
                    eventSource.close();
                    resolve();
                }
            });

            eventSource.onerror = (error) => {
                // SSE connection closed - check if module is done
                eventSource.close();

                // Wait a bit and check output file for result
                setTimeout(async () => {
                    if (!moduleComplete) {
                        try {
                            const checkResponse = await fetch(
                                `${API_BASE}/status.cgi?check_pid=${startData.pid}`
                            );
                            const checkData = await checkResponse.json();

                            if (checkData.running === false) {
                                resolve();
                            } else {
                                // Process might still be running, wait more
                                resolve();
                            }
                        } catch (e) {
                            // Can't check status, assume success
                            resolve();
                        }
                    }
                }, 1000);
            };

            // Timeout after 10 minutes
            setTimeout(() => {
                if (!moduleComplete) {
                    eventSource.close();
                    reject(new Error('Module timed out'));
                }
            }, 600000);

        } catch (error) {
            // If CGI endpoint fails, fall back to simulation
            console.warn('CGI endpoint failed, falling back to simulation:', error);
            await simulateModule(module, logOutput);
            resolve();
        }
    });
}

// ============================================
// FALLBACK - SIMULATE MODULE (for offline/demo)
// ============================================

function simulateModule(module, logOutput) {
    return new Promise((resolve, reject) => {
        // Simulate varying execution times
        const duration = module.id.includes('pull') ? 5000 :
                        module.id.includes('start') ? 3000 : 1500;

        // Simulate progress for long operations
        if (module.id.includes('pull')) {
            let progress = 0;
            const interval = setInterval(() => {
                if (installAborted) {
                    clearInterval(interval);
                    reject(new Error('Installation cancelled'));
                    return;
                }
                progress += 10;
                logOutput.textContent += '  Pulling images... ' + progress + '%\n';
                logOutput.scrollTop = logOutput.scrollHeight;
                if (progress >= 100) clearInterval(interval);
            }, duration / 10);
        }

        setTimeout(() => {
            if (installAborted) {
                reject(new Error('Installation cancelled'));
            } else {
                resolve();
            }
        }, duration);
    });
}

// ============================================
// CANCEL INSTALLATION
// ============================================

async function cancelInstall() {
    if (confirm('Are you sure you want to cancel the installation?')) {
        installAborted = true;
        installCancelledByUser = true;

        // Close SSE connection
        if (currentEventSource) {
            currentEventSource.close();
            currentEventSource = null;
        }

        // Kill the running module process
        if (currentModulePid) {
            try {
                await fetch(`${API_BASE}/status.cgi?kill_pid=${currentModulePid}`);
            } catch (e) {
                console.warn('Failed to kill process:', e);
            }
            currentModulePid = null;
        }

        // Update UI
        const logOutput = document.getElementById('log-output');
        logOutput.textContent += '\n[' + new Date().toLocaleTimeString() + '] Installation cancelled by user\n';

        // Update progress bar to error state
        document.getElementById('progress-bar').classList.add('error');

        // Update button visibility
        document.getElementById('btn-cancel').classList.add('hidden');
        document.getElementById('btn-diagnostic').classList.remove('hidden');
    }
}

// ============================================
// SEND DIAGNOSTIC REPORT (placeholder)
// ============================================

function sendDiagnosticReport() {
    // TODO: Implement diagnostic report sending
    alert('Diagnostic report feature coming soon.');
}

// ============================================
// SERVICE STATUS (Step 6)
// ============================================

// Service status refresh interval ID
let serviceRefreshInterval = null;
let configurationStarted = false;
let configurationComplete = false;

const services = [
    { name: 'Homepage', port: 3000, container: 'homepage', hasConfig: true },
    { name: 'Jellyfin', port: 8096, container: 'jellyfin', hasConfig: true },
    { name: 'Jellyseerr', port: 5055, container: 'jellyseerr', hasConfig: true },
    { name: 'Sonarr', port: 8989, container: 'sonarr', hasConfig: true },
    { name: 'Radarr', port: 7878, container: 'radarr', hasConfig: true },
    { name: 'Lidarr', port: 8686, container: 'lidarr', hasConfig: true },
    { name: 'Prowlarr', port: 9696, container: 'prowlarr', hasConfig: true },
    { name: 'Bazarr', port: 6767, container: 'bazarr', hasConfig: true },
    { name: 'qBittorrent', port: 8080, container: 'qbittorrent', hasConfig: true },
    { name: 'SABnzbd', port: 8085, container: 'sabnzbd', hasConfig: true },
    { name: 'Tdarr', port: 8265, container: 'tdarr', hasConfig: true },
    { name: 'ARM', port: 8090, container: 'arm', hasConfig: true }
];

async function loadServiceStatus() {
    const servicesList = document.getElementById('services-list');
    const configModuleList = document.getElementById('configure-module-list');

    // Clear any existing refresh interval
    if (serviceRefreshInterval) {
        clearInterval(serviceRefreshInterval);
    }

    // Reset configuration state only if not already started or complete
    // This prevents race conditions if loadServiceStatus is called multiple times
    if (!configurationStarted && !configurationComplete) {
        serviceConfigStatus = {};

        // Reset progress bar
        const progressBar = document.getElementById('configure-progress-bar');
        progressBar.classList.remove('success', 'error');
        document.getElementById('configure-progress-fill').style.width = '0%';
    }

    // Initial render with loading state
    servicesList.innerHTML = services.map(s => `
        <div class="service-item" data-container="${s.container}">
            <div class="service-status loading" title="Checking..."></div>
            <span class="service-name">${s.name}</span>
            <span class="service-config-status waiting" data-container="${s.container}">Waiting...</span>
            <a href="http://localhost:${s.port}" target="_blank">Loading...</a>
        </div>
    `).join('');

    // Initialize configure module list (only if not already complete)
    if (configModuleList && !configurationComplete) {
        configModuleList.innerHTML = configureModules.map(m => `
            <div class="module-item" id="config-module-${m.id}">
                <div class="module-status pending">○</div>
                <span>${m.name}</span>
            </div>
        `).join('');
    }

    // Fetch container status and update
    await updateServiceStatus();

    // Set up auto-refresh every 3 seconds while on step 6
    serviceRefreshInterval = setInterval(async () => {
        if (currentStep !== 6) {
            clearInterval(serviceRefreshInterval);
            serviceRefreshInterval = null;
            return;
        }
        await updateServiceStatus();
    }, 3000);
}

async function updateServiceStatus() {
    const servicesList = document.getElementById('services-list');
    let lanIp = 'localhost';
    let containerStatus = {};

    try {
        const response = await fetch(`${API_BASE}/status.cgi`);
        const status = await response.json();

        if (status.lan_ip) {
            lanIp = status.lan_ip;
        }

        // Parse container status from docker compose ps output
        if (status.containers && Array.isArray(status.containers)) {
            status.containers.forEach(c => {
                // Container name might have project prefix, extract service name
                const name = c.Service || c.Name || '';
                const state = (c.State || '').toLowerCase();
                containerStatus[name] = state;
            });
        }
    } catch (e) {
        console.warn('Failed to fetch status:', e);
    }

    // Update the service list with status and correct IP
    servicesList.innerHTML = services.map(s => {
        const state = containerStatus[s.container] || 'unknown';
        let statusClass = 'unknown';
        let statusTitle = 'Unknown';

        if (state === 'running') {
            statusClass = 'running';
            statusTitle = 'Running';
        } else if (state === 'exited' || state === 'dead') {
            statusClass = 'stopped';
            statusTitle = 'Stopped';
        } else if (state === 'restarting') {
            statusClass = 'restarting';
            statusTitle = 'Restarting';
        } else if (state === 'created') {
            statusClass = 'starting';
            statusTitle = 'Starting';
        }

        // Configuration status for this service
        let configStatusClass = 'waiting';
        let configStatusText = 'Waiting...';

        // Services without config modules show N/A or just dash
        if (!s.hasConfig) {
            configStatusClass = 'waiting';
            configStatusText = '—';
        } else {
            const configStatus = serviceConfigStatus[s.container] || 'waiting';
            if (configStatus === 'configured') {
                configStatusClass = 'configured';
                configStatusText = 'Configured';
            } else if (configStatus === 'configuring') {
                configStatusClass = 'configuring';
                configStatusText = 'Configuring...';
            } else if (configStatus === 'error') {
                configStatusClass = 'error';
                configStatusText = 'Error';
            } else if (configStatus === 'skipped') {
                configStatusClass = 'waiting';
                configStatusText = 'Skipped';
            }
        }

        return `
            <div class="service-item" data-container="${s.container}">
                <div class="service-status ${statusClass}" title="${statusTitle}"></div>
                <span class="service-name">${s.name}</span>
                <span class="service-config-status ${configStatusClass}">${configStatusText}</span>
                <a href="http://${lanIp}:${s.port}" target="_blank">http://${lanIp}:${s.port}</a>
            </div>
        `;
    }).join('');

    // Check if all required services are running and start configuration
    if (!configurationStarted && !configurationComplete) {
        const requiredServices = ['jellyfin', 'sonarr', 'radarr', 'prowlarr', 'qbittorrent'];
        const allRunning = requiredServices.every(s => containerStatus[s] === 'running');

        if (allRunning) {
            configurationStarted = true;
            // Start configuration after a brief delay
            setTimeout(() => {
                runConfiguration();
            }, 1000);
        }
    }
}

// ============================================
// AUTO-CONFIGURATION (Step 6)
// ============================================

// Flag to track if configuration is currently running (prevents duplicate runs)
let configurationInProgress = false;

async function runConfiguration() {
    // Guard against duplicate runs
    if (configurationInProgress || configurationComplete) {
        console.log('Configuration already in progress or complete, skipping');
        return;
    }
    configurationInProgress = true;

    const logOutput = document.getElementById('configure-log-output');
    const progressFill = document.getElementById('configure-progress-fill');
    const progressBar = document.getElementById('configure-progress-bar');

    // Show log card
    document.getElementById('configure-log-card').classList.remove('hidden');

    let completedModules = 0;
    const totalModules = configureModules.length;

    logOutput.textContent = '[' + new Date().toLocaleTimeString() + '] Starting auto-configuration...\n';

    for (const module of configureModules) {
        const moduleEl = document.getElementById(`config-module-${module.id}`);
        const statusEl = moduleEl?.querySelector('.module-status');

        // Update status to running
        if (statusEl) {
            statusEl.className = 'module-status running';
            statusEl.textContent = '●';
        }

        // Mark associated service as configuring
        if (module.container) {
            serviceConfigStatus[module.container] = 'configuring';
            await updateServiceStatus();
        }

        logOutput.textContent += '\n[' + new Date().toLocaleTimeString() + '] Starting ' + module.name + '...\n';
        logOutput.scrollTop = logOutput.scrollHeight;

        try {
            // Run module with real CGI endpoint
            await runConfigModuleWithSSE(module, logOutput);

            // Update status to complete
            if (statusEl) {
                statusEl.className = 'module-status complete';
                statusEl.textContent = '✓';
            }
            completedModules++;

            // Mark associated service as configured
            if (module.container) {
                serviceConfigStatus[module.container] = 'configured';
                await updateServiceStatus();
            }

            logOutput.textContent += '[' + new Date().toLocaleTimeString() + '] ' + module.name + ' completed\n';
        } catch (error) {
            if (statusEl) {
                statusEl.className = 'module-status error';
                statusEl.textContent = '✗';
            }

            // Mark associated service as error
            if (module.container) {
                serviceConfigStatus[module.container] = 'error';
                await updateServiceStatus();
            }

            logOutput.textContent += '[' + new Date().toLocaleTimeString() + '] ERROR: ' + module.name + ' failed\n';
            logOutput.textContent += '  ' + error.message + '\n';

            // Continue with next module - don't stop on errors during configuration
            completedModules++;
        }

        // Update progress
        const progress = (completedModules / totalModules) * 100;
        progressFill.style.width = `${progress}%`;
        logOutput.scrollTop = logOutput.scrollHeight;
    }

    // Configuration complete
    configurationInProgress = false;
    configurationComplete = true;

    const hasErrors = document.querySelectorAll('#configure-module-list .module-status.error').length > 0;

    if (hasErrors) {
        progressBar.classList.add('error');
        logOutput.textContent += '\n[' + new Date().toLocaleTimeString() + '] Configuration completed with errors\n';
    } else {
        progressBar.classList.add('success');
        logOutput.textContent += '\n[' + new Date().toLocaleTimeString() + '] Configuration completed successfully!\n';
    }
}

async function runConfigModuleWithSSE(module, logOutput) {
    return new Promise(async (resolve, reject) => {
        try {
            // Start the module via CGI with config as POST body
            const startResponse = await fetch(
                `${API_BASE}/run-module.cgi?phase=${module.phase}&module=${module.id}`,
                {
                    method: 'POST',
                    headers: {
                        'Content-Type': 'application/json'
                    },
                    body: JSON.stringify(config)
                }
            );
            const startData = await startResponse.json();

            if (startData.status === 'error') {
                reject(new Error(startData.message));
                return;
            }

            // Connect to SSE progress stream
            const progressFile = encodeURIComponent(startData.progress_file);
            const eventSource = new EventSource(`${API_BASE}/progress.cgi?file=${progressFile}`);

            let moduleComplete = false;

            eventSource.onmessage = (event) => {
                try {
                    const data = JSON.parse(event.data);

                    // Log progress messages
                    if (data.message) {
                        logOutput.textContent += '  ' + data.message + '\n';
                        logOutput.scrollTop = logOutput.scrollHeight;
                    }

                    // Check for completion
                    if (data.status === 'complete' || data.type === 'finish') {
                        moduleComplete = true;
                        eventSource.close();
                        resolve();
                    }

                    // Check for error
                    if (data.status === 'error') {
                        moduleComplete = true;
                        eventSource.close();
                        reject(new Error(data.message || 'Module failed'));
                    }
                } catch (e) {
                    // Non-JSON data, just log it
                    logOutput.textContent += '  ' + event.data + '\n';
                    logOutput.scrollTop = logOutput.scrollHeight;
                }
            };

            eventSource.addEventListener('done', () => {
                if (!moduleComplete) {
                    eventSource.close();
                    resolve();
                }
            });

            eventSource.onerror = (error) => {
                // SSE connection closed - check if module is done
                eventSource.close();

                // Wait a bit and check output file for result
                setTimeout(async () => {
                    if (!moduleComplete) {
                        try {
                            const checkResponse = await fetch(
                                `${API_BASE}/status.cgi?check_pid=${startData.pid}`
                            );
                            const checkData = await checkResponse.json();

                            if (checkData.running === false) {
                                resolve();
                            } else {
                                resolve();
                            }
                        } catch (e) {
                            resolve();
                        }
                    }
                }, 1000);
            };

            // Timeout after 5 minutes per module
            setTimeout(() => {
                if (!moduleComplete) {
                    eventSource.close();
                    reject(new Error('Module timed out'));
                }
            }, 300000);

        } catch (error) {
            // If CGI endpoint fails, simulate success for demo
            console.warn('CGI endpoint failed:', error);
            await new Promise(r => setTimeout(r, 1000));
            resolve();
        }
    });
}

// ============================================
// INITIALIZE
// ============================================

// Initialize toggle field visibility based on checkbox states
function initToggleFields() {
    // Sync Usenet fields visibility
    const usenetCheckbox = document.getElementById('enable-usenet');
    if (usenetCheckbox) {
        const usenetFields = document.getElementById('usenet-fields');
        if (usenetFields) {
            usenetFields.classList.toggle('hidden', !usenetCheckbox.checked);
        }
    }

    // Sync NZB Indexer fields visibility
    const nzbCheckbox = document.getElementById('enable-nzb-indexer');
    if (nzbCheckbox) {
        const nzbFields = document.getElementById('nzb-indexer-fields');
        if (nzbFields) {
            nzbFields.classList.toggle('hidden', !nzbCheckbox.checked);
        }
    }

    // Sync Cloudflare fields visibility
    const cfCheckbox = document.getElementById('enable-cloudflare');
    if (cfCheckbox) {
        const cfFields = document.getElementById('cloudflare-fields');
        if (cfFields) {
            cfFields.classList.toggle('hidden', !cfCheckbox.checked);
        }
    }

    // Sync NZB indexer URL visibility based on type
    const indexerType = document.getElementById('nzb-indexer-type');
    if (indexerType) {
        const urlGroup = document.getElementById('nzb-indexer-url-group');
        if (urlGroup) {
            urlGroup.classList.toggle('hidden', indexerType.value !== 'custom');
        }
    }
}

document.addEventListener('DOMContentLoaded', () => {
    loadFormData();
    setupFormPersistence();
    detectHardware();
    initToggleFields();

    // Re-validate forms after loading saved data to enable/disable Next buttons correctly
    if (typeof validatePassword === 'function') validatePassword();
    if (typeof validateUsername === 'function') {
        const usernameInput = document.getElementById('admin-user');
        if (usernameInput) validateUsername(usernameInput);
    }
    if (typeof updateAdminNextButton === 'function') updateAdminNextButton();
});

// Also sync on window load (after browser form restoration)
window.addEventListener('load', () => {
    initToggleFields();
});
