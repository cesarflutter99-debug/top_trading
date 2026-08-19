// provincias_cuba.dart
//
// Lista de las 16 provincias de Cuba + el municipio especial Isla de
// la Juventud. Por ahora solo La Habana tiene su lista de municipios
// completa (son los que más tráfico tienen en la app); el resto usa
// entrada de texto libre en el Paso 3 del stepper hasta que se
// carguen sus municipios acá.
//
// Para agregar los municipios de otra provincia, simplemente se
// agrega su entrada al mapa -- el Paso 3 detecta automáticamente
// si la provincia tiene lista propia (dropdown) o no (campo de texto).

const List<String> kProvinciasCuba = [
  'Pinar del Río',
  'Artemisa',
  'La Habana',
  'Mayabeque',
  'Matanzas',
  'Cienfuegos',
  'Villa Clara',
  'Sancti Spíritus',
  'Ciego de Ávila',
  'Camagüey',
  'Las Tunas',
  'Holguín',
  'Granma',
  'Santiago de Cuba',
  'Guantánamo',
  'Isla de la Juventud',
];

/// Provincias que ya tienen su lista de municipios cargada -- el
/// resto cae a campo de texto libre en el formulario.
const Map<String, List<String>> kMunicipiosPorProvincia = {
  'La Habana': [
    'Playa',
    'Plaza de la Revolución',
    'Centro Habana',
    'Habana Vieja',
    'Regla',
    'Habana del Este',
    'Guanabacoa',
    'San Miguel del Padrón',
    'Diez de Octubre',
    'Cerro',
    'Marianao',
    'La Lisa',
    'Boyeros',
    'Arroyo Naranjo',
    'Cotorro',
  ],
};

/// true si esta provincia ya tiene municipios cargados (dropdown);
/// false si todavía debe pedirse como texto libre.
bool tieneMunicipiosCargados(String provincia) =>
    kMunicipiosPorProvincia.containsKey(provincia);

List<String> municipiosDe(String provincia) =>
    kMunicipiosPorProvincia[provincia] ?? const [];
