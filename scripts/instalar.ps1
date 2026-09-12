<#
.SYNOPSIS
  Copia los archivos del taller dentro del proyecto de Open Industry Project.

.DESCRIPTION
  El repo no contiene el proyecto de OIP (pesa ~550 MB y no es nuestro).
  Contiene solo los archivos propios, que hay que superponer sobre el proyecto
  base de OIP respetando las rutas:

      demos\height_sorter\   la escena y el programa ST
      tools\                 las herramientas de verificacion
      oip_data\              la configuracion de comunicaciones (tags)

  Se puede correr las veces que haga falta: sobreescribe, no anida.

.PARAMETER Proyecto
  Ruta a la carpeta del proyecto de OIP (la que contiene project.godot).

.EXAMPLE
  .\scripts\instalar.ps1 -Proyecto C:\OIP\default_project
#>
param(
    [Parameter(Mandatory = $true)]
    [string]$Proyecto
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot

if (-not (Test-Path -LiteralPath (Join-Path $Proyecto 'project.godot'))) {
    throw "No encuentro project.godot en '$Proyecto'. Esa no es la carpeta del proyecto de OIP."
}
if (-not (Test-Path -LiteralPath (Join-Path $Proyecto 'parts\BeltConveyor.tscn'))) {
    throw "'$Proyecto' no parece el proyecto de Open Industry Project (falta parts\BeltConveyor.tscn)."
}

foreach ($carpeta in 'demos', 'tools', 'oip_data') {
    $origen  = Join-Path $repo $carpeta
    $destino = Join-Path $Proyecto $carpeta
    # Se crea el destino y se copia el CONTENIDO: asi una segunda corrida
    # sobreescribe en lugar de anidar demos\demos\.
    New-Item -ItemType Directory -Path $destino -Force | Out-Null
    Copy-Item -Path (Join-Path $origen '*') -Destination $destino -Recurse -Force
    Write-Host "  copiado  $carpeta\"
}

Write-Host ""
Write-Host "Listo. Abri el proyecto con el editor de OIP y despues la escena" -ForegroundColor Green
Write-Host "res://demos/height_sorter/HeightSorter.tscn"
