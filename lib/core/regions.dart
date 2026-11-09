/// ThinQ API base URLs by region (see "Base URL" tag in openapi.json).
enum ThinqRegion {
  america('America', 'https://api-aic.lgthinq.com'),
  asiaPacific('Ásia e Pacífico', 'https://api-kic.lgthinq.com'),
  europe('Europa, Oriente Médio e África', 'https://api-eic.lgthinq.com');

  const ThinqRegion(this.label, this.baseUrl);
  final String label;
  final String baseUrl;

  static ThinqRegion fromName(String? name) => ThinqRegion.values.firstWhere(
        (r) => r.name == name,
        orElse: () => ThinqRegion.america,
      );
}
