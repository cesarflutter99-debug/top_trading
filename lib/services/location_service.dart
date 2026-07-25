import 'package:geolocator/geolocator.dart';

class LocationService {
  /// Solicita permiso y devuelve la posición actual.
  /// Si el usuario deniega el GPS, lanza una excepción para que la UI
  /// pida ubicación manual (según regla de negocio del Doc 2).
  Future<Position> obtenerUbicacionActual() async {
    final habilitado = await Geolocator.isLocationServiceEnabled();
    if (!habilitado) {
      throw Exception('GPS desactivado');
    }

    LocationPermission permiso = await Geolocator.checkPermission();
    if (permiso == LocationPermission.denied) {
      permiso = await Geolocator.requestPermission();
      if (permiso == LocationPermission.denied) {
        throw Exception('Permiso de ubicación denegado');
      }
    }

    if (permiso == LocationPermission.deniedForever) {
      throw Exception('Permiso de ubicación denegado permanentemente');
    }

    return Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.medium,
    );
  }
}
