/**
 * ═══════════════════════════════════════════════════════════════════════════
 * ART SOC Dashboard — Application Logic
 * ═══════════════════════════════════════════════════════════════════════════
 * Handles data loading, filtering, sorting, technique browsing, 
 * command generation, and MITRE ATT&CK heat map rendering.
 */

// ── State ──────────────────────────────────────────────────────────────────
const state = {
    results: null,         // Loaded results JSON
    techniques: null,      // Loaded techniques catalog
    filteredResults: [],   // Current filtered view of results
    selectedTechniques: new Set(),  // Selected technique IDs for launcher
    sortColumn: null,
    sortDirection: 'asc',
    expandedRows: new Set()
};

// ── MITRE ATT&CK Tactic Order ─────────────────────────────────────────────
const TACTIC_ORDER = [
    'Reconnaissance', 'Resource Development', 'Initial Access', 'Execution',
    'Persistence', 'Privilege Escalation', 'Defense Evasion', 'Credential Access',
    'Discovery', 'Lateral Movement', 'Collection', 'Command and Control',
    'Exfiltration', 'Impact'
];

// ═══════════════════════════════════════════════════════════════════════════
// INITIALIZATION
// ═══════════════════════════════════════════════════════════════════════════

document.addEventListener('DOMContentLoaded', () => {
    initTabs();
    initFilters();
    initLauncher();
    initFileLoader();
    loadDefaultData();
});

// ── Load default data from data/ folder ────────────────────────────────────
async function loadDefaultData() {
    try {
        const [resultsRes, techRes] = await Promise.allSettled([
            fetch('data/results.json'),
            fetch('data/techniques.json')
        ]);

        if (resultsRes.status === 'fulfilled' && resultsRes.value.ok) {
            const data = await resultsRes.value.json();
            loadResults(data);
        }

        if (techRes.status === 'fulfilled' && techRes.value.ok) {
            const data = await techRes.value.json();
            loadTechniques(data);
        }
    } catch (e) {
        console.log('No default data files found. Use file loader.');
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// TAB NAVIGATION
// ═══════════════════════════════════════════════════════════════════════════

function initTabs() {
    document.querySelectorAll('.tab-btn').forEach(btn => {
        btn.addEventListener('click', () => {
            const tabId = btn.dataset.tab;

            // Update buttons
            document.querySelectorAll('.tab-btn').forEach(b => b.classList.remove('active'));
            btn.classList.add('active');

            // Update content
            document.querySelectorAll('.tab-content').forEach(c => c.classList.remove('active'));
            document.getElementById(`tab-${tabId}`).classList.add('active');
        });
    });
}

// ═══════════════════════════════════════════════════════════════════════════
// FILE LOADER
// ═══════════════════════════════════════════════════════════════════════════

function initFileLoader() {
    document.getElementById('load-results-file').addEventListener('change', (e) => {
        const file = e.target.files[0];
        if (!file) return;

        const reader = new FileReader();
        reader.onload = (evt) => {
            try {
                const data = JSON.parse(evt.target.result);
                
                // Detect if this is a results file or techniques file
                if (data.SessionInfo && data.Results) {
                    loadResults(data);
                } else if (data.Techniques) {
                    loadTechniques(data);
                } else {
                    alert('Unrecognized JSON format. Expected results or techniques file.');
                }
            } catch (err) {
                alert('Failed to parse JSON: ' + err.message);
            }
        };
        reader.readAsText(file);
        e.target.value = ''; // Reset for re-upload
    });
}

// ═══════════════════════════════════════════════════════════════════════════
// RESULTS LOADING & DISPLAY
// ═══════════════════════════════════════════════════════════════════════════

function loadResults(data) {
    state.results = data;
    state.filteredResults = [...data.Results];
    state.expandedRows.clear();

    // Update session info
    const session = data.SessionInfo;
    document.getElementById('session-host').textContent = session.Hostname || 'Unknown';
    document.getElementById('session-bar').style.display = 'flex';
    document.getElementById('session-id').textContent = session.SessionID;
    document.getElementById('session-hostname').textContent = session.Hostname;
    document.getElementById('session-username').textContent = session.Username;
    document.getElementById('session-start').textContent = session.StartTime;
    document.getElementById('session-end').textContent = session.EndTime;

    // Update stats
    document.getElementById('stat-total').textContent = session.TotalTests;
    document.getElementById('stat-passed').textContent = session.Passed;
    document.getElementById('stat-failed').textContent = session.Failed;
    document.getElementById('stat-rate').textContent = session.SuccessRate + '%';
    document.getElementById('stat-duration').textContent = session.DurationMinutes + 'm';
    document.getElementById('stat-skipped').textContent = session.Skipped;

    // Count unique techniques
    const uniqueTechniques = new Set(data.Results.map(r => r.TechniqueID));
    document.getElementById('stat-techniques-count').textContent = uniqueTechniques.size + ' techniques';

    // Populate tactic filter
    populateTacticFilter(data.Results);

    // Render table
    renderResultsTable();

    // Update heat map if techniques are loaded
    if (state.techniques) {
        renderHeatMap();
    }
}

function populateTacticFilter(results) {
    const tactics = new Set();
    results.forEach(r => {
        if (r.Tactic) {
            r.Tactic.split(',').forEach(t => tactics.add(t.trim()));
        }
    });

    const select = document.getElementById('filter-tactic');
    // Keep "All Tactics" option
    select.innerHTML = '<option value="all">All Tactics</option>';
    
    TACTIC_ORDER.forEach(tactic => {
        if (tactics.has(tactic)) {
            const opt = document.createElement('option');
            opt.value = tactic;
            opt.textContent = tactic;
            select.appendChild(opt);
        }
    });
}

// ═══════════════════════════════════════════════════════════════════════════
// RESULTS TABLE RENDERING
// ═══════════════════════════════════════════════════════════════════════════

function renderResultsTable() {
    const tbody = document.getElementById('results-body');
    const emptyState = document.getElementById('results-empty');
    const countBadge = document.getElementById('results-count');

    if (!state.filteredResults || state.filteredResults.length === 0) {
        tbody.innerHTML = '';
        emptyState.style.display = 'block';
        countBadge.textContent = '0';
        return;
    }

    emptyState.style.display = 'none';
    countBadge.textContent = state.filteredResults.length;

    tbody.innerHTML = state.filteredResults.map((r, idx) => {
        const isExpanded = state.expandedRows.has(idx);
        const statusClass = r.Status === 'Success' ? 'success' : 'failed';
        const cleanupClass = r.CleanupStatus === 'Success' ? 'success' :
                            r.CleanupStatus === 'Failed' ? 'failed' : 'skipped';

        let html = `
            <tr class="${isExpanded ? 'expanded' : ''}" data-idx="${idx}" onclick="toggleRow(${idx})">
                <td><span class="technique-id">${escapeHtml(r.TechniqueID)}</span></td>
                <td>${escapeHtml(r.TechniqueName)}</td>
                <td><span class="tactic-tag">${escapeHtml(r.Tactic)}</span></td>
                <td class="test-name" title="${escapeHtml(r.TestName)}">${escapeHtml(r.TestName)}</td>
                <td class="timestamp">${escapeHtml(r.StartTime)}</td>
                <td>${r.Duration}s</td>
                <td><span class="status-badge ${statusClass}"><span class="badge-dot"></span>${r.Status}</span></td>
                <td><span class="status-badge ${cleanupClass}"><span class="badge-dot"></span>${r.CleanupStatus}</span></td>
            </tr>`;

        if (isExpanded) {
            html += `
            <tr class="detail-row">
                <td colspan="8">
                    <div class="detail-content">
                        <div class="detail-grid">
                            <div class="detail-section">
                                <h4>⚡ Executed Command</h4>
                                <pre>${escapeHtml(r.ExecutedCommand || 'N/A')}</pre>
                            </div>
                            <div class="detail-section">
                                <h4>📤 Command Output</h4>
                                <pre>${escapeHtml(r.CommandOutput || 'No output captured')}</pre>
                            </div>
                            <div class="detail-section">
                                <h4>🧹 Cleanup Command</h4>
                                <pre>${escapeHtml(r.CleanupCommand || 'N/A')}</pre>
                                ${r.CleanupOutput ? `<h4 style="margin-top:10px">🧹 Cleanup Output</h4><pre>${escapeHtml(r.CleanupOutput)}</pre>` : ''}
                            </div>
                            <div class="detail-section">
                                <h4>📋 Details</h4>
                                <div class="meta-row"><span class="meta-label">Test GUID</span><span class="meta-value">${escapeHtml(r.TestGUID)}</span></div>
                                <div class="meta-row"><span class="meta-label">Test Number</span><span class="meta-value">#${r.TestNumber}</span></div>
                                <div class="meta-row"><span class="meta-label">Executor</span><span class="meta-value">${escapeHtml(r.ExecutorType)}</span></div>
                                <div class="meta-row"><span class="meta-label">Start Time</span><span class="meta-value">${escapeHtml(r.StartTime)}</span></div>
                                <div class="meta-row"><span class="meta-label">End Time</span><span class="meta-value">${escapeHtml(r.EndTime)}</span></div>
                                <div class="meta-row"><span class="meta-label">Duration</span><span class="meta-value">${r.Duration}s</span></div>
                                <div class="meta-row"><span class="meta-label">Prerequisites</span><span class="meta-value">${r.PrereqsMet ? '✅ Met' : '❌ Not Met'}</span></div>
                                <div class="meta-row"><span class="meta-label">Host</span><span class="meta-value">${escapeHtml(r.Hostname)}</span></div>
                                <div class="meta-row"><span class="meta-label">User</span><span class="meta-value">${escapeHtml(r.Username)}</span></div>
                                ${r.ErrorMessage ? `<div class="meta-row"><span class="meta-label">Error</span><span class="meta-value" style="color:var(--color-danger)">${escapeHtml(r.ErrorMessage)}</span></div>` : ''}
                            </div>
                        </div>
                    </div>
                </td>
            </tr>`;
        }

        return html;
    }).join('');
}

function toggleRow(idx) {
    if (state.expandedRows.has(idx)) {
        state.expandedRows.delete(idx);
    } else {
        state.expandedRows.add(idx);
    }
    renderResultsTable();
}

// ═══════════════════════════════════════════════════════════════════════════
// FILTERS
// ═══════════════════════════════════════════════════════════════════════════

function initFilters() {
    const searchInput = document.getElementById('filter-search');
    const statusFilter = document.getElementById('filter-status');
    const tacticFilter = document.getElementById('filter-tactic');
    const cleanupFilter = document.getElementById('filter-cleanup');

    const applyFilters = () => {
        if (!state.results) return;

        const search = searchInput.value.toLowerCase();
        const status = statusFilter.value;
        const tactic = tacticFilter.value;
        const cleanup = cleanupFilter.value;

        state.filteredResults = state.results.Results.filter(r => {
            // Search
            if (search) {
                const searchFields = [
                    r.TechniqueID, r.TechniqueName, r.TestName,
                    r.ExecutedCommand, r.Tactic, r.TestGUID
                ].map(f => (f || '').toLowerCase());

                if (!searchFields.some(f => f.includes(search))) return false;
            }

            // Status
            if (status !== 'all' && r.Status !== status) return false;

            // Tactic
            if (tactic !== 'all' && !(r.Tactic || '').includes(tactic)) return false;

            // Cleanup
            if (cleanup !== 'all' && r.CleanupStatus !== cleanup) return false;

            return true;
        });

        // Apply sort if active
        if (state.sortColumn) {
            sortResults(state.sortColumn, false);
        }

        state.expandedRows.clear();
        renderResultsTable();
    };

    searchInput.addEventListener('input', debounce(applyFilters, 200));
    statusFilter.addEventListener('change', applyFilters);
    tacticFilter.addEventListener('change', applyFilters);
    cleanupFilter.addEventListener('change', applyFilters);

    // Table header sort
    document.querySelectorAll('.results-table thead th').forEach(th => {
        th.addEventListener('click', () => {
            const col = th.dataset.sort;
            if (col) sortResults(col, true);
        });
    });
}

function sortResults(column, toggle) {
    if (toggle) {
        if (state.sortColumn === column) {
            state.sortDirection = state.sortDirection === 'asc' ? 'desc' : 'asc';
        } else {
            state.sortColumn = column;
            state.sortDirection = 'asc';
        }
    }

    state.filteredResults.sort((a, b) => {
        let valA = a[column] || '';
        let valB = b[column] || '';

        if (column === 'Duration') {
            valA = parseFloat(valA) || 0;
            valB = parseFloat(valB) || 0;
        } else {
            valA = String(valA).toLowerCase();
            valB = String(valB).toLowerCase();
        }

        if (valA < valB) return state.sortDirection === 'asc' ? -1 : 1;
        if (valA > valB) return state.sortDirection === 'asc' ? 1 : -1;
        return 0;
    });

    renderResultsTable();
}

// ═══════════════════════════════════════════════════════════════════════════
// TECHNIQUES BROWSER
// ═══════════════════════════════════════════════════════════════════════════

function loadTechniques(data) {
    state.techniques = data;

    document.getElementById('techniques-count').textContent = data.Techniques.length;

    // Populate tactic filter
    const tacticFilter = document.getElementById('tech-tactic-filter');
    tacticFilter.innerHTML = '<option value="all">All Tactics</option>';
    const tactics = new Set();
    data.Techniques.forEach(t => {
        if (t.Tactic) {
            t.Tactic.split(',').forEach(tc => tactics.add(tc.trim()));
        }
    });
    TACTIC_ORDER.forEach(tactic => {
        if (tactics.has(tactic)) {
            const opt = document.createElement('option');
            opt.value = tactic;
            opt.textContent = tactic;
            tacticFilter.appendChild(opt);
        }
    });

    // Init filters
    document.getElementById('tech-search').addEventListener('input', debounce(renderTechniques, 200));
    tacticFilter.addEventListener('change', renderTechniques);
    document.getElementById('tech-platform-filter').addEventListener('change', renderTechniques);

    renderTechniques();

    // Update heat map if results are loaded
    if (state.results) {
        renderHeatMap();
    }
}

function renderTechniques() {
    if (!state.techniques) return;

    const grid = document.getElementById('technique-grid');
    const emptyState = document.getElementById('techniques-empty');
    const search = document.getElementById('tech-search').value.toLowerCase();
    const tactic = document.getElementById('tech-tactic-filter').value;
    const platform = document.getElementById('tech-platform-filter').value;

    let filtered = state.techniques.Techniques.filter(t => {
        if (search) {
            const searchFields = [t.TechniqueID, t.TechniqueName, t.Tactic].map(f => (f || '').toLowerCase());
            if (!searchFields.some(f => f.includes(search))) return false;
        }
        if (tactic !== 'all' && !(t.Tactic || '').includes(tactic)) return false;
        if (platform !== 'all' && !(t.Platforms || '').toLowerCase().includes(platform)) return false;
        return true;
    });

    if (filtered.length === 0) {
        grid.innerHTML = '';
        emptyState.style.display = 'block';
        return;
    }

    emptyState.style.display = 'none';

    grid.innerHTML = filtered.map(t => {
        const isSelected = state.selectedTechniques.has(t.TechniqueID);
        const platforms = (t.Platforms || '').split(',').map(p => p.trim()).filter(Boolean);

        return `
        <div class="technique-card ${isSelected ? 'selected' : ''}" 
             onclick="toggleTechniqueSelection('${t.TechniqueID}')" 
             data-technique-id="${t.TechniqueID}">
            <div class="tech-header">
                <span class="tech-id">${escapeHtml(t.TechniqueID)}</span>
                <div class="checkbox"></div>
            </div>
            <div class="tech-name">${escapeHtml(t.TechniqueName)}</div>
            <div><span class="tactic-tag">${escapeHtml(t.Tactic)}</span></div>
            <div class="tech-tests">${t.TestCount} test${t.TestCount !== 1 ? 's' : ''} available</div>
            <div class="tech-platform">
                ${platforms.map(p => `<span class="platform-tag">${escapeHtml(p)}</span>`).join('')}
            </div>
        </div>`;
    }).join('');
}

function toggleTechniqueSelection(techId) {
    if (state.selectedTechniques.has(techId)) {
        state.selectedTechniques.delete(techId);
    } else {
        state.selectedTechniques.add(techId);
    }
    
    renderTechniques();
    updateLauncherFromSelection();
}

function updateLauncherFromSelection() {
    const ids = [...state.selectedTechniques];
    const display = document.getElementById('selected-techniques-list');
    const input = document.getElementById('launcher-techniques');

    if (ids.length === 0) {
        display.textContent = 'None';
    } else {
        display.textContent = ids.join(', ');
        input.value = ids.join(',');
    }
}

// ═══════════════════════════════════════════════════════════════════════════
// ATTACK LAUNCHER / COMMAND GENERATOR
// ═══════════════════════════════════════════════════════════════════════════

function initLauncher() {
    // Toggle switches
    document.querySelectorAll('.toggle').forEach(toggle => {
        toggle.addEventListener('click', () => {
            const isActive = toggle.classList.toggle('active');
            toggle.dataset.value = isActive ? 'true' : 'false';

            // Update labels
            const labelId = toggle.id.replace('toggle-', '') + '-label';
            const label = document.getElementById(labelId);
            if (label) {
                label.textContent = isActive ? 'Enabled' : 'Disabled';
            }
        });
    });

    // Generate command button
    document.getElementById('btn-generate-command').addEventListener('click', generateCommand);

    // Copy button
    document.getElementById('btn-copy-command').addEventListener('click', copyCommand);

    // Clear tactic when techniques are entered and vice versa
    document.getElementById('launcher-techniques').addEventListener('input', () => {
        document.getElementById('launcher-tactic').value = '';
    });
    document.getElementById('launcher-tactic').addEventListener('change', () => {
        if (document.getElementById('launcher-tactic').value) {
            document.getElementById('launcher-techniques').value = '';
        }
    });
}

function generateCommand() {
    const techIds = document.getElementById('launcher-techniques').value.trim();
    const tactic = document.getElementById('launcher-tactic').value;
    const delay = document.getElementById('launcher-delay').value;
    const autoCleanup = document.getElementById('toggle-cleanup').dataset.value === 'true';
    const skipPrereqs = document.getElementById('toggle-prereqs').dataset.value === 'true';
    const exportExcel = document.getElementById('toggle-excel').dataset.value === 'true';

    if (!techIds && !tactic) {
        alert('Please enter technique IDs or select a tactic.');
        return;
    }

    let cmd = '.\\Invoke-ARTAutomation.ps1';

    if (techIds) {
        cmd += ` -TechniqueIds "${techIds}"`;
    } else if (tactic) {
        cmd += ` -Tactic "${tactic}"`;
    }

    cmd += ` -DelayBetweenTests ${delay}`;
    cmd += ` -AutoCleanup:$${autoCleanup}`;
    
    if (skipPrereqs) {
        cmd += ' -SkipPrereqCheck';
    }

    cmd += ` -ExportExcel:$${exportExcel}`;

    // Show output
    const outputDiv = document.getElementById('command-output');
    const preEl = document.getElementById('generated-command');
    
    preEl.textContent = `# ART Automation — Generated Command\n# Run this on your target VM in PowerShell (Admin)\n\ncd C:\\path\\to\\ART\\scripts\n${cmd}`;
    outputDiv.style.display = 'block';

    // Reset copy button
    const copyBtn = document.getElementById('btn-copy-command');
    copyBtn.textContent = '📋 Copy';
    copyBtn.classList.remove('copied');
}

function copyCommand() {
    const text = document.getElementById('generated-command').textContent;
    navigator.clipboard.writeText(text).then(() => {
        const btn = document.getElementById('btn-copy-command');
        btn.textContent = '✅ Copied!';
        btn.classList.add('copied');
        setTimeout(() => {
            btn.textContent = '📋 Copy';
            btn.classList.remove('copied');
        }, 2000);
    });
}

// ═══════════════════════════════════════════════════════════════════════════
// MITRE ATT&CK HEAT MAP
// ═══════════════════════════════════════════════════════════════════════════

function renderHeatMap() {
    const grid = document.getElementById('heatmap-grid');
    const emptyState = document.getElementById('heatmap-empty');

    // Build a map of tested techniques and their results
    const testedMap = {};
    if (state.results && state.results.Results) {
        state.results.Results.forEach(r => {
            if (!testedMap[r.TechniqueID]) {
                testedMap[r.TechniqueID] = { passed: 0, failed: 0, tactic: r.Tactic };
            }
            if (r.Status === 'Success') testedMap[r.TechniqueID].passed++;
            else testedMap[r.TechniqueID].failed++;
        });
    }

    // Build technique-to-tactic map from techniques catalog
    const tacticTechniques = {};
    TACTIC_ORDER.forEach(t => tacticTechniques[t] = []);

    if (state.techniques && state.techniques.Techniques) {
        state.techniques.Techniques.forEach(t => {
            const tactics = (t.Tactic || 'Unknown').split(',').map(x => x.trim());
            tactics.forEach(tactic => {
                if (tacticTechniques[tactic]) {
                    tacticTechniques[tactic].push(t.TechniqueID);
                }
            });
        });
    }

    // Also add tested techniques that might not be in the catalog
    Object.keys(testedMap).forEach(techId => {
        const tactics = (testedMap[techId].tactic || 'Unknown').split(',').map(x => x.trim());
        tactics.forEach(tactic => {
            if (tacticTechniques[tactic] && !tacticTechniques[tactic].includes(techId)) {
                tacticTechniques[tactic].push(techId);
            }
        });
    });

    // Check if we have any data
    const hasData = Object.values(tacticTechniques).some(arr => arr.length > 0);
    if (!hasData) {
        grid.innerHTML = '';
        emptyState.style.display = 'block';
        return;
    }

    emptyState.style.display = 'none';

    // Render grid
    grid.innerHTML = TACTIC_ORDER.map(tactic => {
        const techniques = [...new Set(tacticTechniques[tactic])].sort();
        
        let cellsHtml = techniques.map(techId => {
            const tested = testedMap[techId];
            let cssClass = 'untested';
            let title = `${techId} — Not tested`;

            if (tested) {
                if (tested.failed === 0) {
                    cssClass = 'tested-pass';
                    title = `${techId} — All ${tested.passed} tests passed`;
                } else if (tested.passed === 0) {
                    cssClass = 'tested-fail';
                    title = `${techId} — All ${tested.failed} tests failed`;
                } else {
                    cssClass = 'tested-mixed';
                    title = `${techId} — ${tested.passed} passed, ${tested.failed} failed`;
                }
            }

            return `<div class="heatmap-cell ${cssClass}" title="${title}">${techId.replace('T','')}</div>`;
        }).join('');

        if (techniques.length === 0) {
            cellsHtml = '<div class="heatmap-cell untested" style="opacity:0.3">—</div>';
        }

        return `
        <div class="heatmap-column">
            <div class="heatmap-header">${tactic}</div>
            ${cellsHtml}
        </div>`;
    }).join('');
}

// ═══════════════════════════════════════════════════════════════════════════
// UTILITIES
// ═══════════════════════════════════════════════════════════════════════════

function escapeHtml(str) {
    if (!str) return '';
    const div = document.createElement('div');
    div.textContent = str;
    return div.innerHTML;
}

function debounce(fn, delay) {
    let timer;
    return (...args) => {
        clearTimeout(timer);
        timer = setTimeout(() => fn(...args), delay);
    };
}
