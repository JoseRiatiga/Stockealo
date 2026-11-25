/// Fuera de la web no hay barra de direcciones que limpiar
void showCleanStoreUrl(String slug) {}

/// Primera vez en esta visita (fase 4): fuera de la web, siempre
bool firstTimeThisVisit(String key) => true;

/// Fuera de la web no se recuerda la sede elegida
String? savedStoreBranch(String slug) => null;
void saveStoreBranch(String slug, String branchId) {}
