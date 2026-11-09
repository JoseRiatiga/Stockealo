/// Versión con la que se compiló esta app. Debe ser igual a `version:` de
/// pubspec.yaml (lo comprueba test/core/app_version_test.dart).
///
/// En la web, PackageInfo lee el version.json del servidor, que es la versión
/// publicada y no la que está corriendo; por eso el aviso de versión nueva de la
/// web compara contra esta constante.
const String kAppVersion = '0.11.0';
const int kAppBuildNumber = 36;
