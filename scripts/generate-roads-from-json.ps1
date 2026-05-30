$ErrorActionPreference = 'Stop'

$src = 'c:\Users\james\Downloads\road_network_2048x1536_studs_v1.json'
$dst = 'src/Workspace/Map/Graybox/SupportingRoutes/Layout.model.json'
$data = Get-Content $src -Raw | ConvertFrom-Json

function WorldPoint($pt) {
    $mx = [double]$pt[0]
    $mz = [double]$pt[1]
    $wx = $mx - 1024.0
    $wz = $mz - 768.0
    return @($wx, $wz)
}

function RoadColor($kind) {
    switch ($kind) {
        'primary_loop' { return @(0.20, 0.20, 0.20) }
        'primary_arterial' { return @(0.19, 0.19, 0.19) }
        'giant_route' { return @(0.28, 0.28, 0.30) }
        'secondary_connector' { return @(0.30, 0.30, 0.30) }
        'minor_spur' { return @(0.36, 0.36, 0.36) }
        'tinyfolk_lane' { return @(0.44, 0.44, 0.44) }
        default { return @(0.25, 0.25, 0.25) }
    }
}

function NewSeg($name, $width, $p0, $p1, $kind) {
    $x0 = [double]$p0[0]
    $z0 = [double]$p0[1]
    $x1 = [double]$p1[0]
    $z1 = [double]$p1[1]

    $dx = $x1 - $x0
    $dz = $z1 - $z0
    $len = [Math]::Sqrt($dx * $dx + $dz * $dz)
    if ($len -lt 0.001) { return $null }

    $yaw = [Math]::Atan2($dx, $dz) * 180.0 / [Math]::PI

    return [ordered]@{
        name       = $name
        className  = 'Part'
        properties = [ordered]@{
            Anchored     = $true
            CanCollide   = $false
            Material     = 'Asphalt'
            Transparency = 0.04
            Color        = (RoadColor $kind)
            Size         = @([Math]::Round([double]$width, 3), 1.2, [Math]::Round($len, 3))
            Orientation  = @(0, [Math]::Round($yaw, 3), 0)
            Position     = @([Math]::Round(($x0 + $x1) / 2.0, 3), 0.7, [Math]::Round(($z0 + $z1) / 2.0, 3))
        }
    }
}

$root = [ordered]@{ className = 'Model'; children = @() }
$pointCounts = @{}

foreach ($road in $data.roads) {
    $roadChildren = @()
    $pts = @()

    foreach ($pt in $road.points) {
        $pts += , (WorldPoint $pt)
        $k = '{0},{1}' -f [int]$pt[0], [int]$pt[1]
        if (-not $pointCounts.ContainsKey($k)) { $pointCounts[$k] = 0 }
        $pointCounts[$k] = [int]$pointCounts[$k] + 1
    }

    for ($i = 0; $i -lt $pts.Count - 1; $i++) {
        $seg = NewSeg ('{0}_S{1:d2}' -f $road.id, ($i + 1)) $road.widthStuds $pts[$i] $pts[$i + 1] $road.kind
        if ($null -ne $seg) { $roadChildren += , $seg }
    }

    if ($road.closed -and $pts.Count -gt 2) {
        $seg = NewSeg ('{0}_S{1:d2}' -f $road.id, $pts.Count) $road.widthStuds $pts[$pts.Count - 1] $pts[0] $road.kind
        if ($null -ne $seg) { $roadChildren += , $seg }
    }

    $roadModel = [ordered]@{
        name       = '{0}_{1}' -f $road.id, ($road.name -replace '[^A-Za-z0-9]+', '')
        className  = 'Model'
        attributes = [ordered]@{
            RoadId     = $road.id
            RoadName   = $road.name
            RoadKind   = $road.kind
            WidthStuds = [double]$road.widthStuds
            Closed     = [bool]$road.closed
            Surface    = $road.surface
        }
        children   = $roadChildren
    }

    $root.children += , $roadModel
}

$junctionChildren = @()
$jn = 1
foreach ($entry in $pointCounts.GetEnumerator() | Where-Object { $_.Value -ge 2 } | Sort-Object Key) {
    $xy = $entry.Key.Split(',')
    $x = [double]$xy[0] - 1024.0
    $z = [double]$xy[1] - 768.0

    $junctionChildren += , ([ordered]@{
            name       = 'Junction_{0:d2}' -f $jn
            className  = 'Part'
            properties = [ordered]@{
                Anchored    = $true
                CanCollide  = $false
                Material    = 'Concrete'
                Color       = @(0.14, 0.14, 0.14)
                Shape       = 'Cylinder'
                Size        = @(1.4, 34, 34)
                Orientation = @(0, 0, 90)
                Position    = @([Math]::Round($x, 3), 0.9, [Math]::Round($z, 3))
            }
        })

    $jn++
}

$root.children += , ([ordered]@{ name = 'RoadJunctions'; className = 'Model'; children = $junctionChildren })

$root | ConvertTo-Json -Depth 100 | Set-Content $dst -Encoding utf8
Write-Output ('roads={0} roadModels={1} junctions={2}' -f $data.roads.Count, $root.children.Count, $junctionChildren.Count)
