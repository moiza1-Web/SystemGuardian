# SystemGuardian/Modules/Dashboard.psm1
# Interactive HTML Dashboard – Fixed special characters
# Version: 1.1.0 (now uses shared Core modules instead of local copies)

Import-Module (Join-Path $PSScriptRoot "Logger.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Progress.psm1") -Force
Import-Module (Join-Path $PSScriptRoot "Utils.psm1") -Force

function Invoke-Dashboard {
    <#
    .SYNOPSIS
        Generates an interactive HTML dashboard with search, sorting, filtering, and charts
    #>

    $script:ModuleDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
    $script:ProjectRoot = Split-Path -Parent $script:ModuleDir
    $script:OutputCSV = Join-Path $script:ProjectRoot "Output\CSV"

    if (-not (Test-Path $script:OutputCSV)) {
        Write-Warning "No CSV data found. Run Storage and other modules first."
        return $false
    }

    $paths = Initialize-ModulePaths -ModuleRoot $script:ModuleDir
    $script:OutputHTML = $paths.OutputHTML

    # Write-Log and Write-ProgressEx now come from Logger.psm1 and
    # Progress.psm1 (imported above).

    Write-Log "Starting Dashboard Generation" "Info"

    # Read-CsvSafely now comes from Utils.psm1 (imported above).

    Write-ProgressEx -Activity "Dashboard" -Status "Loading data..." -PercentComplete 10

    $driveUsage = Read-CsvSafely (Join-Path $script:OutputCSV "DriveUsage.csv")
    $largeFiles = Read-CsvSafely (Join-Path $script:OutputCSV "LargeFiles.csv") | Select-Object -First 50
    $largeFolders = Read-CsvSafely (Join-Path $script:OutputCSV "LargeFolders.csv") | Select-Object -First 30
    $oldFiles = Read-CsvSafely (Join-Path $script:OutputCSV "OldFiles.csv") | Select-Object -First 30
    $tempFiles = Read-CsvSafely (Join-Path $script:OutputCSV "TempFiles.csv") | Select-Object -First 30
    $browserCache = Read-CsvSafely (Join-Path $script:OutputCSV "BrowserCache.csv")
    $duplicates = Read-CsvSafely (Join-Path $script:OutputCSV "Duplicates.csv") | Select-Object -First 100
    $recommendations = Read-CsvSafely (Join-Path $script:OutputCSV "ReviewRecommended.csv")
    $systemInfo = Read-CsvSafely (Join-Path $script:OutputCSV "SystemInfo.csv")

    $jsonData = @{
        driveUsage = $driveUsage
        largeFiles = $largeFiles
        largeFolders = $largeFolders
        oldFiles = $oldFiles
        tempFiles = $tempFiles
        browserCache = $browserCache
        duplicates = $duplicates
        recommendations = $recommendations
        systemInfo = $systemInfo
    } | ConvertTo-Json -Depth 5

    Write-ProgressEx -Activity "Dashboard" -Status "Building dashboard..." -PercentComplete 30

    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $filename = "dashboard.html"
    $dashboardPath = Join-Path $script:OutputHTML $filename

    $htmlContent = @"
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>System Guardian Dashboard</title>
    <style>
        * { margin: 0; padding: 0; box-sizing: border-box; }
        body {
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            background: #0d1117;
            color: #c9d1d9;
            padding: 20px;
        }
        .container { max-width: 1440px; margin: 0 auto; }
        header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 15px;
            padding-bottom: 15px;
            border-bottom: 2px solid #30363d;
            margin-bottom: 25px;
        }
        header h1 {
            font-size: 26px;
            color: #f0f6fc;
        }
        header h1 small {
            font-size: 14px;
            font-weight: 400;
            color: #8b949e;
            margin-left: 12px;
        }
        .header-actions {
            display: flex;
            gap: 10px;
            flex-wrap: wrap;
        }
        .header-actions input, .header-actions select {
            padding: 8px 14px;
            border-radius: 6px;
            border: 1px solid #30363d;
            background: #161b22;
            color: #c9d1d9;
            font-size: 13px;
            outline: none;
            min-width: 180px;
        }
        .header-actions input:focus, .header-actions select:focus {
            border-color: #58a6ff;
        }
        .header-actions input::placeholder { color: #484f58; }
        .stats-grid {
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(170px, 1fr));
            gap: 14px;
            margin-bottom: 25px;
        }
        .stat-card {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 8px;
            padding: 16px 18px;
            transition: 0.2s;
        }
        .stat-card:hover { border-color: #58a6ff; }
        .stat-card .label { font-size: 12px; text-transform: uppercase; color: #8b949e; letter-spacing: 0.3px; }
        .stat-card .value { font-size: 24px; font-weight: 600; margin-top: 2px; }
        .stat-card .sub { font-size: 12px; color: #8b949e; margin-top: 2px; }
        .stat-card .bar {
            width: 100%;
            height: 4px;
            background: #21262d;
            border-radius: 2px;
            margin-top: 6px;
            overflow: hidden;
        }
        .stat-card .bar .fill { height: 100%; border-radius: 2px; transition: width 0.8s; }
        .stat-card .bar .fill.blue { background: #58a6ff; }
        .stat-card .bar .fill.green { background: #3fb950; }
        .stat-card .bar .fill.orange { background: #d29922; }
        .stat-card .bar .fill.red { background: #f85149; }
        .stat-card .bar .fill.purple { background: #bc8cff; }
        .section {
            background: #161b22;
            border: 1px solid #30363d;
            border-radius: 8px;
            padding: 18px 20px;
            margin-bottom: 22px;
            overflow-x: auto;
        }
        .section-header {
            display: flex;
            justify-content: space-between;
            align-items: center;
            flex-wrap: wrap;
            gap: 12px;
            margin-bottom: 14px;
        }
        .section-header h2 {
            font-size: 17px;
            font-weight: 600;
            color: #f0f6fc;
        }
        .section-header h2 span {
            font-weight: 400;
            color: #8b949e;
            font-size: 13px;
            margin-left: 8px;
        }
        .section-controls {
            display: flex;
            gap: 8px;
            flex-wrap: wrap;
        }
        .section-controls input, .section-controls select {
            padding: 5px 10px;
            border-radius: 4px;
            border: 1px solid #30363d;
            background: #0d1117;
            color: #c9d1d9;
            font-size: 12px;
            outline: none;
        }
        .section-controls input:focus, .section-controls select:focus {
            border-color: #58a6ff;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            font-size: 13px;
        }
        table th {
            text-align: left;
            padding: 8px 10px;
            background: #0d1117;
            color: #8b949e;
            font-weight: 600;
            border-bottom: 2px solid #30363d;
            cursor: pointer;
            user-select: none;
            position: sticky;
            top: 0;
        }
        table th:hover { color: #f0f6fc; }
        table td {
            padding: 6px 10px;
            border-bottom: 1px solid #21262d;
            vertical-align: middle;
        }
        table tr:hover td { background: #1c2128; }
        table .highlight { color: #f0883e; font-weight: 500; }
        table .truncate {
            max-width: 200px;
            white-space: nowrap;
            overflow: hidden;
            text-overflow: ellipsis;
            display: inline-block;
        }
        .badge {
            display: inline-block;
            font-size: 11px;
            padding: 1px 10px;
            border-radius: 20px;
            font-weight: 500;
        }
        .badge.high { background: #da3633; color: #fff; }
        .badge.medium { background: #d29922; color: #fff; }
        .badge.low { background: #238636; color: #fff; }
        .badge.blue { background: #1f6feb; color: #fff; }
        .text-muted { color: #8b949e; }
        .text-center { text-align: center; }
        .no-data { padding: 30px; text-align: center; color: #8b949e; font-size: 14px; }
        .no-data .icon { font-size: 40px; display: block; margin-bottom: 10px; }
        .flex { display: flex; align-items: center; gap: 10px; flex-wrap: wrap; }
        .mt-1 { margin-top: 6px; }
        .mt-2 { margin-top: 12px; }
        .status-danger { color: #f85149; }
        .status-warning { color: #d29922; }
        .status-success { color: #3fb950; }
        .chart-container {
            display: flex;
            flex-wrap: wrap;
            gap: 20px;
            margin-top: 10px;
        }
        .chart-box {
            flex: 1;
            min-width: 180px;
            background: #0d1117;
            border-radius: 6px;
            padding: 14px 16px;
        }
        .chart-box h4 {
            font-size: 13px;
            color: #8b949e;
            margin-bottom: 8px;
            font-weight: 400;
        }
        .chart-bar {
            display: flex;
            align-items: center;
            gap: 10px;
            margin: 4px 0;
        }
        .chart-bar .label {
            font-size: 12px;
            min-width: 60px;
            color: #8b949e;
        }
        .chart-bar .track {
            flex: 1;
            height: 6px;
            background: #21262d;
            border-radius: 3px;
            overflow: hidden;
        }
        .chart-bar .track .fill {
            height: 100%;
            border-radius: 3px;
            transition: width 0.6s;
        }
        .chart-bar .pct {
            font-size: 12px;
            min-width: 40px;
            text-align: right;
            color: #c9d1d9;
        }
        .footer {
            text-align: center;
            padding: 18px 0 8px;
            color: #8b949e;
            font-size: 12px;
            border-top: 1px solid #30363d;
            margin-top: 5px;
        }
        .footer a { color: #58a6ff; text-decoration: none; }
        .footer a:hover { text-decoration: underline; }
        @media (max-width: 768px) {
            body { padding: 12px; }
            header h1 { font-size: 20px; }
            .stats-grid { grid-template-columns: 1fr 1fr; }
            .section { padding: 12px 14px; }
            table { font-size: 12px; }
            table th, table td { padding: 5px 7px; }
            .header-actions input { min-width: 120px; }
        }
        @media (max-width: 480px) {
            .stats-grid { grid-template-columns: 1fr; }
            .chart-box { min-width: 100%; }
        }
    </style>
</head>
<body>
<div class="container">

    <header>
        <h1>🛡️ System Guardian <small>Interactive Dashboard</small></h1>
        <div class="header-actions">
            <input type="text" id="globalSearch" placeholder="🔍 Search all tables..." oninput="globalSearch(this.value)">
            <button onclick="window.location.reload()" style="padding:6px 14px;border-radius:6px;border:1px solid #30363d;background:#161b22;color:#c9d1d9;cursor:pointer;">⟳ Refresh</button>
        </div>
    </header>

    <div class="stats-grid" id="statsGrid">
        <div class="stat-card">
            <div class="label">Drives</div>
            <div class="value" id="statDrives">-</div>
            <div class="sub">Total storage</div>
        </div>
        <div class="stat-card">
            <div class="label">Used Space</div>
            <div class="value status-danger" id="statUsed">-</div>
            <div class="sub" id="statUsedPct"></div>
            <div class="bar"><div class="fill red" id="statUsedBar" style="width:0%;"></div></div>
        </div>
        <div class="stat-card">
            <div class="label">Free Space</div>
            <div class="value status-success" id="statFree">-</div>
            <div class="sub">Available</div>
        </div>
        <div class="stat-card">
            <div class="label">Large Files</div>
            <div class="value" id="statLargeFiles">-</div>
            <div class="sub">> 500 MB</div>
        </div>
        <div class="stat-card">
            <div class="label">Duplicates</div>
            <div class="value" id="statDuplicates">-</div>
            <div class="sub">Groups</div>
        </div>
        <div class="stat-card">
            <div class="label">Recommendations</div>
            <div class="value status-warning" id="statRecommendations">-</div>
            <div class="sub">Actionable insights</div>
            <div class="bar"><div class="fill orange" id="statRecBar" style="width:0%;"></div></div>
        </div>
    </div>

    <div class="section">
        <div class="section-header">
            <h2>📊 Storage Breakdown</h2>
        </div>
        <div class="chart-container" id="chartContainer">
            <div class="chart-box">
                <h4>Drive Usage</h4>
                <div id="driveChart"></div>
            </div>
            <div class="chart-box">
                <h4>Top File Categories</h4>
                <div id="categoryChart"></div>
            </div>
        </div>
    </div>

    <div class="section" id="recommendationsSection">
        <div class="section-header">
            <h2>💡 Recommendations <span>Actionable insights</span></h2>
            <div class="section-controls">
                <select id="recPriorityFilter" onchange="filterTable('recTable', 'priority', this.value)">
                    <option value="">All Priorities</option>
                    <option value="High">High</option>
                    <option value="Medium">Medium</option>
                    <option value="Low">Low</option>
                </select>
                <input type="text" id="recSearch" placeholder="Search..." oninput="filterTable('recTable', 'search', this.value)">
            </div>
        </div>
        <div id="recTableContainer"></div>
    </div>

    <div class="section">
        <div class="section-header">
            <h2>📄 Largest Files <span>Top 50</span></h2>
            <div class="section-controls">
                <input type="text" id="fileSearch" placeholder="Search..." oninput="filterTable('fileTable', 'search', this.value)">
            </div>
        </div>
        <div id="fileTableContainer"></div>
    </div>

    <div class="section">
        <div class="section-header">
            <h2>📁 Largest Folders <span>Top 30</span></h2>
            <div class="section-controls">
                <input type="text" id="folderSearch" placeholder="Search..." oninput="filterTable('folderTable', 'search', this.value)">
            </div>
        </div>
        <div id="folderTableContainer"></div>
    </div>

    <div class="section">
        <div class="section-header">
            <h2>🌐 Browser Cache</h2>
        </div>
        <div id="browserTableContainer"></div>
    </div>

    <div class="section">
        <div class="section-header">
            <h2>🖥️ System Information</h2>
        </div>
        <div id="systemInfoContainer"></div>
    </div>

    <div class="footer">
        <p>System Guardian v1.0 &bull; Generated: $timestamp &bull; <a href="#" onclick="window.print()">Print</a> &bull; <a href="#" onclick="window.close()">Close</a></p>
        <p style="font-size:11px;">Read-only &bull; Privacy-first &bull; No data modification</p>
    </div>

</div>

<script>
// ----- DATA -----
const data = $jsonData;

// ----- Helper Functions -----
function formatSize(bytes) {
    if (!bytes || bytes < 0) return '0 B';
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    let i = 0;
    let size = parseFloat(bytes);
    while (size >= 1024 && i < units.length - 1) { size /= 1024; i++; }
    return size.toFixed(1) + ' ' + units[i];
}

function makeTable(data, columns, id, sortable = true) {
    if (!data || data.length === 0) {
        return '<div class="no-data"><span class="icon">📭</span>No data available</div>';
    }
    let html = '<table id="' + id + '"><thead><tr>';
    for (let col of columns) {
        html += '<th data-col="' + col.key + '" onclick="sortTable(\'' + id + '\', \'' + col.key + '\')">' + col.label + ' ↕</th>';
    }
    html += '</tr></thead><tbody id="' + id + 'Body">';
    for (let row of data) {
        html += '<tr>';
        for (let col of columns) {
            let val = row[col.key] !== undefined ? row[col.key] : '—';
            if (col.type === 'size') {
                val = '<span class="highlight">' + formatSize(val) + '</span>';
            } else if (col.type === 'priority') {
                const cls = val === 'High' ? 'badge high' : val === 'Medium' ? 'badge medium' : 'badge low';
                val = '<span class="' + cls + '">' + val + '</span>';
            } else if (col.type === 'truncate') {
                val = '<span class="truncate" title="' + val + '">' + val + '</span>';
            } else if (col.type === 'date') {
                try { val = new Date(val).toLocaleDateString(); } catch(e) {}
            }
            html += '<td>' + val + '</td>';
        }
        html += '</tr>';
    }
    html += '</tbody></table>';
    return html;
}

function buildSystemInfo(data) {
    if (!data || data.length === 0) return '<div class="no-data">No system info available</div>';
    let html = '<table><thead><tr><th>Category</th><th>Property</th><th>Value</th></tr></thead><tbody>';
    for (let row of data) {
        html += '<tr><td>' + (row.Category || '') + '</td><td>' + (row.Property || '') + '</td><td>' + (row.Value || '') + '</td></tr>';
    }
    html += '</tbody></table>';
    return html;
}

function buildBrowserCache(data) {
    if (!data || data.length === 0) return '<div class="no-data">No browser cache data available</div>';
    let html = '<table><thead><tr><th>Browser</th><th>Profile</th><th>Cache Size</th></tr></thead><tbody>';
    for (let row of data) {
        html += '<tr><td><strong>' + (row.Browser || '') + '</strong></td><td>' + (row.Profile || '') + '</td><td><span class="highlight">' + (row.TotalCacheSizeHuman || formatSize(row.TotalCacheSize)) + '</span></td></tr>';
    }
    html += '</tbody></table>';
    return html;
}

// ----- Sorting -----
let sortState = {};

function sortTable(tableId, colKey) {
    const table = document.getElementById(tableId);
    if (!table) return;
    const tbody = document.getElementById(tableId + 'Body');
    if (!tbody) return;
    const rows = Array.from(tbody.querySelectorAll('tr'));
    if (rows.length === 0) return;

    if (!sortState[tableId]) sortState[tableId] = {};
    if (sortState[tableId].col === colKey) {
        sortState[tableId].dir = sortState[tableId].dir === 'asc' ? 'desc' : 'asc';
    } else {
        sortState[tableId] = { col: colKey, dir: 'asc' };
    }
    const dir = sortState[tableId].dir;

    const headers = table.querySelectorAll('thead th');
    let colIndex = -1;
    for (let i = 0; i < headers.length; i++) {
        if (headers[i].getAttribute('data-col') === colKey) { colIndex = i; break; }
    }
    if (colIndex === -1) return;

    rows.sort((a, b) => {
        let va = a.cells[colIndex] ? a.cells[colIndex].textContent.trim() : '';
        let vb = b.cells[colIndex] ? b.cells[colIndex].textContent.trim() : '';
        const na = parseFloat(va.replace(/,/g, ''));
        const nb = parseFloat(vb.replace(/,/g, ''));
        if (!isNaN(na) && !isNaN(nb)) {
            return dir === 'asc' ? na - nb : nb - na;
        }
        return dir === 'asc' ? va.localeCompare(vb) : vb.localeCompare(va);
    });

    rows.forEach(row => tbody.appendChild(row));
}

// ----- Filtering -----
function filterTable(tableId, type, value) {
    const tbody = document.getElementById(tableId + 'Body');
    if (!tbody) return;
    const rows = tbody.querySelectorAll('tr');
    const searchVal = (type === 'search') ? value.toLowerCase().trim() : '';
    const priorityVal = (type === 'priority') ? value : '';

    rows.forEach(row => {
        let show = true;
        if (searchVal) {
            const text = row.textContent.toLowerCase();
            if (!text.includes(searchVal)) show = false;
        }
        if (priorityVal) {
            const cells = row.querySelectorAll('td');
            let found = false;
            for (let cell of cells) {
                if (cell.textContent.trim() === priorityVal) { found = true; break; }
            }
            if (!found) show = false;
        }
        row.style.display = show ? '' : 'none';
    });
}

// ----- Global Search -----
function globalSearch(val) {
    const searchVal = val.toLowerCase().trim();
    const tables = document.querySelectorAll('table');
    tables.forEach(table => {
        const rows = table.querySelectorAll('tbody tr');
        rows.forEach(row => {
            const text = row.textContent.toLowerCase();
            row.style.display = (!searchVal || text.includes(searchVal)) ? '' : 'none';
        });
    });
}

// ----- Build Charts -----
function buildCharts() {
    const drives = data.driveUsage || [];
    const driveContainer = document.getElementById('driveChart');
    if (drives.length > 0) {
        let html = '';
        const maxSize = Math.max(...drives.map(d => parseFloat(d.TotalSize) || 0));
        for (let d of drives) {
            const total = parseFloat(d.TotalSize) || 0;
            const pct = maxSize > 0 ? (total / maxSize) * 100 : 0;
            const usedPct = parseFloat(d.PercentUsed) || 0;
            const color = usedPct > 90 ? 'red' : usedPct > 70 ? 'orange' : 'blue';
            html += '<div class="chart-bar">';
            html += '<span class="label">' + (d.Drive || '') + '</span>';
            html += '<div class="track"><div class="fill ' + color + '" style="width:' + pct + '%;"></div></div>';
            html += '<span class="pct">' + (d.TotalSizeHuman || formatSize(total)) + '</span>';
            html += '</div>';
        }
        driveContainer.innerHTML = html;
    } else {
        driveContainer.innerHTML = '<div class="no-data">No drive data</div>';
    }

    const files = data.largeFiles || [];
    const catContainer = document.getElementById('categoryChart');
    if (files.length > 0) {
        const extCount = {};
        for (let f of files) {
            const ext = (f.Extension || '').toLowerCase() || 'unknown';
            extCount[ext] = (extCount[ext] || 0) + 1;
        }
        const sorted = Object.entries(extCount).sort((a, b) => b[1] - a[1]).slice(0, 8);
        const max = sorted.length > 0 ? sorted[0][1] : 1;
        let html = '';
        const colors = ['blue', 'green', 'orange', 'red', 'purple', 'blue', 'green', 'orange'];
        for (let i = 0; i < sorted.length; i++) {
            const [ext, count] = sorted[i];
            const pct = (count / max) * 100;
            html += '<div class="chart-bar">';
            html += '<span class="label">' + ext + '</span>';
            html += '<div class="track"><div class="fill ' + colors[i % colors.length] + '" style="width:' + pct + '%;"></div></div>';
            html += '<span class="pct">' + count + '</span>';
            html += '</div>';
        }
        catContainer.innerHTML = html || '<div class="no-data">No categories</div>';
    } else {
        catContainer.innerHTML = '<div class="no-data">No file data</div>';
    }
}

// ----- Build Stats -----
function buildStats() {
    const drives = data.driveUsage || [];
    let totalSpace = 0, usedSpace = 0, freeSpace = 0;
    for (let d of drives) {
        const t = parseFloat(d.TotalSize) || 0;
        const u = parseFloat(d.UsedSpace) || 0;
        totalSpace += t;
        usedSpace += u;
        freeSpace += (t - u);
    }
    const usedPct = totalSpace > 0 ? (usedSpace / totalSpace) * 100 : 0;

    document.getElementById('statDrives').textContent = drives.length;
    document.getElementById('statUsed').textContent = formatSize(usedSpace);
    document.getElementById('statUsedPct').textContent = usedPct.toFixed(1) + '% used';
    document.getElementById('statUsedBar').style.width = Math.min(usedPct, 100) + '%';
    document.getElementById('statFree').textContent = formatSize(freeSpace);
    document.getElementById('statLargeFiles').textContent = (data.largeFiles || []).length;
    document.getElementById('statDuplicates').textContent = (data.duplicates || []).length > 0 ? (data.duplicates || []).reduce((acc, r) => { return acc + (r.TotalInGroup || 0); }, 0) : 0;
    const recs = data.recommendations || [];
    document.getElementById('statRecommendations').textContent = recs.length;
    const recHigh = recs.filter(r => r.Priority === 'High').length;
    document.getElementById('statRecBar').style.width = recs.length > 0 ? Math.min((recHigh / recs.length) * 100, 100) + '%' : '0%';

    const recContainer = document.getElementById('recTableContainer');
    if (recs.length > 0) {
        recContainer.innerHTML = makeTable(recs, [
            { key: 'Priority', label: 'Priority', type: 'priority' },
            { key: 'Category', label: 'Category' },
            { key: 'Item', label: 'Item' },
            { key: 'SizeHuman', label: 'Size', type: 'size' },
            { key: 'Reason', label: 'Reason', type: 'truncate' }
        ], 'recTable');
    } else {
        recContainer.innerHTML = '<div class="no-data"><span class="icon">✅</span>No recommendations found</div>';
    }

    const fileContainer = document.getElementById('fileTableContainer');
    const files = data.largeFiles || [];
    if (files.length > 0) {
        fileContainer.innerHTML = makeTable(files, [
            { key: 'Name', label: 'Name' },
            { key: 'Size', label: 'Size', type: 'size' },
            { key: 'Extension', label: 'Type' },
            { key: 'Directory', label: 'Location', type: 'truncate' }
        ], 'fileTable');
    } else {
        fileContainer.innerHTML = '<div class="no-data">No large files found</div>';
    }

    const folderContainer = document.getElementById('folderTableContainer');
    const folders = data.largeFolders || [];
    if (folders.length > 0) {
        folderContainer.innerHTML = makeTable(folders, [
            { key: 'Name', label: 'Name' },
            { key: 'Size', label: 'Size', type: 'size' },
            { key: 'Items', label: 'Items' }
        ], 'folderTable');
    } else {
        folderContainer.innerHTML = '<div class="no-data">No large folders found</div>';
    }

    const browserContainer = document.getElementById('browserTableContainer');
    const browsers = data.browserCache || [];
    browserContainer.innerHTML = buildBrowserCache(browsers);

    const sysContainer = document.getElementById('systemInfoContainer');
    const sysInfo = data.systemInfo || [];
    sysContainer.innerHTML = buildSystemInfo(sysInfo);
}

document.addEventListener('DOMContentLoaded', function() {
    buildStats();
    buildCharts();
});

</script>
</body>
</html>
"@

    Write-ProgressEx -Activity "Dashboard" -Status "Saving dashboard..." -PercentComplete 80

    $htmlContent | Out-File -FilePath $dashboardPath -Encoding UTF8
    Write-Log "Saved dashboard.html" "Success"

    $reportCopy = Join-Path $script:ProjectRoot "Output\Reports\dashboard.html"
    Copy-Item -Path $dashboardPath -Destination $reportCopy -Force

    Write-ProgressEx -Activity "Dashboard" -Status "Complete" -PercentComplete 100
    Write-Progress -Activity "Dashboard" -Completed

    Write-Host ""
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "DASHBOARD GENERATION COMPLETE" -ForegroundColor Yellow
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Interactive Dashboard: dashboard.html" -ForegroundColor White
    Write-Host "Location: $script:OutputHTML" -ForegroundColor White
    Write-Host ""
    Write-Host "Open dashboard: Start-Process '$dashboardPath'" -ForegroundColor Green
    Write-Host "════════════════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    return $true
}

Export-ModuleMember -Function Invoke-Dashboard