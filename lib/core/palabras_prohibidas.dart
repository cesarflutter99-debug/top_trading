// Almacena las palabras consideradas "ofensivas" en Al Lado y una utilidad
// para detectarlas en textos (comentarios de anuncios del Marketplace).
//
// La deteccion normaliza el texto (minusculas, sin tildes, sin simbolos)
// y compara cada token como palabra completa para evitar falsos positivos
// como "disputa" (contiene "puta").
//
// NOTA: la base de datos tambien rechaza estos textos en un trigger
// (parche_comentarios_anuncios.sql); este filtro es la capa de la app.

const List<String> _palabrasBase = [
  'pinga',
  'pinqa',
  'singao',
  'singado',
  'cingao',
  'cingado',
  'conio',
  'cono', // coño normalizado
  'conazo',
  'conoso',
  'verga',
  'vergon',
  'puta',
  'puto',
  'pendejo',
  'pendeja',
  'maricon',
  'maricona',
  'marica',
  'cabron',
  'cabrona',
  'carajo',
  'mierda',
  'ojete',
  'mamabicho',
  'mamahuevo',
  'mamaguevo',
  'hijueputa',
  'hpta',
  'gafo',
  'gafa',
  'pajuo',
  'pajua',
  'culero',
  'culera',
  'malparido',
];

const String _conAcentos = 'áàäâéèëêíìïîóòöôúùüûñÁÀÄÂÉÈËÊÍÌÏÎÓÒÖÔÚÙÜÛÑ';
const String _sinAcentos =
    'aaaaeeeeiiiioooouuuunAAAAEEEEIIIIOOOOUUUUN';

String _normalizar(String texto) {
  var s = texto.toLowerCase();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    final c = s[i];
    final idx = _conAcentos.indexOf(c);
    b.write(idx >= 0 ? _sinAcentos[idx] : c);
  }
  return b.toString();
}

/// Devuelve `true` si [texto] contiene alguna palabra ofensiva.
bool textoEsOfensivo(String texto) {
  final normalizado = _normalizar(texto);
  if (normalizado.trim().isEmpty) return false;
  final sinSimbolos = normalizado.replaceAll(RegExp('[^a-z]'), ' ');
  for (final palabra in _palabrasBase) {
    final forma = _normalizar(palabra).trim();
    if (forma.isEmpty) continue;
    final re = RegExp('\\b${RegExp.escape(forma)}\\b');
    if (re.hasMatch(sinSimbolos)) return true;
  }
  return false;
}

/// Devuelve el texto normalizado (minusculas, sin tildes, sin simbolos).
/// Util para tests o depuracion.
String normalizarTextoParaFiltro(String texto) => _normalizar(texto);