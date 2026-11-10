# aplicar_imagenes_cacheadas.ps1
#
# Cambia Image.network(  -> ImagenRed(   y   NetworkImage( -> imagenRed(
# en todos los .dart de lib\ y agrega el import. Antes hace una copia
# completa de lib\ FUERA del proyecto, por si quieres deshacerlo.
#
# Ejecutar desde D:\top_trading\top_trading, DESPUES de copiar
# imagen_red.dart a lib\core\ y de correr: flutter pub add flutter_cache_manager

$ErrorActionPreference = 'Stop'
$raiz = (Get-Location).Path

if (-not (Test-Path "$raiz\lib\core\imagen_red.dart")) {
  Write-Host "Falta lib\core\imagen_red.dart. Copialo primero." -ForegroundColor Red
  exit 1
}

# 1) Respaldo de lib\ fuera del proyecto
$sello = Get-Date -Format 'yyyyMMdd_HHmmss'
$respaldo = Join-Path (Split-Path $raiz -Parent) "respaldo_lib_$sello"
Copy-Item "$raiz\lib" $respaldo -Recurse
Write-Host "Respaldo creado en: $respaldo" -ForegroundColor Green

$utf8 = New-Object System.Text.UTF8Encoding($false)
$reImage  = '(?<![A-Za-z0-9_])Image\.network\('
$reNet    = '(?<![A-Za-z0-9_])(?:const\s+)?NetworkImage\('
$reImport = New-Object System.Text.RegularExpressions.Regex('(?m)^import ')

$archivos = Get-ChildItem "$raiz\lib" -Recurse -Filter *.dart |
  Where-Object { $_.Name -notlike '*(1)*' -and $_.Name -ne 'imagen_red.dart' }

$tocados = 0; $sitios = 0
foreach ($f in $archivos) {
  $txt = [System.IO.File]::ReadAllText($f.FullName, $utf8)
  $n1 = [regex]::Matches($txt, $reImage).Count
  $n2 = [regex]::Matches($txt, $reNet).Count
  if (($n1 + $n2) -eq 0) { continue }

  $txt = [regex]::Replace($txt, $reImage, 'ImagenRed(')
  $txt = [regex]::Replace($txt, $reNet, 'imagenRed(')

  if ($txt -notmatch 'imagen_red\.dart') {
    # ruta relativa a lib\core\imagen_red.dart segun la carpeta del archivo
    $rel = $f.DirectoryName.Substring("$raiz\lib".Length).Trim('\')
    $niveles = if ($rel -eq '') { 0 } else { ($rel -split '\\').Count }
    $ruta = ('../' * $niveles) + 'core/imagen_red.dart'
    $nl = if ($txt.Contains("`r`n")) { "`r`n" } else { "`n" }
    $txt = $reImport.Replace($txt, ("import '" + $ruta + "';" + $nl + "import "), 1)
  }

  [System.IO.File]::WriteAllText($f.FullName, $txt, $utf8)
  $tocados++; $sitios += ($n1 + $n2)
  Write-Host ("  {0}: {1} cambio(s)" -f $f.FullName.Substring($raiz.Length + 1), ($n1 + $n2))
}

Write-Host ""
Write-Host "Listo: $sitios cambios en $tocados archivos." -ForegroundColor Green
Write-Host "Ahora corre:  flutter build apk --release"
Write-Host ""
Write-Host "Para DESHACER todo:" -ForegroundColor Yellow
Write-Host "  Remove-Item '$raiz\lib' -Recurse -Force; Copy-Item '$respaldo' '$raiz\lib' -Recurse"
